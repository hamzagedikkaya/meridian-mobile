import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import 'animated_fraction.dart';
import 'entrance.dart';

/// A progress ring (design-analysis §4.21): a `track` groove, the fill in
/// the record's colour with round caps from −90°, painted by a
/// `CustomPainter` that repaints from the [AnimatedFraction] — no rebuild per
/// frame.
///
/// | Size | Stroke | Centre |
/// |---|---|---|
/// | 16 | 2 | — (SectionHeader counter) |
/// | 40 | 3 | — (Today's counted habit) |
/// | 72 | 6 | labelLarge w600, tabular (GoalCard) |
/// | 160 | 10 | RollingNumber displayMedium (goal detail) |
///
/// It sweeps 0 → value only on the first visible frame of a tab's data
/// (the [EntranceGate]) — [sweepOnMount] overrides that (a Hero shuttle
/// passes false). A new value springs from wherever the ring is
/// ([Motion.defaultEffects]; [Motion.slowEffects] from 160 dp up). Under
/// reduced motion the value is drawn as it is.
///
/// With [segments] (a habit counted several times a day) the ring splits
/// into min(segments, 12) arcs 3° apart and each step fills the next one in
/// [Motion.quick].
class ProgressRing extends StatefulWidget {
  final double value;
  final Color color;
  final double size;
  final double strokeWidth;
  final Widget? center;

  /// Whether to sweep from zero when mounted; null asks the [EntranceGate].
  final bool? sweepOnMount;

  /// Splits the ring into this many segments (capped at 12).
  final int? segments;

  /// The spring a new value rides; null picks by [size].
  final SpringDescription? spring;

  /// What a screen reader hears as the value; null is the percentage
  /// ("%62" / "62%"). While the ring speaks, [center] is left out of the
  /// tree, so the percentage it shows is not read twice. An empty string
  /// leaves the ring out of the tree (and [center] in it).
  final String? semanticsValue;

  const ProgressRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 72,
    this.strokeWidth = 6,
    this.center,
    this.sweepOnMount,
    this.segments,
    this.spring,
    this.semanticsValue,
  });

  @override
  State<ProgressRing> createState() => ProgressRingState();
}

class ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  AnimatedFraction? _fraction;

  /// The value painted this frame (for tests).
  @visibleForTesting
  double get paintedValue => _fraction?.value ?? widget.value;

  SpringDescription get _spring => widget.spring ??
      (widget.size >= 160 ? Motion.slowEffects : Motion.defaultEffects);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fraction ??= AnimatedFraction(
      vsync: this,
      target: widget.value,
      spring: _spring,
      sweep: !Motion.reduced(context) &&
          (widget.sweepOnMount ?? entranceShouldPlay(context)),
    );
  }

  @override
  void didUpdateWidget(ProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    final fraction = _fraction!..spring = _spring;
    if (widget.value != old.value) {
      fraction.retarget(
        widget.value,
        reduced: Motion.reduced(context),
        duration: widget.segments != null ? Motion.quick : null,
      );
    }
  }

  @override
  void dispose() {
    _fraction?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final fraction = _fraction!;
    final semantics = widget.semanticsValue ??
        formatPercent((widget.value.clamp(0.0, 1.0) * 100).round());
    final center = widget.center;
    final ring = RepaintBoundary(
      child: CustomPaint(
        painter: _RingPainter(
          fraction: fraction,
          color: widget.color,
          track: c.track,
          strokeWidth: widget.strokeWidth,
          segments: widget.segments,
        ),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: center == null
              ? null
              // Inside the stroke, shrunk rather than drawn over it at
              // large text.
              : Padding(
                  padding: EdgeInsets.all(widget.strokeWidth + 2),
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: center),
                  ),
                ),
        ),
      ),
    );
    if (semantics.isEmpty) return ring;
    // The ring says the value; a centre that shows it is not read again.
    return Semantics(
      value: semantics,
      child: center == null ? ring : ExcludeSemantics(child: ring),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.strokeWidth,
    required this.segments,
  }) : super(repaint: fraction.controller);

  final AnimatedFraction fraction;
  final Color color;
  final Color track;
  final double strokeWidth;
  final int? segments;

  static const _gap = 3 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final value = fraction.value;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final n = segments == null ? 0 : math.min(segments!, 12);
    if (n <= 1) {
      canvas.drawCircle(center, radius, paint..color = track);
      if (value > 0) {
        canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false,
            paint..color = color);
      }
      return;
    }
    // Segments: round caps eat into the gap, so the arcs are shortened by
    // the cap's angle as well.
    final cap = strokeWidth / radius;
    final span = 2 * math.pi / n;
    final arc = math.max(0.0, span - _gap - cap);
    final filled = value * n;
    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * span + (_gap + cap) / 2;
      canvas.drawArc(rect, start, arc, false, paint..color = track);
      final part = (filled - i).clamp(0.0, 1.0);
      if (part > 0) {
        canvas.drawArc(rect, start, arc * part, false, paint..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.strokeWidth != strokeWidth ||
      old.segments != segments;
}
