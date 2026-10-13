import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Press feedback for tappable cards, chips and small controls
/// (design-analysis §4.2): the child scales down the moment a finger lands
/// and back when it lifts.
///
/// * **Instant.** The press starts on `PointerDown` — it does not wait the
///   100 ms tap timeout — and is driven by a [ScaleTransition], so the
///   child is never rebuilt per frame.
/// * **Timing.** Down in [Motion.pressIn] (80 ms, `easeOut`), back in
///   [Motion.pressOut] (150 ms, `easeOutCubic`). A finger that slides past
///   [kTouchSlop] cancels the press.
/// * **Always visible.** A tap shorter than the press-in still finishes it
///   before releasing, so even a 40 ms tap shows ≈ 230 ms of feedback.
/// * **Scale by size.** [Motion.pressScale] (0.98) for cards at least
///   120 dp wide; [PressableScale.small] uses [Motion.pressScaleSmall]
///   (0.95) for chips and pills, where 0.98 would not be seen.
/// * **Reduced motion** ([Motion.reduced]): no scale at all; taps still work.
/// * **Long press** plays the platform's long-press feedback
///   (`Feedback.forLongPress`) before [onLongPress].
///
/// * **Controls inside** ([PressableClaim]): a touch that lands on a
///   control the card holds (a habit's check, its counter) is the
///   control's alone — the card neither presses nor opens.
///
/// Rows do not scale — they show the theme's gold ripple instead (§4.4).
/// With neither [onTap] nor [onLongPress] it ignores the finger, but keeps
/// the same tree: a child that turns tappable or not (a chip just chosen)
/// carries on its own animations rather than starting over.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The scale while pressed.
  final double pressedScale;

  /// Leaves the tap out of the semantics tree — for a child that already
  /// is the screen-reader button (it would otherwise be announced twice).
  final bool excludeFromSemantics;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = Motion.pressScale,
    this.excludeFromSemantics = false,
  });

  /// For chips, pills and other small controls: scales to 0.95.
  const PressableScale.small({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.excludeFromSemantics = false,
  }) : pressedScale = Motion.pressScaleSmall;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late Animation<double> _scale;

  /// Where the finger landed, while it is down; null otherwise.
  Offset? _downAt;

  /// Pointers that landed on a [PressableClaim] inside.
  final _claimed = <int>{};

  Animation<double> _scaleFor(double pressed) =>
      _press.drive(Tween(begin: 1.0, end: pressed));

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this)..addStatusListener(_onStatus);
    _scale = _scaleFor(widget.pressedScale);
  }

  @override
  void didUpdateWidget(PressableScale old) {
    super.didUpdateWidget(old);
    if (old.pressedScale != widget.pressedScale) {
      _scale = _scaleFor(widget.pressedScale);
    }
    // Turned off mid-press (a chip chosen by this very tap): the finger no
    // longer counts, and the press eases back rather than snapping.
    if (!_enabled && _downAt != null) _up();
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    // The press-in finished after the finger had already lifted: now
    // release, so the shortest tap still shows a full press.
    if (status == AnimationStatus.completed && _downAt == null) _release();
  }

  void _down(PointerDownEvent event) {
    // A control's claim ran first (it is deeper in the tree).
    if (!_enabled || _claimed.contains(event.pointer)) return;
    _downAt = event.position;
    if (Motion.reduced(context)) return;
    _press.animateTo(1, duration: Motion.pressIn, curve: Motion.press);
  }

  void _move(PointerMoveEvent event) {
    final at = _downAt;
    if (at == null) return;
    if ((event.position - at).distance > kTouchSlop) _up();
  }

  void _up([PointerEvent? event]) {
    if (event != null) _claimed.remove(event.pointer);
    if (_downAt == null) return;
    _downAt = null;
    // Still pressing in: the status listener releases once it is done.
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

  @override
  Widget build(BuildContext context) {
    // The same tree whether enabled or not, so the child's state survives
    // the change.
    final enabled = _enabled;
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: GestureDetector(
        behavior: enabled ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
        excludeFromSemantics: widget.excludeFromSemantics,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null ? null : _longPress,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}

/// A control inside a [PressableScale] whose touches are its own: the
/// pressable around it neither presses nor taps for a finger that lands
/// here — also where the control is off (a counter at its target). The
/// control keeps its own gestures and semantics.
class PressableClaim extends StatelessWidget {
  final Widget child;

  const PressableClaim({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (e) => context
            .findAncestorStateOfType<_PressableScaleState>()
            ?._claimed
            .add(e.pointer),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          // Wins the tap over the pressable's, so the card does not open.
          onTap: () {},
          child: child,
        ),
      );
}
