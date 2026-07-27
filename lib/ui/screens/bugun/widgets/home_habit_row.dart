import 'package:flutter/material.dart';

import '../../../../models/home.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_typography.dart';
import '../../../widgets/check_pop.dart';
import 'bugun_common.dart';

/// Compact 56dp home habit row: name + streak meta + tappable completion ring.
class HomeHabitRow extends StatelessWidget {
  final HomeHabit habit;
  final bool busy;
  final VoidCallback onToggle;

  const HomeHabitRow({
    super.key,
    required this.habit,
    required this.busy,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final color = hexColor(habit.color, fallback: c.gold);

    final metaParts = <String>[];
    if (habit.currentStreak > 0) metaParts.add('🔥 ${habit.currentStreak}');
    if (habit.targetCount > 1) {
      metaParts.add('${habit.todayCount}/${habit.targetCount}');
    }
    final meta = metaParts.join(' · ');

    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.name,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      style: text.bodySmall!.copyWith(color: c.inkMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _HabitRing(
              color: color,
              done: habit.completedToday,
              busy: busy,
              targetCount: habit.targetCount,
              todayCount: habit.todayCount,
              onTap: busy ? null : onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitRing extends StatelessWidget {
  final Color color;
  final bool done;
  final bool busy;
  final int targetCount;
  final int todayCount;
  final VoidCallback? onTap;

  const _HabitRing({
    required this.color,
    required this.done,
    required this.busy,
    required this.targetCount,
    required this.todayCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Multi-count habits increment per tap; show progress until complete, then
    // the CheckPop fill/overshoot lands on the completing tap. Uncheck is plain.
    final showCount = targetCount > 1 && !done && !busy;

    return SizedBox(
      width: 48,
      height: 48,
      child: IgnorePointer(
        ignoring: busy,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CheckPop(
              checked: done,
              color: color,
              size: 40,
              onTap: onTap ?? () {},
            ),
            if (showCount)
              IgnorePointer(
                child: Text(
                  '$todayCount/$targetCount',
                  style: text.labelSmall!.copyWith(
                    color: color,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
            if (busy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
          ],
        ),
      ),
    );
  }
}
