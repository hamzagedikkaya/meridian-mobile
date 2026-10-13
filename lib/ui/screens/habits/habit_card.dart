import 'package:flutter/material.dart';

import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/check_pop.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/streak_flame.dart';
import 'widgets/counter_pill.dart';
import 'widgets/habit_day_cell.dart';

/// One card per habit (design-analysis §7.10).
///
/// * **Top row** (at least 48 dp): the habit's 12 dp colour dot, its name
///   (up to two lines) over its streak — a flame and the days, or "Yeni seri
///   · Rekor 21" once broken — and its 30-day rate once it has a day of
///   history (a habit made today shows no "%0 (30g)"); on the right the
///   control that logs today.
/// * **The control**: a `CheckPop` for a habit done once a day; the
///   [CounterPill] for one done several times a day; for a weekly or
///   monthly habit a `CheckPop` for today — the target is days, not taps —
///   with the period ("Bu hafta 2/3") under the streak.
/// * **Under it**, 12 dp down and level with the name, the last 14 days
///   ([ChainRow]).
///
/// The whole card opens the habit ([onOpen]) and presses to 0.98 under the
/// finger; a long press opens today's log ([onLongPress]). A touch on the
/// control only works the control: the card does not press with it.
class HabitCard extends StatelessWidget {
  final Habit habit;

  /// Today's count the control asks for — the check's target or 0, the
  /// counter one step up or down — with the control's global centre, where
  /// a celebration starts.
  final void Function(int count, Offset origin) onLog;
  final VoidCallback onOpen;
  final VoidCallback? onLongPress;

  const HabitCard({
    super.key,
    required this.habit,
    required this.onLog,
    required this.onOpen,
    this.onLongPress,
  });

  /// The 30-day rate as a whole percentage (the server sends 0–100; older
  /// payloads a 0–1 share).
  static int rateOf(Habit habit) => habit.completionRate30d <= 1
      ? (habit.completionRate30d * 100).round()
      : habit.completionRate30d.round();

  /// Whether [habit] has lived through a day before today — what its 30-day
  /// rate needs to mean anything. A habit made today has none: its rate
  /// would read "%0" (§7.15: no zero that is not one), so it is not shown.
  static bool hasHistory(Habit habit) {
    final today = dateOnly(habit.today.date);
    final start = habit.startDate;
    if (start != null && dateOnly(start).isBefore(today)) return true;
    return habit.chain.any((d) => dateOnly(d.date).isBefore(today));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(habit.color, c);
    final periodic = !habit.isDaily;

    final rate = hasHistory(habit);
    final meta = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Gap.xs,
      runSpacing: Gap.xxs,
      children: [
        StreakFlame(days: habit.currentStreak, record: habit.longestStreak),
        if (rate && (habit.currentStreak > 0 || habit.longestStreak > 0))
          // A separator for the eye: a screen reader would say "dot".
          ExcludeSemantics(child: Text('·', style: text.bodySmall)),
        if (rate)
          Text(
            l.habitsRate30d(rateOf(habit)),
            style: context.nokText.numMeta.copyWith(color: c.inkMid),
          ),
      ],
    );

    final period = periodic ? _PeriodPill(habit: habit, tone: tone) : null;

    // The name and meta, with a weekly or monthly habit's period under
    // the streak (beside the check it would squeeze the name on a phone).
    final info = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Hit.min),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            habit.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium,
          ),
          const SizedBox(height: Gap.xxs),
          meta,
          if (period != null) ...[const SizedBox(height: Gap.xs), period],
        ],
      ),
    );

    // One node for a screen reader, the size of the card (§8.2): the name
    // and meta as its label, the card's tap and long press as its actions.
    // The control is a node of its own inside it. The card presses under
    // the finger (its gesture stays out of the semantics tree, which has
    // the node); a touch on the control is the control's alone.
    return Semantics(
      container: true,
      button: true,
      onTap: onOpen,
      onLongPress: onLongPress,
      onLongPressHint: onLongPress == null ? null : l.habitLogLongPressHint,
      child: PressableScale(
        onTap: onOpen,
        onLongPress: onLongPress,
        excludeFromSemantics: true,
        child: NokturnCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.card,
            vertical: Gap.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Hit.min),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: tone.fill,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(child: info),
                    const SizedBox(width: Gap.sm),
                    PressableClaim(
                      child: Semantics(
                        container: true,
                        child: _control(context, tone),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 24),
                child: ChainRow(
                  chain: habit.chain,
                  fill: tone.fill,
                  startDate: habit.startDate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _control(BuildContext context, EntityTone tone) {
    final l = context.l10n;
    if (habit.countsWithinDay) {
      return CounterPill(
        count: habit.today.count,
        target: habit.targetCount,
        tone: tone,
        semanticLabel: habit.name,
        onDelta: (delta, origin) => onLog(habit.today.count + delta, origin),
      );
    }
    return Builder(
      builder: (control) => CheckPop(
        checked: habit.today.completed,
        tone: tone,
        semanticLabel: l.habitLogSemantics(
          habit.name,
          count: habit.today.count,
          target: 1,
          done: habit.today.completed,
        ),
        onToggle: () => onLog(habit.checkCount, _centreOf(control)),
      ),
    );
  }

  static Offset _centreOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(box.size.center(Offset.zero));
  }
}

/// "Bu hafta 2/3": a weekly or monthly habit's done days in its period; in
/// the habit's tint with a tick once the period's target is met.
class _PeriodPill extends StatelessWidget {
  final Habit habit;
  final EntityTone tone;

  const _PeriodPill({required this.habit, required this.tone});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final period = habit.period;
    final label = habit.frequency == 'monthly'
        ? l.habitsThisMonth
        : l.habitsThisWeek;
    final done = period?.completedCount ?? habit.today.count;
    final complete = period?.complete ?? false;
    return AnimatedContainer(
      duration: Motion.orInstant(context, Motion.quick),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: complete ? tone.tint : c.surface2,
        shape: StadiumBorder(
          side: BorderSide(color: complete ? tone.fill : c.hairline),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (complete) ...[
            Icon(Icons.check_rounded, size: 14, color: tone.text),
            const SizedBox(width: Gap.xxs),
          ],
          Text(
            l.habitsPeriodProgress(label, done, habit.targetCount),
            style: text.labelSmall!.copyWith(
              color: complete ? tone.text : c.inkMid,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
