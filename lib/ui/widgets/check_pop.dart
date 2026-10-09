import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/entity_color.dart';

/// Shape of the [CheckPop] target.
enum CheckPopShape { circle, roundedSquare }

/// The one check-off control (design-analysis §4.22) — habit rings, todo
/// boxes, everywhere: 40 dp visual in a 48 dp target ([CheckPop.checkbox]:
/// a 24 dp box, radius 7).
///
/// * **Press:** the pointer going down scales it to 0.90 in
///   [Motion.pressIn] at once; sliding past the touch slop or a cancel
///   brings it back in [Motion.pressOut].
/// * **Check (a tap):** the fill grows in 250 ms, the tick draws as the fill
///   goes from 0.35 to 1, and the pop runs from the current scale to 1.05
///   ([Motion.popUp]) and back to 1.0 ([Motion.popSettle]) — the app's only
///   overshoot — with [Haptics.check].
/// * **Uncheck:** the fill goes back in [Motion.quick]; no pop, no haptic.
/// * **Data changes are not taps.** When [checked] changes because the data
///   did — a refresh, an edit on the web, a hidden tab coming back — the
///   control shows the new state without a pop or a haptic. A change that
///   takes the user's tap back (the write failed) empties or fills it in
///   [Motion.quick], without a pop; the screen plays [Haptics.reject].
///
/// Two ways to wire it:
///
/// * **[onToggle]** (the v2 API): the control animates its own tap at once
///   (next = !checked) and then calls [onToggle].
/// * **[onTap]** (older call sites): the screen decides what a tap does —
///   a counted habit steps its count without checking — and the control
///   plays the check only if [checked] changes right after its tap.
///
/// Reduced motion: no scale, the fill set at once; the haptic stays.
class CheckPop extends StatefulWidget {
  final bool checked;

  /// The record's tone: [EntityTone.fill] fills it, [EntityTone.onFill]
  /// draws the tick.
  final EntityTone? tone;

  /// A plain fill colour (older call sites); the tick picks white or ink,
  /// whichever stands out more.
  final Color? color;

  final VoidCallback? onToggle;
  final VoidCallback? onTap;
  final double size;
  final CheckPopShape shape;

  /// What a screen reader calls it ("Sabah koşusu"); with it the control is
  /// a checkable button of its own. Without it the row around it speaks.
  final String? semanticLabel;

  /// Fill the parent with the tap target (a todo row's 76 × 56 dp leading
  /// area), drawing the control at [visualAlignment] in it.
  final bool expandHitArea;
  final AlignmentGeometry visualAlignment;

  const CheckPop({
    super.key,
    required this.checked,
    this.tone,
    this.color,
    this.onToggle,
    this.onTap,
    this.size = 40,
    this.shape = CheckPopShape.circle,
    this.semanticLabel,
    this.expandHitArea = false,
    this.visualAlignment = Alignment.center,
  })  : assert(tone != null || color != null, 'a tone or a colour'),
        assert(onToggle != null || onTap != null, 'onToggle or onTap');

  /// The rounded-square checkbox of a todo row: 24 dp, radius 7.
  const CheckPop.checkbox({
    super.key,
    required this.checked,
    this.tone,
    this.color,
    this.onToggle,
    this.onTap,
    this.size = 24,
    this.semanticLabel,
    this.expandHitArea = false,
    this.visualAlignment = Alignment.center,
  })  : shape = CheckPopShape.roundedSquare,
        assert(tone != null || color != null, 'a tone or a colour'),
        assert(onToggle != null || onTap != null, 'onToggle or onTap');

  /// The press scale the pointer going down sets.
  static const pressedScale = 0.90;

  /// The pop's peak.
  static const popScale = 1.05;

  /// How long the check's fill takes. A local alias of [Motion.collapse]
  /// (the same 250 ms, not the same meaning) until WP-1/WP-17 add a token named for it
  /// (`Motion.fillIn`); see the WP-17 note in §9.
  static const fillIn = Motion.collapse;

  @override
  State<CheckPop> createState() => _CheckPopState();
}

