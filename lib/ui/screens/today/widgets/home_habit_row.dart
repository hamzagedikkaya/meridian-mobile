import 'package:flutter/material.dart';

import '../../../../l10n/app_l10n.dart';
import '../../../../models/home.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_typography.dart';
import '../../../widgets/check_pop.dart';
import 'today_common.dart';

/// Compact 56dp home habit row: name + streak meta + tappable completion ring.
/// A tap shows its result at once (the write is optimistic, see
/// `HabitActions`), so the ring never waits on the network; a long-press
/// opens the day's log, to step a count back or undo the day.
class HomeHabitRow extends StatelessWidget {
  final HomeHabit habit;

  /// Whether the day is a count (`2/3` until done) rather than done or not.
  final bool counts;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const HomeHabitRow({
    super.key,
    required this.habit,
    required this.counts,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final color = hexColor(habit.color, fallback: c.gold);

    final metaParts = <String>[];
    if (habit.currentStreak > 0) metaParts.add('🔥 ${habit.currentStreak}');
    if (counts) metaParts.add('${habit.todayCount}/${habit.targetCount}');
    final meta = metaParts.join(' · ');

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
            // One stop for a screen reader: the habit and its day, a
            // double-tap logs it like a tap, and a long-press opens the
            // day's log. The ring's own detectors are left out of the tree —
            // each would be a stop of its own (the tap one unlabelled), and
            // this node would then answer a double-tap with nothing.
            Semantics(
              label: l.habitLogSemantics(
                habit.name,
                count: habit.todayCount,
                target: counts ? habit.targetCount : 1,
                done: habit.completedToday,
              ),
              hint: l.habitLogHint,
              button: true,
              checked: habit.completedToday,
              onTap: onTap,
              onLongPress: onLongPress,
              child: ExcludeSemantics(
                child: GestureDetector(
                  onLongPress: onLongPress,
                  child: _HabitRing(
                    color: color,
                    done: habit.completedToday,
                    counts: counts,
                    targetCount: habit.targetCount,
                    todayCount: habit.todayCount,
                    onTap: onTap,
                  ),
                ),
              ),
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
  final bool counts;
  final int targetCount;
  final int todayCount;
  final VoidCallback onTap;

  const _HabitRing({
    required this.color,
    required this.done,
    required this.counts,
    required this.targetCount,
    required this.todayCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // A counted habit goes up one per tap; it shows its progress until
    // complete, then the CheckPop fill/overshoot lands on the completing tap.
    // Uncheck is plain.
    final showCount = counts && !done;

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CheckPop(checked: done, color: color, size: 40, onTap: onTap),
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
        ],
      ),
    );
  }
}
