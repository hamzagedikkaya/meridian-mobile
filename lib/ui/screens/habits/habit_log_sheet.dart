import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/actions.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/habit.dart';
import '../../../models/home.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/sync_hint.dart';
import '../today/widgets/today_common.dart';
import 'widgets/habit_check.dart';

/// Today's log of one habit, to set it exactly: a counter steps down as well
/// as up, a done day can be undone, and "Tamamla" / "Sıfırla" jump to either
/// end. What a long-press on a Today ring opens, and a tap on a counter that
/// is already full (another +1 could do nothing).
///
/// Every change writes the count the user picked (`HabitActions.setToday`),
/// shown at once here, on Today and on Habits. The sheet reads the habit
/// from `/home` as it updates, so it always shows what the server has with
/// the taps on their way on top.
///
/// [date] logs another day than today instead (any day from the habit's
/// start on, design-analysis D13): the sheet then reads the habit's day
/// from the Habits list — or, for a day before the list's two weeks, from
/// the habit's year of history — and sends the count for that day.
Future<void> showHabitLogSheet(
  BuildContext context, {
  required int habitId,
  DateTime? date,
}) {
  final c = context.nok;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    // However tall large text makes it, the sheet stops below the status
    // bar, and scrolls (see the build).
    useSafeArea: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    backgroundColor: c.surface3,
    builder: (_) => _HabitLogSheet(habitId: habitId, date: date),
  );
}

class _HabitLogSheet extends ConsumerStatefulWidget {
  final int habitId;

  /// The day logged; null: today.
  final DateTime? date;

  const _HabitLogSheet({required this.habitId, this.date});

  @override
  ConsumerState<_HabitLogSheet> createState() => _HabitLogSheetState();
}

class _HabitLogSheetState extends ConsumerState<_HabitLogSheet> {
  /// Why the last change did not go through, shown in the sheet: a
  /// snackbar would sit under it.
  String? _error;

  Future<void> _set(HomeSummary home, HomeHabit habit, int count) async {
    final l = context.l10n;
    final daily = ref.read(habitActionsProvider).isDaily(habit.id) ?? false;
    final log = habit.logFor(count, daily: daily);
    if (log.completed && !habit.completedToday) {
      Haptics.success();
    } else {
      Haptics.tick();
    }
    setState(() => _error = null);
    try {
      await ref
          .read(habitActionsProvider)
          .setToday(habit.id, count, day: home.today);
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      setState(() {
        _error = failureMessage(e, l, fallback: l.todayHabitUpdateFailed);
      });
    }
  }

  /// The past day's count as last set here: shown until the sheet closes,
  /// and what [_setPast] sends.
  int? _pastCount;

  /// Whether the past day's count is being sent.
  bool _pastSending = false;

  /// Sets the past [day] of [habit] to [count]: shown here at once, then
  /// sent with `PUT /habits/:id/logs/:date`. A change already on its way
  /// picks this one up when it is answered, so the server ends on the last
  /// one (as in the detail sheet). When a write fails, the sheet goes back
  /// to the habit's count, with the reason. The write refreshes the Habits
  /// list (its chain) and Today.
  Future<void> _setPast(Habit habit, DateTime day, int count) async {
    final l = context.l10n;
    // The check or the stepper is the feedback of the change itself.
    Haptics.tick();
    setState(() {
      _pastCount = habit.logFor(count).count;
      _error = null;
    });
    if (_pastSending) return;
    _pastSending = true;
    final repo = ref.read(repositoryProvider);
    int? sent;
    try {
      while (true) {
        final want = _pastCount;
        if (want == null || want == sent) break;
        await repo.setHabitLog(habit.id, day, count: want);
        sent = want;
      }
    } catch (e) {
      Haptics.danger();
      if (mounted) {
        setState(() {
          _pastCount = null;
          _error = failureMessage(e, l, fallback: l.todayHabitUpdateFailed);
        });
      }
    } finally {
      _pastSending = false;
    }
  }

