import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import '../shell/app_tabs.dart';
import 'goal_card.dart';
import 'goal_form.dart';
import 'goal_ui.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen>
    with TabRootScroll<GoalsScreen> {
  @override
  AppTab get tab => AppTab.goals;

  /// Cards play their entrance only with the first data (see [Entrance]).
  bool _firstLoad = true;

  Future<void> _refresh() async {
    Haptics.celebrate();
    refreshTab(ref, AppTab.goals);
    await settleRefresh([ref.read(goalsProvider.future)]);
  }

  void _retry() => refreshTab(ref, AppTab.goals);

  void _openForm() => openGoalForm(context);

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final async = ref.watch(goalsProvider);
    final bundle = _withoutDeleted(async.value?.data);

    if (bundle != null && _firstLoad) {
      // No setState: the cards already mounted keep playing (Entrance ignores
      // later values), and nothing else needs to rebuild for this.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _firstLoad = false;
      });
    }

    return primaryScroll(Scaffold(
      appBar: AppBar(title: Text(l.titleGoals, style: text.headlineLarge)),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        backgroundColor: c.gold,
        foregroundColor: c.onGold,
        child: const Icon(Icons.add),
      ),
      body: SyncHint.over(
        active: async.isRefetching,
        child: RefreshIndicator.adaptive(
          color: c.gold,
          onRefresh: _refresh,
          child: _body(async, bundle),
        ),
      ),
    ));
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

  Widget _body(AsyncValue<Fetched<GoalsBundle>> async, GoalsBundle? bundle) {
    final l = context.l10n;
    if (bundle == null) {
      if (async.isFirstLoad) return const _GoalsSkeleton();
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: EmptyState(
              icon: Icons.cloud_off,
              title: l.errServerUnreachable,
              subtitle: l.errCheckWifi,
              actionLabel: l.actionRetry,
              onAction: _retry,
            ),
          ),
        ],
      );
    }

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
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.flag_outlined,
              title: l.goalsSetFirst,
              subtitle: l.goalsSetFirstBody,
              actionLabel: l.goalsAdd,
              onAction: _openForm,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (bundle.active.isNotEmpty) ...[
                  SectionHeader(l.goalsSectionActive),
                  ..._activeGrid(bundle.active),
                  const SizedBox(height: 32),
                ],
                if (bundle.achieved.isNotEmpty) ...[
                  _CollapsedGoals(
                    title: l.goalsSectionAchieved,
                    goals: bundle.achieved,
                    achieved: true,
                  ),
                  const SizedBox(height: 12),
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
    final rows = <Widget>[];
    for (var i = 0; i < active.length; i += 2) {
      final left = active[i];
      final right = (i + 1 < active.length) ? active[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _staggered(i, left)),
              const SizedBox(width: 12),
              Expanded(
                child:
                    right == null ? const SizedBox() : _staggered(i + 1, right),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < active.length) rows.add(const SizedBox(height: 12));
    }
    return rows;
  }

  /// Deliberately not keyed. Each card is the only child of its slot, so a
  /// key could never follow a goal into another slot of the grid: it would
  /// only force a remount, replaying the ring's sweep from zero. Unkeyed,
  /// each slot updates in place when a refresh shifts the grid, and its ring
  /// moves from the old value to the new one.
  Widget _staggered(int index, Goal goal) => Entrance.staggered(
        play: _firstLoad,
        index: index,
        child: GoalCard(goal: goal),
      );
}

/// Collapsed achieved / abandoned section — flat rows.
class _CollapsedGoals extends StatelessWidget {
  final String title;
  final List<Goal> goals;
  final bool achieved;

  const _CollapsedGoals({
    required this.title,
    required this.goals,
    required this.achieved,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text('$title (${goals.length})', style: text.titleMedium),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final g in goals)
                  ListTile(
                    // Opens like an active goal: its details, reopening,
                    // editing, deleting.
                    onTap: () => context.push('/goals/${g.id}'),
                    minTileHeight: 48,
                    leading: Icon(
                      achieved ? Icons.check_circle : Icons.flag_outlined,
                      size: 20,
                      color: achieved ? c.income : c.inkLow,
                    ),
                    title: Text(
                      g.name,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      goalTargetLabel(g),
                      style: text.bodySmall!.copyWith(
                        color: achieved ? c.income : c.inkMid,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
      id: i,
      name: '',
      description: '',
      targetType: 'custom',
      status: 'active',
      color: '#D4A853',
      unit: 'birim',
      daysRemaining: 30,
      deadlineBadge: const DeadlineBadge(state: 'far', days: 30),
      targetValue: 100,
      currentValue: 40,
      progressPercent: 40,
    );

    return NokSkeleton(
      enabled: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        children: [
          SectionHeader(l.goalsSectionActive),
          for (var r = 0; r < 2; r++)...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: GoalCard(goal: bone(r * 2))),
                  const SizedBox(width: 12),
                  Expanded(child: GoalCard(goal: bone(r * 2 + 1))),
                ],
              ),
            ),
            if (r == 0) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
