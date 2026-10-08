import 'package:flutter/material.dart';

import '../../../../core/formats.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/date_utils.dart';
import '../../../../models/habit.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_typography.dart';
import 'habit_check.dart';
import 'habit_visuals.dart';

/// The first day of [day]'s month.
DateTime monthOf(DateTime day) => DateTime(day.year, day.month);

/// A habit's month as a calendar (design-research §5.4): Monday-first
/// weeks, one cell per day — at least 48 dp tall, coloured by its log — and
/// a tap on a day that can be logged selects it for [HabitDayEditor].
///
/// Days before the habit started, after today, and every day of an archived
/// habit are shown but cannot be selected; a screen reader says so.
class HabitMonthCalendar extends StatelessWidget {
  final Habit habit;

  /// The first day of the month shown.
  final DateTime month;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  /// Null when there is no earlier / later month to show.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const HabitMonthCalendar({
    super.key,
    required this.habit,
    required this.month,
    required this.selected,
    required this.onSelect,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final color = hexColor(habit.color);
    final today = dateOnly(habit.today.date);
    final byDay = {for (final d in habit.chain) dateOnly(d.date): d};

    // Monday-first: how many blank cells before the 1st.
    final lead = (month.weekday - DateTime.monday) % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= days; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l.habitsPrevMonth,
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                formatMonthYear(month),
                textAlign: TextAlign.center,
                style: text.titleMedium,
              ),
            ),
            IconButton(
              tooltip: l.habitsNextMonth,
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(
                    // 1 January 2024 was a Monday.
                    formatWeekdayShort(DateTime(2024, 1, 1 + i)),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: text.labelSmall!.copyWith(color: c.inkMid),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < cells.length; row += 7)
          Row(
            children: [
              for (final day in cells.sublist(row, row + 7))
                Expanded(
                  child: day == null
                      ? const SizedBox(height: 48)
                      : _DayCell(
                          key: ValueKey('habit-day-${isoDate(day)}'),
                          day: day,
                          entry: byDay[day],
                          habit: habit,
                          color: color,
                          isToday: day == today,
                          selected:
                              selected != null && dateOnly(selected!) == day,
                          onTap: () => onSelect(day),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final ChainDay? entry;
  final Habit habit;
  final Color color;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  const _DayCell({
    super.key,
    required this.day,
    required this.entry,
    required this.habit,
    required this.color,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final loggable = habit.canLog(day);
    final count = habit.countOn(day);
    final status = entry?.status ?? ChainStatus.missed;
    final done =
        status == ChainStatus.completed || status == ChainStatus.perfect;
    final partial = status == ChainStatus.partial;
    final inRange =
        loggable ||
        (!day.isAfter(dateOnly(habit.today.date)) &&
            habit.startDate != null &&
            !day.isBefore(dateOnly(habit.startDate!)));

    final Color fill;
    final Color ink;
    if (done) {
      fill = color;
      ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
          ? Colors.white
          : const Color(0xFF171310);
    } else if (partial) {
      fill = color.withValues(alpha: 0.35);
      ink = c.inkHi;
    } else if (inRange) {
      fill = c.surface2;
      ink = c.inkHi;
    } else {
      fill = Colors.transparent;
      ink = c.inkFaint;
    }

    final border = selected
        ? Border.all(color: c.inkHi, width: 2)
        : isToday
        ? Border.all(color: c.gold, width: 1.5)
        : partial
        ? Border.all(color: color, width: 1)
        : null;

    return Semantics(
      button: loggable,
      selected: selected,
      label: l.habitsDaySemantics(
        formatDate(day, withYear: true),
        count: count,
        target: habit.countsWithinDay ? habit.targetCount : 1,
        done: done,
        loggable: loggable,
      ),
      // The label replaces the cell's own, which takes the InkWell's tap
      // action with it: give it back here.
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          height: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: border,
              ),
              child: Text(
                '${day.day}',
                style: text.labelLarge!.copyWith(
                  color: ink,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One day's log, to set it: a counter for a daily habit done several
/// times a day, done-or-not for any other; or, for a day that cannot be
/// logged, why not.
class HabitDayEditor extends StatelessWidget {
  final Habit habit;
  final DateTime day;
  final ValueChanged<int> onSet;

  /// Why the last change did not go through.
  final String? error;

  const HabitDayEditor({
    super.key,
    required this.habit,
    required this.day,
    required this.onSet,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final color = hexColor(habit.color);
    final count = habit.countOn(day);
    final target = habit.targetCount;
    final done = habit.logFor(count).completed && count > 0;
    final today = dateOnly(habit.today.date);
    final d = dateOnly(day);
    final title = d == today
        ? l.habitLogToday
        : '${formatWeekday(d)}, ${formatDate(d, withYear: d.year != today.year)}';

    String? reason;
    if (habit.archived) {
      reason = l.errHabitArchived;
    } else if (d.isAfter(today)) {
      reason = l.habitsDayFuture;
    } else if (!habit.canLog(d)) {
      reason = l.habitsDayBeforeStart(
        formatDate(habit.startDate ?? d, withYear: true),
      );
    }

    Widget step(IconData icon, String tooltip, bool enabled, int next) =>
        IconButton.filledTonal(
          tooltip: tooltip,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: enabled ? () => onSet(next) : null,
          icon: Icon(icon),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall),
          const SizedBox(height: 8),
          if (reason != null)
            Text(reason, style: text.bodySmall!.copyWith(color: c.inkMid))
          else if (habit.countsWithinDay)
            Row(
              children: [
                step(Icons.remove, l.habitLogDecrease, count > 0, count - 1),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    label: l.habitLogSemantics(
                      habit.name,
                      count: count,
                      target: target,
                      done: done,
                    ),
                    excludeSemantics: true,
                    child: Text(
                      '$count / $target',
                      textAlign: TextAlign.center,
                      style: text.headlineMedium!.copyWith(
                        color: count >= target ? color : c.inkHi,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                ),
                step(Icons.add, l.habitLogIncrease, count < target, count + 1),
              ],
            )
          else
            Row(
              children: [
                Semantics(
                  label: l.habitLogSemantics(
                    habit.name,
                    count: count,
                    target: 1,
                    done: done,
                  ),
                  button: true,
                  checked: done,
                  child: HabitCheck(
                    completed: done,
                    color: color,
                    onTap: () => onSet(done ? 0 : target),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    done ? l.habitsDayDone : l.habitsDayNotDone,
                    style: text.bodyLarge,
                  ),
                ),
              ],
            ),
          if (reason == null && habit.countsWithinDay) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: count > 0 ? () => onSet(0) : null,
                    child: Text(l.habitLogReset),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: count < target ? () => onSet(target) : null,
                    child: Text(l.habitLogComplete),
                  ),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: text.bodySmall!.copyWith(color: c.error)),
          ],
        ],
      ),
    );
  }
}
