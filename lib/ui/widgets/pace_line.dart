import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/haptics.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import 'charts.dart' show chartLabelLineHeight;
import 'entrance.dart';

/// This month's spending pace against last month's (design-analysis §4.24),
/// 96 dp tall, for the Finance hero.
///
/// * This month: `chartExpense`, 2 dp, gently smoothed without overshoot,
///   over a 16 % → 0 gradient; today's point a 3 dp dot ringed 2 dp in s1.
/// * Last month ([reference]): inkLow 1.5 dp, dashed 4/4. None the first
///   month.
/// * Day labels under it: 1, 15 and the last day.
/// * **Scrub:** the whole plot is a touch target. A 1 dp inkMid cursor
///   locks to each day, a tooltip reads "12 Eki · ₺8.420 / geçen ay
///   ₺9.100", every new day ticks ([Haptics.tick]); letting go fades it in
///   150 ms.
/// * **Entrance** (the [EntranceGate]): the line draws itself in
///   [Motion.sweep], then the dot grows in [Motion.quick]. Reduced motion
///   draws it whole; scrubbing still works.
///
/// The cumulative series come from WP-15's `spend_cumulative_cents[]` and
/// `reference_cumulative_cents[]`; without them, do not build this chart.
class PaceLine extends StatefulWidget {
  const PaceLine({
    super.key,
    required this.spent,
    this.reference,
    required this.daysInMonth,
    required this.month,
    required this.currency,
    required this.subunitToUnit,
    this.semanticsLabel,
    this.height = 96,
  });

  /// Cumulative spending, day 1 to today (index 0 = day 1).
  final List<int> spent;

  /// Last month's cumulative spending, day by day; null the first month.
  final List<int>? reference;

  final int daysInMonth;

  /// Any day of the month shown (for the tooltip's dates).
  final DateTime month;
  final String currency;
  final int subunitToUnit;

  /// The chart's one-sentence insight and its main values.
  final String? semanticsLabel;
  final double height;

  @override
  State<PaceLine> createState() => _PaceLineState();
}

