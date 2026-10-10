import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import '../../../l10n/app_l10n.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/check_pop.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/streak_flame.dart';
import 'widgets/counter_pill.dart';
import 'widgets/habit_day_cell.dart';

/// One card per habit (design-analysis §7.10).
///
/// * **Top row** (at least 48 dp): the habit's 12 dp colour dot, its name
///   (up to two lines) over its streak — a flame and the days, or "Yeni seri
///   · Rekor 21" once broken — and its 30-day rate; on the right the
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

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(habit.color, c);
    final periodic = !habit.isDaily;

    final meta = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Gap.xs,
      runSpacing: Gap.xxs,
      children: [
        StreakFlame(days: habit.currentStreak, record: habit.longestStreak),
        if (habit.currentStreak > 0 || habit.longestStreak > 0)
          // A separator for the eye: a screen reader would say "dot".
          ExcludeSemantics(child: Text('·', style: text.bodySmall)),
        Text(
          l.habitsRate30d(rateOf(habit)),
          style: context.nokText.numMeta.copyWith(color: c.inkMid),
        ),
      ],
    );

    final period = periodic ? _PeriodPill(habit: habit, tone: tone) : null;

    // One node for a screen reader: the name and meta as its label, the
    // card's tap and long press as its actions (as `NokturnCard` merges).
    final info = MergeSemantics(
      child: Semantics(
        button: true,
        onTap: onOpen,
        onLongPress: onLongPress,
        onLongPressHint: onLongPress == null ? null : l.habitLogHint,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            // A weekly or monthly habit's period, under its streak: beside
            // the check it would squeeze the name on a phone.
            if (period != null) ...[const SizedBox(height: Gap.xs), period],
          ],
        ),
      ),
    );

    return _CardPress(
      onTap: onOpen,
      onLongPress: onLongPress,
      builder: (claim) => NokturnCard(
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
                  claim(_control(context, tone)),
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

/// The card's press: the whole card scales to [Motion.pressScale] the
/// moment a finger lands (as `PressableScale` does), except a finger that
/// lands on a control [builder] wraps with its `claim` — the check or the
/// counter works alone, the card stays still. A screen reader reaches the
/// card through its info column, so the gesture here stays out of the
/// semantics tree.
///
/// Local to the Habits screen: `PressableScale` cannot tell a control's
/// touch from the card's (WP-17 note: an `ignore` hook there would replace
/// this).
class _CardPress extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget Function(Widget Function(Widget control) claim) builder;

  const _CardPress({
    required this.onTap,
    required this.onLongPress,
    required this.builder,
  });

  @override
  State<_CardPress> createState() => _CardPressState();
}

class _CardPressState extends State<_CardPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);
  late final Animation<double> _scale = _press.drive(
    Tween(begin: 1.0, end: Motion.pressScale),
  );

  /// Pointers that landed on a control.
  final _claimed = <int>{};
  Offset? _downAt;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _downAt == null) _release();
  }

  void _down(PointerDownEvent event) {
    // The control's own listener ran first (it is deeper in the tree).
    if (_claimed.contains(event.pointer)) return;
    _downAt = event.position;
    if (Motion.reduced(context)) return;
    _press.animateTo(1, duration: Motion.pressIn, curve: Curves.easeOut);
  }

  void _move(PointerMoveEvent event) {
    final at = _downAt;
    if (at != null && (event.position - at).distance > kTouchSlop) _up();
  }

  void _up([PointerEvent? event]) {
    if (event != null) _claimed.remove(event.pointer);
    if (_downAt == null) return;
    _downAt = null;
    if (_press.isAnimating && _press.status == AnimationStatus.forward) return;
    _release();
  }

  void _release() {
    if (_press.value == 0) return;
    _press.animateBack(0, duration: Motion.pressOut, curve: Motion.enter);
  }

  void _longPress() {
    Feedback.forLongPress(context);
    widget.onLongPress!();
  }

  /// A touch on [control] is the control's alone: the card neither presses
  /// nor opens — also where the control is off (a counter at its target).
  Widget _claim(Widget control) => Listener(
    onPointerDown: (e) => _claimed.add(e.pointer),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () {},
      child: control,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null ? null : _longPress,
        child: ScaleTransition(scale: _scale, child: widget.builder(_claim)),
      ),
    );
  }
}
