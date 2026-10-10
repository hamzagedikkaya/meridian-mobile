import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import 'habit_detail_sheet.dart';

/// The habits archived so far (`GET /habits?archived=true`), most recently
/// archived first (design-analysis §7.10): each one restores in a tap
/// ("Arşivden çıkar"), opens — its history, an edit — like an active one,
/// and its ⋯ deletes it for good, after a dialog that says how many logged
/// days go with it. An archived habit's chain ends on its archive day.
class ArchivedHabitsScreen extends ConsumerStatefulWidget {
  const ArchivedHabitsScreen({super.key});

  @override
  ConsumerState<ArchivedHabitsScreen> createState() =>
      _ArchivedHabitsScreenState();
}

class _ArchivedHabitsScreenState extends ConsumerState<ArchivedHabitsScreen> {
  /// Habits whose restore is on its way.
  final _restoring = <int>{};

  Future<void> _refresh() async {
    ref.read(dataSyncProvider).refresh([archivedHabitsProvider]);
    await settleRefresh([ref.read(archivedHabitsProvider.future)]);
  }

  Future<void> _restore(Habit habit) async {
    setState(() => _restoring.add(habit.id));
    await restoreHabit(ref, context, habit);
    if (mounted) setState(() => _restoring.remove(habit.id));
  }

  /// Deletes [listed] for good. The list does not say how many days it
  /// logged or which goals count it: the detail is read first, so the
  /// dialog can.
  Future<void> _delete(Habit listed) async {
    final l = context.l10n;
    Habit habit;
    try {
      habit = (await ref.read(habitDetailProvider(listed.id).future)).data;
    } catch (e) {
      if (mounted) {
        showAppSnack(
          context,
          failureMessage(e, l, fallback: l.habitsDeleteFailed),
          isError: true,
        );
      }
      return;
    }
    if (!mounted || !await confirmDeleteHabit(context, habit) || !mounted) {
      return;
    }
    deleteHabitNow(
      context,
      ref.read(deferredDeletesProvider.notifier),
      ref.read(repositoryProvider),
      habit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(archivedHabitsProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final habits = async.value == null
        ? null
        : withoutDeleted(
            async.value!.data,
            hidden,
            DataScope.habits,
            (h) => h.id,
          );

    final Widget body;
    if (async.isFirstLoad) {
      body = const _Skeleton();
    } else if (habits == null) {
      body = EmptyState.error(onRetry: _refresh);
    } else {
      body = RefreshIndicator.adaptive(
        color: context.nok.gold,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (async.refreshFailed)
              SliverToBoxAdapter(
                child: OfflineBanner(
                  lastUpdated: async.value!.at,
                  onRetry: _refresh,
                ),
              ),
            if (habits.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.archive_outlined,
                  title: l.habitsArchivedEmpty,
                  subtitle: l.habitsArchivedEmptyBody,
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  Insets.gutter,
                  Gap.md,
                  Insets.gutter,
                  Gap.x3 + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: SliverList.separated(
                  itemCount: habits.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Gap.md),
                  itemBuilder: (context, i) => _row(
                    context,
                    habits[i],
                    // Every row lays out alike: by the longest date.
                    dates: [for (final h in habits) archivedOnLabel(l, h)],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.habitsArchivedTitle)),
      body: SyncHint.over(active: async.isRefetching, child: body),
    );
  }

  Widget _row(
    BuildContext context,
    Habit habit, {
    required List<String> dates,
  }) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final restoring = _restoring.contains(habit.id);
    final tone = entityTone(habit.color, c);
    final dateLabel = archivedOnLabel(l, habit);
    final dateStyle = text.bodySmall!.copyWith(color: c.inkMid);

    final dot = Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: tone.fill, shape: BoxShape.circle),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          habit.name,
          style: text.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Gap.xxs),
        Text(dateLabel, style: dateStyle),
      ],
    );
    final restore = TextButton(
      onPressed: restoring ? null : () => _restore(habit),
      style: TextButton.styleFrom(minimumSize: Hit.minSize),
      child: Text(l.habitsUnarchive),
    );
    final more = PopupMenuButton<void>(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      icon: Icon(Icons.more_horiz_rounded, color: c.inkMid),
      itemBuilder: (_) => [
        PopupMenuItem<void>(
          onTap: () => _delete(habit),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline_rounded, color: c.error),
            title: Text(
              l.habitsDeleteForever,
              style: TextStyle(color: c.error),
            ),
          ),
        ),
      ],
    );

    return NokturnCard(
      key: ValueKey('archived-habit-${habit.id}'),
      variant: NokCardVariant.list,
      child: InkWell(
        onTap: () => showHabitDetailSheet(context, habit),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.rowH,
            Gap.sm,
            Gap.xs,
            Gap.sm,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Beside the name only while every date keeps one line next
              // to the actions; otherwise (large text, a long label) the
              // actions go under it and the name has the row's width.
              final inline = _actionsFitBeside(
                context,
                width: constraints.maxWidth,
                dates: [
                  for (final d in dates) TextSpan(text: d, style: dateStyle),
                ],
                action: l.habitsUnarchive,
              );
              if (inline) {
                return Row(
                  children: [
                    dot,
                    const SizedBox(width: Gap.md),
                    Expanded(child: info),
                    const SizedBox(width: Gap.sm),
                    restore,
                    more,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: Gap.xs,
                      end: Gap.md,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          // The dot level with the name's first line.
                          padding: const EdgeInsets.only(top: Gap.xs),
                          child: dot,
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(child: info),
                      ],
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [restore, more],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Whether the restore button and the ⋯ fit beside a name column of at
  /// least [_minInfo] dp in which each of [dates] stays on one line, in
  /// [width].
  static bool _actionsFitBeside(
    BuildContext context, {
    required double width,
    required List<TextSpan> dates,
    required String action,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double widthOf(InlineSpan span) {
      final painter = TextPainter(
        text: span,
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    final buttonStyle =
        TextButtonTheme.of(context).style?.textStyle?.resolve(const {}) ??
        Theme.of(context).textTheme.labelLarge;
    // The button's label and its 12 dp sides, then the 48 dp ⋯.
    final actions =
        widthOf(TextSpan(text: action, style: buttonStyle)) + 2 * Gap.md + 48;
    // The dot, the gaps around the name, a little slack for rounding.
    final room = width - 12 - Gap.md - Gap.sm - actions - Gap.xs;
    return room >= _minInfo * scaler.scale(1) &&
        dates.every((date) => room >= widthOf(date));
  }

  /// The narrowest the name column may get beside the actions.
  static const _minInfo = 96.0;
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return NokSkeleton(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NokturnCard(
                child: Text('██████ ████', style: text.titleMedium),
              ),
            ),
        ],
      ),
    );
  }
}
