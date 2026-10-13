import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api.dart';
import '../../../../core/haptics.dart';
import '../../../../data/actions.dart';
import '../../../../data/current_day.dart';
import '../../../../data/providers.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/habit.dart';
import '../../../../models/home.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../theme/app_motion.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/celebration_layer.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/nokturn_card.dart';
import '../../../widgets/section_header.dart';
import '../../habits/habit_detail_sheet.dart';
import '../../habits/habit_log_sheet.dart';
import 'home_habit_row.dart';
import 'start_card.dart';
import 'today_common.dart';

/// Today's hero (design-analysis §7.2): the day's habits.
///
/// * The header counts the day ("2/5" and a 16 dp ring); with every habit
///   done it says "Hepsi tamam" instead of showing a list to do.
/// * Open habits come first, in the server's order, at most six ("Tümü"
///   leads to the rest). A habit just checked stays in its place
///   [holdChecked], then folds into "✓ 3 tamamlandı", which opens on a tap.
/// * Checking off the day's last habit with a tap plays the day's
///   celebration from that ring ([CelebrationController.allDone]).
///
/// It reads today's habits only: ticking one rebuilds this section, not the
/// rest of Today.
class TodayHabitsSection extends ConsumerStatefulWidget {
  const TodayHabitsSection({super.key});

  /// How long a habit just checked stays among the open ones.
  static const holdChecked = Motion.holdChecked;

  /// The most open habits shown.
  static const maxOpen = 6;

  @override
  ConsumerState<TodayHabitsSection> createState() => _TodayHabitsSectionState();
}

class _TodayHabitsSectionState extends ConsumerState<TodayHabitsSection> {
  /// Habits checked by a tap here, held in place a moment.
  final _held = <int, Timer>{};
  bool _showDone = false;

  @override
  void dispose() {
    for (final timer in _held.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _hold(int id) {
    _held.remove(id)?.cancel();
    _held[id] = Timer(TodayHabitsSection.holdChecked, () {
      if (mounted) setState(() => _held.remove(id));
    });
  }

  void _release(int id) => _held.remove(id)?.cancel();

  /// Whether [habit]'s day is a count (a daily habit with a target above
  /// one) rather than done or not. `/home` does not say how often a habit
  /// repeats; the habit payloads read so far do (see `HabitCadence`). Until
  /// then the ring is done or not, which holds for any habit.
  bool _counts(HomeHabit habit) =>
      habit.targetCount > 1 &&
      (ref.read(habitActionsProvider).isDaily(habit.id) ?? false);

  List<HomeHabit> _habitsNow() =>
      ref.read(homeProvider).value?.data.todayHabits ?? const <HomeHabit>[];

  /// Logs [habit] for today here and on the Habits tab in the same frame;
  /// the server's answer then refreshes streaks, goals and the rest. A
  /// habit done or not flips; one counted several times a day goes up one
  /// per tap, and once full a tap opens its log, where it can step back.
  /// Quick taps all count (see [HabitActions]).
  ///
  /// Until it is known how often a habit with a target above one repeats,
  /// a tap still steps it up one: the server keeps any count of a weekly or
  /// monthly habit as its target, so one step is right for every cadence,
  /// whereas the target (or 0) would fill or wipe a daily count. A habit
  /// already done then opens its log instead of being cleared.
  Future<void> _toggle(HomeHabit habit, Offset origin) async {
    final counts = _counts(habit);
    final steps =
        counts ||
        (habit.targetCount > 1 &&
            ref.read(habitActionsProvider).isDaily(habit.id) == null);
    if (steps &&
        (habit.todayCount >= habit.targetCount ||
            (!counts && habit.completedToday))) {
      await showHabitLogSheet(context, habitId: habit.id);
      return;
    }
    final count = steps
        ? habit.todayCount + 1
        : (habit.completedToday ? 0 : habit.targetCount);
    final completes = !habit.completedToday && count >= habit.targetCount;
    // A step that does not finish the day ticks; the finishing tap is the
    // CheckPop's (and its haptic).
    if (steps && !completes) Haptics.tick();
    setState(() => completes ? _hold(habit.id) : _release(habit.id));

    bool allDone() {
      final all = _habitsNow();
      return all.isNotEmpty && all.every((h) => h.completedToday);
    }

    final home = ref.read(homeProvider).value?.data;
    final day = home?.today ?? ref.read<DateTime>(currentDayProvider);
    final wasAllDone = allDone();
    final request = ref
        .read(habitActionsProvider)
        .setToday(habit.id, count, day: home?.today);
    // The optimistic patch has landed by the time setToday returns: the
    // day's last habit, by the user's own tap, is celebrated (tier 2).
    final celebrations =
        !wasAllDone && allDone() ? CelebrationLayer.maybeOf(context) : null;
    // Only a day this tap claimed is given back below.
    final claimedDay =
        celebrations?.allDone(origin: origin, day: day) ?? false;
    try {
      // Refused or taken back: the day's celebration is not used up.
      if (!await request && claimedDay) celebrations?.forget(day);
    } catch (e) {
      if (claimedDay) celebrations?.forget(day);
      if (!mounted) return;
      setState(() => _release(habit.id));
      final l = context.l10n;
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.todayHabitUpdateFailed),
        isError: true,
      );
    }
  }

