import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The single confetti in the app (design §4.5): 12 gold/sage particles,
/// ~800ms, hand-rolled CustomPainter. Fires once when the day is completed.
class ConfettiBurst extends StatefulWidget {
  final VoidCallback? onDone;

  const ConfettiBurst({super.key, this.onDone});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  static const _gold = Color(0xFFD4A853);
  static const _sage = Color(0xFF8FBF9F);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _particles = List.generate(12, (i) {
      final angle = -math.pi * 0.85 + rnd.nextDouble() * (math.pi * 0.7);
      return _Particle(
        angle: angle,
        speed: 120 + rnd.nextDouble() * 150,
        color: i.isEven ? _gold : _sage,
        size: 5 + rnd.nextDouble() * 4,
        spin: (rnd.nextDouble() - 0.5) * 8,
      );
    });
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone?.call();
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _ConfettiPainter(_ctrl.value, _particles),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final Color color;
  final double size;
  final double spin;

  const _Particle({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
    required this.spin,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  final List<_Particle> particles;

  _ConfettiPainter(this.t, this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.28);
    const gravity = 520.0;
    for (final p in particles) {
      final dx = math.cos(p.angle) * p.speed * t;
      final dy = math.sin(p.angle) * p.speed * t + 0.5 * gravity * t * t;
      final pos = origin + Offset(dx, dy);
      final opacity = (1 - ((t - 0.6) / 0.4)).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: p.size, height: p.size * 1.6),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
