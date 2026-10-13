import 'package:flutter/material.dart';

import '../../../../l10n/app_l10n.dart';
import '../../../../models/home.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../theme/app_typography.dart';
import '../../../../theme/entity_color.dart';
import '../../../widgets/check_pop.dart';
import '../../../widgets/progress_ring.dart';
import '../../../widgets/streak_flame.dart';

/// A habit on Today (design-analysis §7.2.4): at least 56 dp, padded 20 / 8.
///
/// * Left: the name (titleMedium, up to two lines) over its meta — the
///   streak's flame and days (only above zero) and, for a habit counted
///   several times a day, "5/8".
/// * Right: the 40 dp check in a 48 dp target. A habit done or not is a
///   [CheckPop]; a counted one shows its day as a segmented ring until the
///   tap that completes it plays the full check.
///
/// A tap on the row opens the habit ([onOpen]); a tap on the ring logs it
/// ([onToggle], with the ring's global centre — where the day's confetti
/// starts); a long press opens the day's log ([onLongPress], after one
/// long-press haptic, which the row plays: the callback plays none). A tap shows
/// its result at once (the write is optimistic, see `HabitActions`).
class HomeHabitRow extends StatelessWidget {
  final HomeHabit habit;

  /// Whether the day is a count (`2/3` until done) rather than done or not.
  final bool counts;

  /// The ring was tapped; the ring's centre, in global coordinates.
  final ValueChanged<Offset> onToggle;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;

  const HomeHabitRow({
    super.key,
    required this.habit,
    required this.counts,
    required this.onToggle,
    required this.onOpen,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final tone = entityTone(habit.color, c);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    final meta = <Widget>[
      if (habit.currentStreak > 0) StreakFlame(days: habit.currentStreak),
      if (counts)
        Text(
          '${habit.todayCount}/${habit.targetCount}',
          style: context.nokText.numMeta.copyWith(color: c.inkMid),
        ),
    ];

    return InkWell(
      onTap: onOpen,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.rowH,
            vertical: Gap.sm,
          ),
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
                      maxLines: large ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.xxs),
                        child: Wrap(
                          spacing: Gap.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: meta,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              _HabitRing(
                habit: habit,
                counts: counts,
                tone: tone,
                onToggle: onToggle,
                onLongPress: onLongPress,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HabitRing extends StatelessWidget {
  const _HabitRing({
    required this.habit,
    required this.counts,
    required this.tone,
    required this.onToggle,
    required this.onLongPress,
  });

  final HomeHabit habit;
  final bool counts;
  final EntityTone tone;
  final ValueChanged<Offset> onToggle;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final done = habit.completedToday;
    // A counted habit fills a segment per tap; the completing tap lands the
    // CheckPop's fill and pop.
    final showCount = counts && !done;

    // The row's InkWell plays its own long-press haptic; the ring's
    // detector, which wins over it, plays the same one, once.
    void longPress() {
      Feedback.forLongPress(context);
      onLongPress();
    }

    void tap() {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null || !box.hasSize
          ? Offset.zero
          : box.localToGlobal(box.size.center(Offset.zero));
      onToggle(origin);
    }

    // One stop for a screen reader: the habit and its day, a double-tap
    // logs it like a tap, and a long-press opens the day's log. The ring's
    // own detectors are left out of the tree — each would be a stop of its
    // own (the tap one unlabelled), and this node would then answer a
    // double-tap with nothing.
    return Semantics(
      label: l.habitLogSemantics(
        habit.name,
        count: habit.todayCount,
        target: counts ? habit.targetCount : 1,
        done: done,
      ),
      hint: l.habitLogHint,
      button: true,
      checked: done,
      onTap: tap,
      onLongPress: longPress,
      child: ExcludeSemantics(
        child: GestureDetector(
          onLongPress: longPress,
          child: SizedBox.square(
            dimension: Hit.min,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Under the count's ring the check's own outline would show
                // through the gaps between segments: it stays out of sight
                // (and still takes the tap) until the day is done.
                Opacity(
                  opacity: showCount ? 0 : 1,
                  child: CheckPop(
                    checked: done,
                    tone: tone,
                    size: 40,
                    onTap: tap,
                  ),
                ),
                if (showCount)
                  IgnorePointer(
                    child: ProgressRing(
                      value: habit.targetCount <= 0
                          ? 0
                          : habit.todayCount / habit.targetCount,
                      color: tone.fill,
                      size: 40,
                      strokeWidth: 3,
                      segments: habit.targetCount,
                      semanticsValue: '',
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