  /// A long press's own haptic is played where it was pressed (the row's
  /// InkWell, or the ring: see [HomeHabitRow]), once.
  void _openLog(HomeHabit habit) {
    showHabitLogSheet(context, habitId: habit.id);
  }

  /// The habit's sheet: from the Habits list when it is loaded, else drawn
  /// from Today's row until its detail lands.
  void _open(HomeHabit habit) {
    // Only a list something already keeps: reading one nobody watches
    // would start a fetch for nothing.
    final listed = ref.exists(habitsProvider)
        ? ref.read(habitsProvider).value?.data.habits
        : null;
    Habit? full;
    for (final h in listed ?? const <Habit>[]) {
      if (h.id == habit.id) full = h;
    }
    final today =
        ref.read(homeProvider).value?.data.today ??
        ref.read<DateTime>(currentDayProvider);
    final daily = ref.read(habitActionsProvider).isDaily(habit.id) ?? true;
    showHabitDetailSheet(
      context,
      full ??
          Habit(
            id: habit.id,
            name: habit.name,
            description: '',
            frequency: daily ? 'daily' : 'weekly',
            targetCount: habit.targetCount,
            color: habit.color,
            currentStreak: habit.currentStreak,
            longestStreak: habit.currentStreak,
            completionRate30d: 0,
            today: HabitToday(
              date: today,
              completed: habit.completedToday,
              count: habit.todayCount,
            ),
            chain: const [],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final habits =
        ref.watch(homeProvider.select((a) => a.value?.data.todayHabits)) ??
        const <HomeHabit>[];
    // Which habits count within the day ([_counts]): redrawn once known.
    ref.watch(habitCadenceProvider);
    final starting = ref.watch(todayStartProvider.select((p) => p != null));

    if (habits.isEmpty) {
      // The first-run card offers the habit step; nothing to repeat here.
      // Until it is known whether that card shows, nothing either: an
      // empty state it would then replace must not flash first.
      if (starting || !ref.watch(todayStartDecidedProvider)) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l.titleHabits),
          EmptyState.inline(
            icon: Icons.check_circle_outline_rounded,
            message: l.todayNoHabitsYet,
            actionLabel: l.actionAdd,
            onAction: () => showHabitStarterSheet(context),
          ),
        ],
      );
    }

    final open = [
      for (final h in habits)
        if (!h.completedToday || _held.containsKey(h.id)) h,
    ];
    final done = [
      for (final h in habits)
        if (h.completedToday && !_held.containsKey(h.id)) h,
    ];
    final doneCount = habits.where((h) => h.completedToday).length;
    final allDone = open.isEmpty;

    Widget row(HomeHabit h) => HomeHabitRow(
      key: ValueKey('habit-${h.id}'),
      habit: h,
      counts: _counts(h),
      onToggle: (origin) => _toggle(h, origin),
      onOpen: () => _open(h),
      onLongPress: () => _openLog(h),
    );

    final rows = <Widget>[
      for (final h in open.take(TodayHabitsSection.maxOpen)) row(h),
      if (done.isNotEmpty)
        _FinishedHabits(
          count: done.length,
          expanded: _showDone,
          onTap: () => setState(() => _showDone = !_showDone),
        ),
      if (done.isNotEmpty && _showDone)
        for (final h in done) row(h),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l.titleHabits,
          count: '$doneCount/${habits.length}',
          progress: doneCount / habits.length,
          trailing: allDone
              ? Padding(
                  padding: const EdgeInsets.only(left: Gap.sm),
                  child: _AllDonePill(label: l.todayAllHabitsDone),
                )
              : null,
          onSeeAll: open.length > TodayHabitsSection.maxOpen
              ? () => context.go('/habits')
              : null,
        ),
        NokturnCard(
          variant: NokCardVariant.list,
          child: todayResize(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, r) in rows.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: Insets.rowH,
                      endIndent: Insets.rowH,
                      color: c.divider,
                    ),
                  r,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Hepsi tamam" beside the section's title: a goldContainer pill with a
/// 14 dp sparkle.
class _AllDonePill extends StatelessWidget {
  const _AllDonePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: c.goldContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 14, color: c.onGoldContainer),
          const SizedBox(width: Gap.xs),
          Text(
            label,
            style: text.labelSmall!.copyWith(color: c.onGoldContainer),
          ),
        ],
      ),
    );
  }
}

/// The habits done today, folded into one 48 dp row: a check, "3
/// tamamlandı" (titleSmall inkMid) and a chevron that turns down when the
/// row is open.
class _FinishedHabits extends StatelessWidget {
  const _FinishedHabits({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return MergeSemantics(
      child: Semantics(
        button: true,
        expanded: expanded,
        onTapHint: expanded ? l.todayHideFinished : l.todayShowFinished,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Hit.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.rowH,
                vertical: Gap.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.check_rounded, size: 18, color: c.inkMid),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      l.lingeringFinished(count),
                      style: text.titleSmall!.copyWith(color: c.inkMid),
                    ),
                  ),
                  RotatedBox(
                    quarterTurns: expanded ? 1 : 0,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: c.inkLow,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