class _CheckPopState extends State<CheckPop> with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    value: widget.checked ? 1 : 0,
  );
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.normal,
  );

  /// The state this control's own tap asked for (the [CheckPop.onToggle]
  /// API), until [CheckPop.checked] catches up or takes it back.
  bool? _pendingLocal;

  /// An [CheckPop.onTap] tap whose result has not shown yet: a change of
  /// [CheckPop.checked] in the frame after it is that tap's (the screen's
  /// optimistic update is synchronous). A change that comes later — a
  /// refresh, a web edit — is the data's.
  bool _tapPending = false;
  int _tapRun = 0;

  Offset? _downAt;
  int _popRun = 0;

  bool get _reduced => Motion.reduced(context);

  @override
  void didUpdateWidget(CheckPop old) {
    super.didUpdateWidget(old);
    if (widget.checked == old.checked) return;
    final checked = widget.checked;
    if (_pendingLocal != null) {
      final mine = _pendingLocal == checked;
      _pendingLocal = null;
      // Already animated by the tap — or the tap taken back: no pop.
      if (!mine) _settleFill(checked);
      return;
    }
    if (_tapPending) {
      _endTapWindow();
      _playTap(checked);
      return;
    }
    // A refresh, a web edit, a tab coming back: the state, nothing more.
    _fill.value = checked ? 1 : 0;
  }

  @override
  void dispose() {
    _fill.dispose();
    _scale.dispose();
    super.dispose();
  }

  void _settleFill(bool checked) {
    if (_reduced) {
      _fill.value = checked ? 1 : 0;
    } else {
      _fill.animateTo(checked ? 1 : 0,
          duration: Motion.quick, curve: Motion.exit);
    }
  }

  /// The tap's own animation: fill + tick + pop + haptic, or the plain
  /// uncheck.
  void _playTap(bool checked) {
    final reduced = _reduced;
    if (checked) {
      Haptics.check();
      if (reduced) {
        _fill.value = 1;
        _scale.value = 1;
        return;
      }
      _fill.animateTo(1, duration: CheckPop.fillIn, curve: Motion.enter);
      final run = ++_popRun;
      _scale
          .animateTo(CheckPop.popScale, duration: Motion.popUp, curve: Motion.enter)
          .then((_) {
        if (run != _popRun || !mounted) return;
        _scale.animateTo(1,
            duration: Motion.popSettle, curve: Curves.easeInOutCubic);
      });
    } else {
      if (reduced) {
        _fill.value = 0;
        _scale.value = 1;
        return;
      }
      _fill.animateTo(0, duration: Motion.quick, curve: Motion.exit);
      _release();
    }
  }

  void _press() {
    if (_reduced) return;
    _popRun++;
    _scale.animateTo(CheckPop.pressedScale,
        duration: Motion.pressIn, curve: Curves.easeOut);
  }

  void _release() {
    _downAt = null;
    if (_reduced) {
      _scale.value = 1;
      return;
    }
    _popRun++;
    _scale.animateTo(1, duration: Motion.pressOut, curve: Motion.enter);
  }

  void _endTapWindow() {
    _tapPending = false;
    _tapRun++;
  }

  void _handleTap() {
    _downAt = null;
    final toggle = widget.onToggle;
    if (toggle != null) {
      final next = !widget.checked;
      _pendingLocal = next;
      _playTap(next);
      toggle();
      return;
    }
    // The screen decides; the change it makes now — shown in the next
    // frame — is this tap's. The window closes once that frame is drawn.
    _tapPending = true;
    final run = ++_tapRun;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (run == _tapRun) _endTapWindow();
    });
    binding.ensureVisualUpdate();
    widget.onTap!();
    // Let go now; a check that follows pops from wherever the scale is.
    _release();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final tone = widget.tone;
    final fillColor = tone?.fill ?? widget.color!;
    final tickColor = tone?.onFill ?? _onFill(fillColor);
    final box = widget.shape == CheckPopShape.circle
        ? math.max(widget.size, 48.0)
        : widget.size;

    Widget control = Listener(
      onPointerDown: (e) {
        _downAt = e.position;
        _press();
      },
      onPointerMove: (e) {
        final down = _downAt;
        if (down != null && (e.position - down).distance > kTouchSlop) {
          _release();
        }
      },
      onPointerCancel: (_) => _release(),
      onPointerUp: (_) {
        // The tap (if it is one) arrives right after; a long press or a
        // drag that ended here lets go.
        if (_downAt != null) {
          scheduleMicrotask(() {
            if (mounted && _downAt != null) _release();
          });
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        excludeFromSemantics: widget.semanticLabel != null,
        child: SizedBox(
          width: widget.expandHitArea ? double.infinity : box,
          height: widget.expandHitArea ? double.infinity : box,
          child: Align(
            alignment: widget.expandHitArea
                ? widget.visualAlignment
                : Alignment.center,
            child: ScaleTransition(
              scale: _scale,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.square(widget.size),
                  painter: _CheckPainter(
                    fill: _fill,
                    color: fillColor,
                    ring: c.inkLow,
                    check: tickColor,
                    shape: widget.shape,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final label = widget.semanticLabel;
    if (label != null) {
      control = Semantics(
        button: true,
        checked: widget.checked,
        label: label,
        onTap: _handleTap,
        child: control,
      );
    }
    return control;
  }

  /// White or `#171310`, whichever contrasts more with [fill] (D19).
  static Color _onFill(Color fill) {
    const white = Color(0xFFFFFFFF);
    const ink = Color(0xFF171310);
    return contrastRatio(white, fill) >= contrastRatio(ink, fill) ? white : ink;
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.fill,
    required this.color,
    required this.ring,
    required this.check,
    required this.shape,
  }) : super(repaint: fill);

  final Animation<double> fill;
  final Color color;
  final Color ring;
  final Color check;
  final CheckPopShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final t = fill.value.clamp(0.0, 1.0);
    final center = size.center(Offset.zero);
    final w = size.width;
    final h = size.height;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ring.withValues(alpha: ring.a * (1 - t));

    if (shape == CheckPopShape.circle) {
      final r = w / 2;
      if (t < 1) canvas.drawCircle(center, r - 1, ringPaint);
      if (t > 0) canvas.drawCircle(center, r * t, Paint()..color = color);
    } else {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, w - 2, h - 2),
        const Radius.circular(7),
      );
      if (t < 1) canvas.drawRRect(rect, ringPaint);
      if (t > 0) {
        canvas.drawRRect(
            rect, Paint()..color = color.withValues(alpha: color.a * t));
      }
    }

    final p = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
    if (p > 0) {
      final path = Path()
        ..moveTo(w * .30, h * .52)
        ..lineTo(w * .44, h * .66)
        ..lineTo(w * .70, h * .36);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = shape == CheckPopShape.circle ? 3 : 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = check,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.fill != fill ||
      old.color != color ||
      old.ring != ring ||
      old.check != check ||
      old.shape != shape;
}