  /// A centred line in place of the sheet's content: loading, or why there
  /// is nothing to log.
  Widget _placeholder(BuildContext context, Widget child) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: child),
        ),
      );

  /// The log of [day], a day other than today: read from the Habits list
  /// when its chain (the last two weeks at most) reaches back to the day,
  /// otherwise from the habit's year of history (`GET /habits/:id?days=366`,
  /// the detail sheet's read) — loading meanwhile. A day older than that
  /// year cannot be read, so it is shown but not logged.
  Widget _pastDay(BuildContext context, DateTime day) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final async = ref.watch(habitsProvider);
    final listed = async.value?.data.habits
        .where((h) => h.id == widget.habitId)
        .firstOrNull;
    if (listed == null) {
      return _placeholder(
        context,
        async.isLoading && !async.hasValue
            ? const CircularProgressIndicator.adaptive()
            : Text(l.errNotFound, style: text.bodyMedium),
      );
    }
    if (dateOnly(listed.today.date) == day) {
      // The list's today (the server's): logged as today, on every screen.
      return _view(
        context,
        name: listed.name,
        color: listed.color,
        target: listed.targetCount,
        count: listed.today.count,
        done: listed.today.completed,
        counts: listed.countsWithinDay,
        subtitle: l.habitLogToday,
        onSet: (count) => ref
            .read(habitActionsProvider)
            .setToday(listed.id, count, day: listed.today.date)
            .then((_) {}, onError: (Object e) {
          if (mounted) {
            setState(() => _error =
                failureMessage(e, l, fallback: l.todayHabitUpdateFailed));
          }
        }),
      );
    }
    // The chain has every day from its first on (a day it leaves out has
    // nothing logged).
    final listCovers = listed.chain.isNotEmpty &&
        !day.isBefore(dateOnly(listed.chain.first.date));
    var habit = listed;
    var known = listCovers;
    if (listed.canLog(day) && !listCovers) {
      final detail = ref.watch(habitDetailProvider(widget.habitId));
      final loaded = detail.value?.data;
      if (loaded == null) {
        return _placeholder(
          context,
          detail.hasFailed && !detail.isLoading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      detail.isGone
                          ? l.errNotFound
                          : failureMessage(detail.error!, l,
                              fallback: l.errServerUnreachable),
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (!detail.isGone) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref
                            .read(dataSyncProvider)
                            .refresh([habitDetailProvider(widget.habitId)]),
                        child: Text(l.actionRetry),
                      ),
                    ],
                  ],
                )
              : const CircularProgressIndicator.adaptive(),
        );
      }
      habit = loaded;
      final t = dateOnly(loaded.today.date);
      known = !day.isBefore(
          DateTime(t.year, t.month, t.day - (habitHistoryDays - 1)));
    }
    final count = _pastCount ?? habit.countOn(day);
    return _view(
      context,
      name: habit.name,
      color: habit.color,
      target: habit.targetCount,
      count: count,
      done: habit.logFor(count).completed && count > 0,
      counts: habit.countsWithinDay,
      subtitle: formatDate(day, withYear: day.year != habit.today.date.year),
      // Only a day whose count is known: a write from a guess would
      // overwrite what the day has.
      onSet: habit.canLog(day) && known
          ? (count) => _setPast(habit, day, count)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final home = ref.watch(homeProvider).value?.data;
    final asked = widget.date;
    if (asked != null) {
      final day = dateOnly(asked);
      final DateTime today = home?.today ?? ref.watch(currentDayProvider);
      if (day != dateOnly(today)) return _pastDay(context, day);
    }
    final habit = home?.todayHabits
        .where((h) => h.id == widget.habitId)
        .firstOrNull;
    if (home == null || habit == null) {
      // Archived or deleted meanwhile: nothing left to log.
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l.errNotFound, style: text.bodyMedium),
        ),
      );
    }
    // A count to step only for a daily habit; done or not for any other,
    // and — as on Today — while how often it repeats is not known yet.
    final daily = ref.watch(habitCadenceProvider)[habit.id] ?? false;
    return _view(
      context,
      name: habit.name,
      color: habit.color,
      target: habit.targetCount,
      count: habit.todayCount,
      done: habit.completedToday,
      counts: daily && habit.targetCount > 1,
      subtitle: l.habitLogToday,
      onSet: (count) => _set(home, habit, count),
    );
  }

  /// The sheet for one day of a habit: its name and day, the count (a
  /// stepper, or done / not done), then "Sıfırla" and "Tamamla". [onSet]
  /// null: the day cannot be logged (before the habit started).
  Widget _view(
    BuildContext context, {
    required String name,
    required String color,
    required int target,
    required int count,
    required bool done,
    required bool counts,
    required String subtitle,
    required ValueChanged<int>? onSet,
  }) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = hexColor(color, fallback: c.gold);
    void set(int value) => onSet?.call(value);
    final enabled = onSet != null;

    // Under the drag handle every sheet gets from the theme. Scrolls when it
    // does not fit — 200% text on a small phone — rather than overflow.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: text.titleLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
            const SizedBox(height: 24),
            if (counts)
              _Stepper(
                count: count,
                target: target,
                color: tone,
                enabled: enabled,
                semantics: l.habitLogSemantics(
                  name,
                  count: count,
                  target: target,
                  done: done,
                ),
                onSet: set,
              )
            else
              Row(
                children: [
                  Semantics(
                    label: l.habitLogSemantics(
                      name,
                      count: count,
                      target: 1,
                      done: done,
                    ),
                    button: true,
                    enabled: enabled,
                    checked: done,
                    child: HabitCheck(
                      completed: done,
                      color: tone,
                      onTap: () => set(done ? 0 : target),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      done ? l.habitLogDone : l.habitLogNotDone,
                      style: text.bodyLarge,
                    ),
                  ),
                ],
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: text.bodySmall!.copyWith(color: c.error)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: enabled && (count > 0 || done)
                        ? () => set(0)
                        : null,
                    child: Text(l.habitLogReset),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: done || !enabled ? null : () => set(target),
                    child: Text(l.habitLogComplete),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `−  n / target  +` with 48 dp buttons.
class _Stepper extends StatelessWidget {
  final int count;
  final int target;
  final Color color;
  final String semantics;
  final ValueChanged<int> onSet;
  final bool enabled;

  const _Stepper({
    required this.count,
    required this.target,
    required this.color,
    required this.semantics,
    required this.onSet,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    Widget step(IconData icon, bool enabled, int next, String tooltip) =>
        IconButton.filledTonal(
          tooltip: tooltip,
          iconSize: 24,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: enabled && this.enabled ? () => onSet(next) : null,
          icon: Icon(icon),
        );
    final l = context.l10n;
    return Row(
      children: [
        step(Icons.remove, count > 0, count - 1, l.habitLogDecrease),
        Expanded(
          child: Semantics(
            label: semantics,
            liveRegion: true,
            excludeSemantics: true,
            child: Text(
              '$count / $target',
              textAlign: TextAlign.center,
              style: text.displayMedium!.copyWith(
                color: count >= target ? color : c.inkHi,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
        ),
        step(Icons.add, count < target, count + 1, l.habitLogIncrease),
      ],
    );
  }
}
