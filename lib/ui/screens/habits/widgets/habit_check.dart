import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';

/// 48dp check ring (target_count == 1). Tap fills the habit color with the §5
/// check-off pop: press scale 0.9 → color fill sweep + check draw + a single
/// 0.9→1.05→1.0 easeOutBack overshoot. Uncheck is a plain 200ms fade.
class HabitCheck extends StatefulWidget {
  final bool completed;
  final Color color;
  final VoidCallback onTap;

  const HabitCheck({
    super.key,
    required this.completed,
    required this.color,
    required this.onTap,
  });

  @override
  State<HabitCheck> createState() => _HabitCheckState();
}

class _HabitCheckState extends State<HabitCheck>
    with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    reverseDuration: const Duration(milliseconds: 200),
    value: widget.completed ? 1 : 0,
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
  void didUpdateWidget(HabitCheck old) {
    super.didUpdateWidget(old);
    if (widget.completed && !old.completed) {
      _fill.forward(from: 0);
      _pop.forward(from: 0);
    } else if (!widget.completed && old.completed) {
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
      child: AnimatedBuilder(
        animation: Listenable.merge([_fill, _pop]),
        builder: (_, _) {
          final scale = _pressed ? 0.9 : _popScale.value;
          return Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 48,
              height: 48,
              child: CustomPaint(
                painter: _RingPainter(
                  fill: _fill.value,
                  color: widget.color,
                  ring: c.inkLow,
                  check: Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fill;
  final Color color;
  final Color ring;
  final Color check;

  _RingPainter({
    required this.fill,
    required this.color,
    required this.ring,
    required this.check,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;

    if (fill < 1) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring.withValues(alpha: (1 - fill).clamp(0.0, 1.0));
      canvas.drawCircle(center, r - 1, ringPaint);
    }

    if (fill > 0) {
      final disc = Paint()..color = color;
      canvas.drawCircle(center, r * fill, disc);
    }

    final p = ((fill - 0.35) / 0.65).clamp(0.0, 1.0);
    if (p > 0) {
      final w = size.width;
      final h = size.height;
      final path = Path()
        ..moveTo(w * .30, h * .52)
        ..lineTo(w * .44, h * .66)
        ..lineTo(w * .70, h * .36);
      final metric = path.computeMetrics().first;
      final ext = metric.extractPath(0, metric.length * p);
      final checkPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = check;
      canvas.drawPath(ext, checkPaint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fill != fill || old.color != color;
}
