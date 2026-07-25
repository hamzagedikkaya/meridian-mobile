import 'package:flutter/material.dart';
import '../../core/haptics.dart';
import '../../theme/app_colors.dart';

/// Shape of the [CheckPop] target.
enum CheckPopShape { circle, roundedSquare }

/// Reusable section-5 check-off micro-interaction. Tap-down press-scales to
/// 0.9 (~80ms); on becoming checked it plays a 250ms entity-color fill sweep +
/// white check-mark draw + a single 0.9→1.05→1.0 easeOutBack overshoot over
/// 300ms (the only allowed overshoot). Uncheck is a plain 200ms fade — no
/// celebration. Fires [Haptics.success] on check only.
///
/// Use the default circle for habit-ring style targets, or [CheckPop.checkbox]
/// for a rounded-square todo-row checkbox (24-28dp).
class CheckPop extends StatefulWidget {
  final bool checked;
  final Color color;
  final VoidCallback onTap;
  final double size;
  final CheckPopShape shape;

  const CheckPop({
    super.key,
    required this.checked,
    required this.color,
    required this.onTap,
    this.size = 48,
    this.shape = CheckPopShape.circle,
  });

  /// Rounded-square checkbox variant for todo rows (24-28dp).
  const CheckPop.checkbox({
    super.key,
    required this.checked,
    required this.color,
    required this.onTap,
    this.size = 24,
  }) : shape = CheckPopShape.roundedSquare;

  @override
  State<CheckPop> createState() => _CheckPopState();
}

class _CheckPopState extends State<CheckPop> with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    reverseDuration: const Duration(milliseconds: 200),
    value: widget.checked ? 1 : 0,
  );
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late final Animation<double> _popScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.05), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 40),
  ]).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOutBack));

  bool _pressed = false;

  @override
  void didUpdateWidget(CheckPop old) {
    super.didUpdateWidget(old);
    if (widget.checked && !old.checked) {
      _fill.forward(from: 0);
      _pop.forward(from: 0);
      Haptics.success();
    } else if (!widget.checked && old.checked) {
      _fill.reverse();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: AnimatedBuilder(
          animation: Listenable.merge([_fill, _pop]),
          builder: (_, _) => Transform.scale(
            scale: _popScale.value,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _CheckPainter(
                  fill: _fill.value,
                  color: widget.color,
                  track: c.inkLow,
                  check: c.onGold,
                  shape: widget.shape,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double fill;
  final Color color;
  final Color track;
  final Color check;
  final CheckPopShape shape;

  _CheckPainter({
    required this.fill,
    required this.color,
    required this.track,
    required this.check,
    required this.shape,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final w = size.width;
    final h = size.height;

    if (shape == CheckPopShape.circle) {
      final r = w / 2;
      if (fill < 1) {
        final trackPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = track.withValues(alpha: (1 - fill).clamp(0.0, 1.0));
        canvas.drawCircle(center, r - 1, trackPaint);
      }
      if (fill > 0) {
        canvas.drawCircle(center, r * fill, Paint()..color = color);
      }
    } else {
      final radius = Radius.circular(w * 0.28);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, w - 2, h - 2),
        radius,
      );
      if (fill < 1) {
        final trackPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = track.withValues(alpha: (1 - fill).clamp(0.0, 1.0));
        canvas.drawRRect(rect, trackPaint);
      }
      if (fill > 0) {
        final fillPaint = Paint()..color = color.withValues(alpha: fill);
        canvas.drawRRect(rect, fillPaint);
      }
    }

    final p = ((fill - 0.35) / 0.65).clamp(0.0, 1.0);
    if (p > 0) {
      final path = Path()
        ..moveTo(w * .30, h * .52)
        ..lineTo(w * .44, h * .66)
        ..lineTo(w * .70, h * .36);
      final metric = path.computeMetrics().first;
      final ext = metric.extractPath(0, metric.length * p);
      final checkPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape == CheckPopShape.circle ? 3 : 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = check;
      canvas.drawPath(ext, checkPaint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.fill != fill || old.color != color || old.shape != shape;
}
