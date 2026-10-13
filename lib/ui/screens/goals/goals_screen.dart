import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_typography.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/load_phase_switcher.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import 'goal_actions.dart';
import 'goal_card.dart';
import 'goal_form.dart';
import 'goal_kind_tile.dart';
import 'goal_ui.dart';

/// From this text scale the active goals stack in one column: two cards
/// side by side would leave each name a word per line and cut the longest
/// overline ("ALIŞKANLIK" needs 111 dp of a 108 dp column at 1.6×, §8.3).
const _oneColumnFrom = 1.55;

/// How many columns the active grid has at the current text scale.
int _gridColumns(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= _oneColumnFrom ? 1 : 2;

/// The Hedefler page (`/goals`), pushed over the tabs — from Today's goals,
/// the Habits menu — with the back arrow (design-analysis §6.1, §7.11).
///
/// "Yeni" in the app bar creates (no FAB: it would cover the right column's
/// badge, D37). Active goals sit in a two-column grid of [GoalCard]s, the
/// achieved and abandoned ones folded below; with no goal at all, the page
/// offers the three kinds of goal, each opening the form with its kind
/// chosen.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  Future<void> _refresh() async {
    ref.read(dataSyncProvider).refresh([goalsProvider]);
    await settleRefresh([ref.read(goalsProvider.future)]);
  }

  void _retry() => ref.read(dataSyncProvider).refresh([goalsProvider]);

  void _openForm({String? type}) => openGoalForm(context, type: type);

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final async = ref.watch(goalsProvider);
    final bundle = _withoutDeleted(async.value?.data);

    final LoadPhase phase;
    if (bundle != null) {
      phase = LoadPhase.content;
    } else if (async.isFirstLoad) {
      phase = LoadPhase.waiting;
    } else {
      phase = LoadPhase.error;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.titleGoals),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Gap.sm),
            child: TextButton.icon(
              onPressed: _openForm,
              icon: const Icon(Icons.add_rounded),
              label: Text(l.goalsNew),
            ),
          ),
        ],
      ),
      body: SyncHint.over(
        active: async.isRefetching,
        child: RefreshIndicator.adaptive(
          color: c.gold,
          // Armed (§5.8): the pull let go past its threshold.
          onRefresh: () {
            Haptics.armed();
            return _refresh();
          },
          child: LoadPhaseSwitcher(
            phase: phase,
            skeleton: (_) => const _GoalsSkeleton(),
            error: (_) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.7,
                  child: EmptyState.error(onRetry: _retry),
                ),
              ],
            ),
            content: (_) => _content(async, bundle!),
          ),
        ),
      ),
    );
  }

  /// [bundle] without the goals being deleted: they leave the grid at once.
  GoalsBundle? _withoutDeleted(GoalsBundle? bundle) {
    final hidden = ref.watch(deferredDeletesProvider);
    if (bundle == null || hidden.isEmpty) return bundle;
    List<Goal> keep(List<Goal> goals) =>
        withoutDeleted(goals, hidden, DataScope.goals, (g) => g.id);
    return GoalsBundle(
      active: keep(bundle.active),
      achieved: keep(bundle.achieved),
      abandoned: keep(bundle.abandoned),
    );
  }

  Widget _content(AsyncValue<Fetched<GoalsBundle>> async, GoalsBundle bundle) {
    final l = context.l10n;
    final empty =
        bundle.active.isEmpty &&
        bundle.achieved.isEmpty &&
        bundle.abandoned.isEmpty;

    return CustomScrollView(
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (async.refreshFailed)
          SliverToBoxAdapter(
            child: OfflineBanner(
              lastUpdated: async.value?.at ?? DateTime.now(),
              onRetry: _retry,
            ),
          ),
        if (empty)
          // At least the rest of the screen, centred, and as tall as it
          // needs at large text (a fill-remaining sliver would measure the
          // cards' text at the full width, not the empty state's 280 dp).
          SliverLayoutBuilder(
            builder: (context, constraints) => SliverToBoxAdapter(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(
                    0.0,
                    constraints.viewportMainAxisExtent -
                        constraints.precedingScrollExtent,
                  ),
                ),
                child: Center(
                  child: EmptyState(
                    icon: Icons.flag_outlined,
                    title: l.goalsSetFirst,
                    subtitle: l.goalsSetFirstBody,
                    chips: [
                      Column(
                        children: [
                          for (final type in goalKinds) ...[
                            GoalKindTile(
                              type: type,
                              onTap: () => _openForm(type: type),
                            ),
                            if (type != goalKinds.last)
                              const SizedBox(height: Gap.sm),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              Gap.lg,
              Insets.gutter,
              Gap.x5,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (bundle.active.isNotEmpty) ...[
                  SectionHeader(l.goalsSectionActive),
                  ..._activeGrid(bundle.active),
                  const SizedBox(height: Gap.x3),
                ],
                if (bundle.achieved.isNotEmpty) ...[
                  _CollapsedGoals(
                    title: l.goalsSectionAchieved,
                    goals: bundle.achieved,
                    achieved: true,
                  ),
                  const SizedBox(height: Gap.md),
                ],
                if (bundle.abandoned.isNotEmpty)
                  _CollapsedGoals(
                    title: l.goalsSectionAbandoned,
                    goals: bundle.abandoned,
                    achieved: false,
                  ),
              ]),
            ),
          ),
      ],
    );
  }

  List<Widget> _activeGrid(List<Goal> active) {
    final columns = _gridColumns(context);
    return goalGridRows([
      for (var i = 0; i < active.length; i++)
        // Deliberately not keyed. Each card is the only child of its slot,
        // so a key could never follow a goal into another slot of the
        // grid: it would only force a remount, replaying the ring's sweep
        // from zero. Unkeyed, each slot updates in place when a refresh
        // shifts the grid, and its ring moves from the old value to the
        // new one.
        Entrance.staggered(
          play: true,
          index: i,
          child: GoalCard(goal: active[i]),
        ),
    ], columns: columns);
  }
}

/// [cards] in rows of [columns], 12 dp apart both ways; the cards of a row
/// share its tallest card's height, so their rings and badges line up.
List<Widget> goalGridRows(List<Widget> cards, {required int columns}) {
  final rows = <Widget>[];
  for (var i = 0; i < cards.length; i += columns) {
    rows.add(
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) const SizedBox(width: Gap.md),
              Expanded(
                child: i + j < cards.length ? cards[i + j] : const SizedBox(),
              ),
            ],
          ],
        ),
      ),
    );
    if (i + columns < cards.length) rows.add(const SizedBox(height: Gap.md));
  }
  return rows;
}

