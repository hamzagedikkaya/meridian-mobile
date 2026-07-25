import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Ring with animated sweep — 600ms easeOutCubic from 0 on first build,
/// then previous→new over 350ms, never re-zeroing (design §5).
class ProgressRing extends StatefulWidget {
  final double value;
  final Color color;
  final double size;
  final double strokeWidth;
  final Widget? center;

  const ProgressRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 72,
    this.strokeWidth = 6,
    this.center,
  });

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing> {
  bool _first = true;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final target = widget.value.clamp(0.0, 1.0);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: TweenAnimationBuilder<double>(
        tween: _first ? Tween(begin: 0, end: target) : Tween(end: target),
        duration: Duration(milliseconds: _first ? 600 : 350),
        curve: Curves.easeOutCubic,
        onEnd: () {
          if (mounted && _first) setState(() => _first = false);
        },
        builder: (context, v, child) => CustomPaint(
          painter: _RingPainter(
            value: v,
            color: widget.color,
            track: c.surface2,
            strokeWidth: widget.strokeWidth,
          ),
          child: Center(child: widget.center),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  final double strokeWidth;

  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paint..color = track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}