class _PaceLineState extends State<PaceLine> with TickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: Motion.sweep + Motion.quick,
    value: 1,
  );
  late final AnimationController _cursor = AnimationController(
    vsync: this,
    duration: _hintFade,
  );

  /// The scrub cursor's fade.
  static const _hintFade = Motion.hintIn;
  bool _decided = false;
  int? _day;

  /// The day labels' band at 1× text; it grows with the text (§8.3) and
  /// the plot keeps its room.
  static const _labelHeight = 18.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (entranceShouldPlay(context)) _draw.forward(from: 0);
  }

  @override
  void dispose() {
    _draw.dispose();
    _cursor.dispose();
    super.dispose();
  }

  void _scrub(Offset local, double width) {
    final days = widget.daysInMonth;
    if (days < 2 || widget.spent.isEmpty) return;
    final day =
        ((local.dx / width) * (days - 1)).round().clamp(0, days - 1) + 1;
    final shown = math.min(
      day,
      math.max(widget.spent.length, widget.reference?.length ?? 0),
    );
    if (shown < 1) return;
    if (shown != _day) {
      Haptics.tick();
      setState(() => _day = shown);
    }
    _cursor.value = 1;
  }

  void _release() {
    if (Motion.reduced(context)) {
      _cursor.value = 0;
    } else {
      _cursor.reverse();
    }
  }

  String _tooltip(AppL10n l, int day) {
    final date = DateTime(widget.month.year, widget.month.month, day);
    String money(int cents) => formatMoney(
      cents,
      widget.currency,
      widget.subunitToUnit,
      decimals: MoneyDecimals.auto,
    );
    final spent = day <= widget.spent.length
        ? money(widget.spent[day - 1])
        : '—';
    final ref = widget.reference;
    final previous = ref == null || day > ref.length
        ? null
        : money(ref[day - 1]);
    return l.chartPaceTooltip(
      '${date.day} ${formatMonthShort(date)}',
      spent,
      previous,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final labelStyle = text.labelSmall!.copyWith(
      color: c.inkLow,
      fontFeatures: tabularFigures,
    );
    final days = widget.daysInMonth;
    final labelHeight = math.max(
      _labelHeight,
      chartLabelLineHeight(labelStyle, MediaQuery.textScalerOf(context)) + 4,
    );
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      child: RepaintBoundary(
        child: SizedBox(
          height: widget.height + labelHeight - _labelHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final day = _day;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    bottom: labelHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (d) =>
                          _scrub(d.localPosition, width),
                      onHorizontalDragUpdate: (d) =>
                          _scrub(d.localPosition, width),
                      onHorizontalDragEnd: (_) => _release(),
                      onHorizontalDragCancel: _release,
                      onLongPressStart: (d) => _scrub(d.localPosition, width),
                      onLongPressMoveUpdate: (d) =>
                          _scrub(d.localPosition, width),
                      onLongPressEnd: (_) => _release(),
                      onTapDown: (d) => _scrub(d.localPosition, width),
                      onTapUp: (_) => _release(),
                      child: CustomPaint(
                        painter: _PacePainter(
                          draw: _draw,
                          cursor: _cursor,
                          cursorDay: day,
                          spent: widget.spent,
                          reference: widget.reference,
                          days: days,
                          line: c.chartExpense,
                          referenceColor: c.inkLow,
                          ring: c.surface1,
                          cursorColor: c.inkMid,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: labelHeight,
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('1', style: labelStyle),
                          Text('15', style: labelStyle),
                          Text('$days', style: labelStyle),
                        ],
                      ),
                    ),
                  ),
                  if (day != null)
                    Positioned(
                      top: -30,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: FadeTransition(
                          opacity: _cursor,
                          child: Align(
                            alignment: Alignment(
                              days < 2 ? 0 : ((day - 1) / (days - 1)) * 2 - 1,
                              0,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.surface3,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: c.overlayBorder),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Text(
                                  _tooltip(l, day),
                                  style: text.labelSmall!.copyWith(
                                    color: c.inkHi,
                                    fontFeatures: tabularFigures,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PacePainter extends CustomPainter {
  _PacePainter({
    required this.draw,
    required this.cursor,
    required this.cursorDay,
    required this.spent,
    required this.reference,
    required this.days,
    required this.line,
    required this.referenceColor,
    required this.ring,
    required this.cursorColor,
  }) : super(repaint: Listenable.merge([draw, cursor]));

  final Animation<double> draw;
  final Animation<double> cursor;
  final int? cursorDay;
  final List<int> spent;
  final List<int>? reference;
  final int days;
  final Color line;
  final Color referenceColor;
  final Color ring;
  final Color cursorColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (days < 2 || spent.isEmpty) return;
    final ref = reference;
    var top = 0;
    for (final v in spent) {
      top = math.max(top, v);
    }
    for (final v in ref ?? const <int>[]) {
      top = math.max(top, v);
    }
    if (top <= 0) top = 1;
    // Room for the dot and its ring at the edges.
    const pad = 5.0;
    final plot = Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad);
    Offset at(int index, int cents) => Offset(
      plot.left + plot.width * index / (days - 1),
      plot.bottom - plot.height * (cents / top),
    );

    // Line first, over 600 of the 800 ms; then the dot.
    final total = (Motion.sweep + Motion.quick).inMicroseconds;
    final t = draw.value;
    final lineT = Motion.enter.transform(
      (t * total / Motion.sweep.inMicroseconds).clamp(0.0, 1.0),
    );
    final dotT =
        ((t * total - Motion.sweep.inMicroseconds) /
                Motion.quick.inMicroseconds)
            .clamp(0.0, 1.0);

    if (ref != null && ref.length > 1) {
      final path = _smooth([
        for (var i = 0; i < ref.length; i++) at(i, ref[i]),
      ]);
      _dashed(
        canvas,
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = referenceColor,
      );
    }

    final points = [for (var i = 0; i < spent.length; i++) at(i, spent[i])];
    final full = points.length > 1 ? _smooth(points) : null;
    if (full != null && lineT > 0) {
      final metric = full.computeMetrics().first;
      final drawn = metric.extractPath(0, metric.length * lineT);
      final end =
          metric.getTangentForOffset(metric.length * lineT)?.position ??
          points.last;
      final area = Path.from(drawn)
        ..lineTo(end.dx, plot.bottom)
        ..lineTo(points.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, plot.top),
            Offset(0, plot.bottom),
            [line.withValues(alpha: 0.16), line.withValues(alpha: 0)],
          ),
      );
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = line,
      );
    }
    if (dotT > 0 || points.length == 1) {
      final r = 3.0 * (points.length == 1 ? 1.0 : dotT);
      canvas.drawCircle(points.last, r + 2, Paint()..color = ring);
      canvas.drawCircle(points.last, r, Paint()..color = line);
    }

    final day = cursorDay;
    if (day != null && cursor.value > 0) {
      final x = plot.left + plot.width * (day - 1) / (days - 1);
      canvas.drawLine(
        Offset(x, plot.top - pad),
        Offset(x, plot.bottom + pad),
        Paint()
          ..strokeWidth = 1
          ..color = cursorColor.withValues(alpha: cursorColor.a * cursor.value),
      );
    }
  }

  /// A curve through [p] that never overshoots a point (monotone cubic,
  /// mild tension).
  static Path _smooth(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    const tension = 0.2;
    for (var i = 0; i < p.length - 1; i++) {
      final a = p[i];
      final b = p[i + 1];
      final before = i == 0 ? a : p[i - 1];
      final after = i + 2 < p.length ? p[i + 2] : b;
      var c1 = a + (b - before) * tension;
      var c2 = b - (after - a) * tension;
      // Keep the controls between the two points' heights: no overshoot.
      double clampY(double y) =>
          y.clamp(math.min(a.dy, b.dy), math.max(a.dy, b.dy));
      c1 = Offset(c1.dx, clampY(c1.dy));
      c2 = Offset(c2.dx, clampY(c2.dy));
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy);
    }
    return path;
  }

  static void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 4, metric.length)),
          paint,
        );
        d += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_PacePainter old) =>
      old.draw != draw ||
      old.cursor != cursor ||
      old.cursorDay != cursorDay ||
      old.spent != spent ||
      old.reference != reference ||
      old.days != days ||
      old.line != line ||
      old.referenceColor != referenceColor ||
      old.ring != ring ||
      old.cursorColor != cursorColor;
}
