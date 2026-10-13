import 'package:flutter/material.dart';

import '../../../../core/formats.dart';
import '../../../../core/haptics.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/date_utils.dart';
import '../../../../models/habit.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_typography.dart';
import '../../../../theme/entity_color.dart';
import '../../../widgets/check_pop.dart';
import 'habit_day_cell.dart';

/// The first day of [day]'s month.
DateTime monthOf(DateTime day) => DateTime(day.year, day.month);

/// Whether [habit] as read says what [day] holds: a day of its chain — which
/// has every day from its first through today, or through the archive day
/// (contract §5.1) — or today for an active habit. A day before the chain
/// read (further back than the year the detail reads, or the list's two
/// weeks while the detail loads) or after an archived habit's last day is
/// not known: it is drawn without a log, and never set from a guess — a
/// write would overwrite what the day really has.
bool habitDayKnown(Habit habit, DateTime day) {
  final d = dateOnly(day);
  if (!habit.archived && d == dateOnly(habit.today.date)) return true;
  final chain = habit.chain;
  return chain.isNotEmpty &&
      !d.isBefore(dateOnly(chain.first.date)) &&
      !d.isAfter(dateOnly(chain.last.date));
}

/// [habit]'s chain as drawn: an archived habit owes nothing, so its
/// archive day while still open (`today_pending`) shows no log — not the
/// gold "bekliyor" ring (§4.23, contract §5.1).
List<ChainDay> habitShownChain(Habit habit) => !habit.archived
    ? habit.chain
    : [
        for (final d in habit.chain)
          d.status == ChainStatus.todayPending
              ? ChainDay(date: d.date, status: ChainStatus.noHabits)
              : d,
      ];

/// A habit's log on [day] for a screen reader: today's as
/// [AppL10n.habitLogSemantics] says it ("Koşu, bugün tamamlandı"), any
/// other day with its date ("Koşu, 3 Ekim 2026, yapıldı") — never "today"
/// for a day that is not.
String habitDayLogSemantics(
  AppL10n l, {
  required String name,
  required DateTime day,
  required DateTime today,
  required int count,
  required int target,
  required bool done,
}) {
  if (dateOnly(day) == dateOnly(today)) {
    return l.habitLogSemantics(name, count: count, target: target, done: done);
  }
  final dated = l.habitsDaySemantics(
    formatDate(day, withYear: true),
    count: count,
    target: target,
    done: done,
    loggable: true,
  );
  return '$name, $dated';
}