/// Achieved or abandoned goals, folded; each row opens its goal, and a
/// long press (or its screen-reader actions) offers the goal's actions.
class _CollapsedGoals extends ConsumerWidget {
  final String title;
  final List<Goal> goals;
  final bool achieved;

  const _CollapsedGoals({
    required this.title,
    required this.goals,
    required this.achieved,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      variant: NokCardVariant.list,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        title: Text('$title (${goals.length})', style: text.titleMedium),
        childrenPadding: const EdgeInsets.only(bottom: Gap.sm),
        children: [
          for (final g in goals)
            // Opens like an active goal: its details, reopening, editing,
            // deleting.
            NokturnRow(
              onTap: () => context.push('/goals/${g.id}', extra: g),
              onLongPress: () => showGoalActions(context, ref, g),
              semanticActions: goalSemanticActions(context, ref, g),
              leading: Icon(
                achieved ? Icons.check_circle_rounded : Icons.flag_outlined,
                size: 20,
                color: achieved ? c.income : c.inkMid,
              ),
              title: g.name,
              trailing: Text(
                goalTargetLabel(g),
                style: context.nokText.numMeta.copyWith(
                  color: achieved ? c.income : c.inkMid,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GoalsSkeleton extends StatelessWidget {
  const _GoalsSkeleton();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Goal bone(int i) => Goal(
      id: -1 - i,
      name: '',
      description: '',
      targetType: 'custom',
      status: 'active',
      color: '#D4A853',
      unit: '',
      daysRemaining: null,
      targetValue: 100,
      currentValue: 40,
      progressPercent: 40,
    );

    return NokSkeleton(
      enabled: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Insets.gutter,
          Gap.lg,
          Insets.gutter,
          Gap.x5,
        ),
        children: [
          SectionHeader(l.goalsSectionActive),
          ...goalGridRows(
            [for (var i = 0; i < 4; i++) GoalCard(goal: bone(i))],
            columns: _gridColumns(context),
          ),
        ],
      ),
    );
  }
}
