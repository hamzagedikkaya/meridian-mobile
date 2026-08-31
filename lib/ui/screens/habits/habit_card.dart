import 'package:flutter/material.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/nokturn_card.dart';
import 'widgets/chain_row.dart';
import 'widgets/counter_pill.dart';
import 'widgets/habit_check.dart';
import 'widgets/habit_visuals.dart';

/// One card per habit — 72dp core row + 14-day chain (daily) or a period pill
/// (weekly/monthly). Design §4.5.
class HabitCard extends StatelessWidget {
  final Habit habit;
  final void Function(int delta) onToggle;
  final VoidCallback onOpen;

  const HabitCard({
    super.key,
    required this.habit,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final color = hexColor(habit.color);
    final isDaily = habit.frequency == 'daily';

    final rate = habit.completionRate30d <= 1
        ? (habit.completionRate30d * 100).round()
        : habit.completionRate30d.round();

    return NokturnCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 72,
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpen,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.habitsMeta(habit.currentStreak, rate),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall!.copyWith(color: c.inkMid),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _trailing(color),
              ],
            ),
          ),
          const SizedBox(height: 8),
          isDaily
              ? ChainRow(chain: habit.chain, color: color)
              : _periodPill(context, color),
        ],
      ),
    );
  }

  Widget _trailing(Color color) {
    if (habit.targetCount <= 1) {
      return HabitCheck(
        completed: habit.today.completed,
        color: color,
        onTap: () => onToggle(habit.today.completed ? -1 : 1),
      );
    }
    return CounterPill(
      count: habit.today.count,
      target: habit.targetCount,
      color: color,
      onDelta: onToggle,
    );
  }

  Widget _periodPill(BuildContext context, Color color) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final period = habit.period;
    final label =
        habit.frequency == 'monthly' ? l.habitsThisMonth : l.habitsThisWeek;
    final done = period?.completedCount ?? habit.today.count;
    final complete = period?.complete ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: complete ? color.withValues(alpha: 0.18) : c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.habitsPeriodProgress(label, done, habit.targetCount),
            style: text.labelSmall!.copyWith(color: c.inkMid),
          ),
          if (complete) ...[
            const SizedBox(width: 4),
            Icon(Icons.check, size: 14, color: color),
          ],
        ],
      ),
    );
  }
}