/// A habit's month as a calendar (design-analysis §4.23): Monday-first
/// weeks, one cell per day — at least 44 dp wide and 48 dp tall, 2 dp
/// apart — drawn by [HabitDayPainter] in its calendar look (the day's
/// number on the tint, never on the solid colour). A tap on a day that can
/// be logged selects it for [HabitDayEditor]; only that cell animates when
/// its log changes.
///
/// Days before the habit started, after today, and every day of an archived
/// habit are shown but cannot be selected; a tooltip and a screen reader
/// say so.
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

  /// Space between cells: (320 − 6 × 2) / 7 = 44 dp per cell in a sheet.
  static const gap = 2.0;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(habit.color, c);
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

    Widget week(List<DateTime?> days) => Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          Expanded(
            child: switch (days[i]) {
              null => const SizedBox(height: Hit.min),
              final day => _DayCell(
                key: ValueKey('habit-day-${isoDate(day)}'),
                day: day,
                entry: byDay[day],
                habit: habit,
                tone: tone,
                isToday: day == today,
                selected: selected != null && dateOnly(selected!) == day,
                onTap: () => onSelect(day),
              ),
            },
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l.habitsPrevMonth,
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
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
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: gap),
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
            ],
          ),
        ),
        const SizedBox(height: Gap.xs),
        RepaintBoundary(
          child: Column(
            children: [
              for (var row = 0; row < cells.length; row += 7) ...[
                if (row > 0) const SizedBox(height: gap),
                week(cells.sublist(row, row + 7)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final ChainDay? entry;
  final Habit habit;
  final EntityTone tone;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  const _DayCell({
    super.key,
    required this.day,
    required this.entry,
    required this.habit,
    required this.tone,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final known = habitDayKnown(habit, day);
    final loggable = habit.canLog(day) && known;
    final count = habit.countOn(day);
    final today = dateOnly(habit.today.date);
    final inRange =
        !day.isAfter(today) &&
        (habit.startDate == null || !day.isBefore(dateOnly(habit.startDate!)));
    // A day the habit as read does not cover has no log to show — never
    // "missed" (§4.23), as the heatmap draws it.
    final state = !inRange || !known
        ? HabitDayState.none
        // Archived on its last day, still open: it owes nothing.
        : habit.archived && entry?.status == ChainStatus.todayPending
        ? HabitDayState.none
        : habitDayStateOf(
            entry?.status ??
                (day == today ? ChainStatus.todayPending : ChainStatus.missed),
          );
    final done = state == HabitDayState.done;

    final Color ink = switch (state) {
      HabitDayState.done => tone.text,
      // A day out of range is still tappable (the editor says why it
      // cannot be logged): readable text, not inkFaint (§3.1, §8.1).
      HabitDayState.none => c.inkLow,
      _ => c.inkHi,
    };

    final shape = state == HabitDayState.none
        ? const SizedBox.expand()
        : HabitDayCellBox(
            state: state,
            colors: HabitDayColors.of(c, tone.fill, tint: tone.tint),
            animate: selected,
          );

    final cell = SizedBox(
      height: Hit.min,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(left: 1, right: 1, top: 3, bottom: 3, child: shape),
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: Radii.mdAll,
                  border: Border.all(color: c.inkHi, width: 2),
                ),
              ),
            ),
          Text(
            '${day.day}',
            style: text.labelLarge!.copyWith(
              color: ink,
              fontFeatures: tabularFigures,
              fontWeight: isToday ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: loggable,
      selected: selected,
      label: inRange && !known
          ? '${formatDate(day, withYear: true)}, ${l.habitsDayStateNone}'
          : l.habitsDaySemantics(
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
      child: Tooltip(
        message: loggable ? '' : l.habitsDayCannotLog,
        excludeFromSemantics: true,
        child: InkWell(onTap: onTap, borderRadius: Radii.mdAll, child: cell),
      ),
    );
  }
}

/// A calendar day's shape, filling its box, in the calendar look (the tint
/// under the number); it grows in when [animate] (the selected day) and
/// its state changes.
class HabitDayCellBox extends StatefulWidget {
  final HabitDayState state;
  final HabitDayColors colors;
  final bool animate;

  const HabitDayCellBox({
    super.key,
    required this.state,
    required this.colors,
    this.animate = false,
  });

  @override
  State<HabitDayCellBox> createState() => _HabitDayCellBoxState();
}

class _HabitDayCellBoxState extends State<HabitDayCellBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: Motion.standard,
    value: 1,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _grow,
    curve: Motion.enter,
  );

  @override
  void didUpdateWidget(HabitDayCellBox old) {
    super.didUpdateWidget(old);
    if (widget.animate &&
        old.state != widget.state &&
        !Motion.reduced(context)) {
      _grow.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: HabitDayPainter(
      state: widget.state,
      colors: widget.colors,
      radius: Radii.md - 2,
      solid: false,
      grow: _curve,
    ),
  );
}

/// One day's log, to set it: a counter for a daily habit done several
/// times a day, done-or-not for any other; or, for a day that cannot be
/// logged, why not. It changes the detail sheet's content — no sheet opens
/// over the sheet.
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
    final tone = entityTone(habit.color, c);
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
    } else if (!habitDayKnown(habit, d)) {
      // Not read: what it holds is not known, so it is not set from here.
      reason = l.habitsDayUnknown;
    }
    String semantics(int target) => habitDayLogSemantics(
      l,
      name: habit.name,
      day: d,
      today: today,
      count: count,
      target: target,
      done: done,
    );

    Widget step(IconData icon, String tooltip, bool enabled, int next) =>
        IconButton.filledTonal(
          tooltip: tooltip,
          constraints: const BoxConstraints.tightFor(
            width: Hit.min,
            height: Hit.min,
          ),
          onPressed: enabled
              ? () {
                  Haptics.tick();
                  onSet(next);
                }
              : null,
          icon: Icon(icon),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: Radii.lgAll,
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall),
          const SizedBox(height: Gap.sm),
          if (reason != null)
            Text(reason, style: text.bodySmall!.copyWith(color: c.inkMid))
          else if (habit.countsWithinDay)
            Row(
              children: [
                step(
                  Icons.remove_rounded,
                  l.habitLogDecrease,
                  count > 0,
                  count - 1,
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    label: semantics(target),
                    excludeSemantics: true,
                    child: Text(
                      '$count / $target',
                      textAlign: TextAlign.center,
                      style: context.nokText.numStat.copyWith(
                        color: count >= target ? tone.text : c.inkHi,
                      ),
                    ),
                  ),
                ),
                step(
                  Icons.add_rounded,
                  l.habitLogIncrease,
                  count < target,
                  count + 1,
                ),
              ],
            )
          else
            Row(
              children: [
                CheckPop(
                  checked: done,
                  tone: tone,
                  semanticLabel: semantics(1),
                  onToggle: () => onSet(done ? 0 : target),
                ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Text(
                    done ? l.habitsDayDone : l.habitsDayNotDone,
                    style: text.bodyLarge,
                  ),
                ),
              ],
            ),
          if (reason == null && habit.countsWithinDay) ...[
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: count > 0 ? () => onSet(0) : null,
                    style: TextButton.styleFrom(foregroundColor: c.inkMid),
                    child: Text(l.habitLogReset),
                  ),
                ),
                const SizedBox(width: Gap.md),
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
            const SizedBox(height: Gap.sm),
            Text(error!, style: text.bodySmall!.copyWith(color: c.error)),
          ],
        ],
      ),
    );
  }
}
