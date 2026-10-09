import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import 'animated_fraction.dart';
import 'entrance.dart';

/// A fully rounded progress bar (design-analysis §4.21): 6 dp (8 on the
/// Habits hero) on the `track` groove, filled in [color] — or in `error`
/// when [over] (a budget past its limit).
///
/// * [paceTick] draws where the value *should* be by now: a 2 × 12 dp inkMid
///   line standing 3 dp above and below the bar, with 1 dp of surface on
///   each side. It is painted outside the bar's box, so it takes no layout.
/// * [committed] outlines (1 dp, hollow) the share already promised — an
///   upcoming payment — beyond the fill.
///
/// The fill sweeps 0 → value only on the first visible frame of a tab's
/// data (the [EntranceGate]); a new value springs from where the bar is.
/// One `CustomPainter` repaints from the [AnimatedFraction]: no layout, no
/// rebuild per frame. Reduced motion draws the value as it is.
class PacedProgressBar extends StatefulWidget {
  final double value;
  final Color color;
  final double? paceTick;
  final double height;

  /// Share already committed beyond [value] (drawn as an outline), 0–1.
  final double? committed;

  /// Past the limit: the fill turns `error`.
  final bool over;

  /// Whether to sweep from zero when mounted; null asks the [EntranceGate].
  final bool? sweepOnMount;

  /// The spring a new value rides; null is [Motion.defaultEffects].
  final SpringDescription? spring;

  const PacedProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.paceTick,
    this.height = 6,
    this.committed,
    this.over = false,
    this.sweepOnMount,
    this.spring,
  });

  @override
  State<PacedProgressBar> createState() => _PacedProgressBarState();
}

class _PacedProgressBarState extends State<PacedProgressBar>
    with SingleTickerProviderStateMixin {
  AnimatedFraction? _fraction;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fraction ??= AnimatedFraction(
      vsync: this,
      target: widget.value,
      spring: widget.spring,
      sweep: !Motion.reduced(context) &&
          (widget.sweepOnMount ?? entranceShouldPlay(context)),
    );
  }

  @override
  void didUpdateWidget(PacedProgressBar old) {
    super.didUpdateWidget(old);
    final fraction = _fraction!..spring = widget.spring;
    if (widget.value != old.value) {
      fraction.retarget(widget.value, reduced: Motion.reduced(context));
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
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BarPainter(
          fraction: _fraction!,
          color: widget.over ? c.error : widget.color,
          track: c.track,
          tick: c.inkMid,
          surface: c.surface1,
          paceTick: widget.paceTick?.clamp(0.0, 1.0),
          committed: widget.committed?.clamp(0.0, 1.0),
        ),
        child: SizedBox(height: widget.height, width: double.infinity),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.tick,
    required this.surface,
    required this.paceTick,
    required this.committed,
  }) : super(repaint: fraction.controller);

  final AnimatedFraction fraction;
  final Color color;
  final Color track;
  final Color tick;
  final Color surface;
  final double? paceTick;
  final double? committed;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final radius = Radius.circular(h / 2);
    final bar = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(bar, Paint()..color = track);

    final value = fraction.value;
    final committed = this.committed;
    if (committed != null && committed > 0) {
      final end = (value + committed).clamp(0.0, 1.0) * w;
      final outline = RRect.fromRectAndRadius(
        Rect.fromLTRB(0.5, 0.5, end - 0.5, h - 0.5),
        radius,
      );
      if (end > 1) {
        canvas.drawRRect(
          outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color,
        );
      }
    }

    if (value > 0) {
      // A fill narrower than the bar is tall stays a full pill.
      final double fillW = (value * w).clamp(math.min(h, w), w);
      canvas.save();
      canvas.clipRRect(bar);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fillW, h), radius),
        Paint()..color = color,
      );
      canvas.restore();
    }

    final pace = paceTick;
    if (pace != null && w >= 2) {
      final x = (pace * w).clamp(1.0, w - 1.0);
      // 1 dp of surface either side, then the 2 dp line, 3 dp past the bar.
      canvas.drawRect(
        Rect.fromLTRB(x - 2, -3, x + 2, h + 3),
        Paint()..color = surface,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - 1, -3, x + 1, h + 3),
          const Radius.circular(1),
        ),
        Paint()..color = tick,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.tick != tick ||
      old.surface != surface ||
      old.paceTick != paceTick ||
      old.committed != committed;
}
