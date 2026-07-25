import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// A single donut slice.
class DonutSection {
  final double value;
  final Color color;
  const DonutSection({required this.value, required this.color});
}

/// Noktürn-themed donut (design §4.4 Kategoriler). 160dp, centerSpaceRadius 56,
/// sectionsSpace 2. Sweeps its sections in from 0 over ~600ms on first build
/// only (subtle, no re-sweep on refresh — §5). [center] renders inside the
/// hole; provide [centerTotalCents] (+ [centerCurrency]/[centerSubunitToUnit]/
/// [centerLabel]) instead to get a first-load count-up total. [onSliceTap]
/// fires with the tapped section index.
class DonutChart extends StatefulWidget {
  final List<DonutSection> sections;
  final Widget? center;
  final double size;
  final ValueChanged<int>? onSliceTap;
  final int? centerTotalCents;
  final String? centerCurrency;
  final int? centerSubunitToUnit;
  final String? centerLabel;

  const DonutChart({
    super.key,
    required this.sections,
    this.center,
    this.size = 160,
    this.onSliceTap,
    this.centerTotalCents,
    this.centerCurrency,
    this.centerSubunitToUnit,
    this.centerLabel,
  });

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  bool _swept = false;
  bool _counted = false;

  List<PieChartSectionData> _slices(double radius, double t) {
    final real = [
      for (final s in widget.sections)
        PieChartSectionData(
          value: s.value * t,
          color: s.color,
          radius: radius,
          showTitle: false,
        ),
    ];
    if (t >= 1) return real;
    final total = widget.sections.fold<double>(0, (a, s) => a + s.value);
    return [
      ...real,
      PieChartSectionData(
        value: total * (1 - t),
        color: Colors.transparent,
        radius: radius,
        showTitle: false,
      ),
    ];
  }

  Widget? _buildCenter(BuildContext context) {
    if (widget.centerTotalCents == null) return widget.center;
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final target = widget.centerTotalCents!.abs().toDouble();

    Widget amount(int cents) => Text(
          formatMoney(cents, widget.centerCurrency ?? '',
              widget.centerSubunitToUnit ?? 1),
          style: text.titleLarge!.copyWith(fontFeatures: tabularFigures),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_counted)
          amount(widget.centerTotalCents!)
        else
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            onEnd: () {
              if (mounted && !_counted) setState(() => _counted = true);
            },
            builder: (context, v, _) => amount(v.round()),
          ),
        if (widget.centerLabel != null)
          Text(widget.centerLabel!,
              style: text.labelSmall!.copyWith(color: c.inkMid)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final radius = widget.size / 2 - 56;
    final total = widget.sections.fold<double>(0, (a, s) => a + s.value);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (total <= 0)
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface2, width: radius),
                ),
              ),
            )
          else
            TweenAnimationBuilder<double>(
              tween: _swept ? Tween(begin: 1, end: 1) : Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              onEnd: () {
                if (mounted && !_swept) setState(() => _swept = true);
              },
              builder: (context, t, _) => PieChart(
                PieChartData(
                  centerSpaceRadius: 56,
                  sectionsSpace: 2,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    enabled: widget.onSliceTap != null && t >= 1,
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final idx =
                          response?.touchedSection?.touchedSectionIndex ?? -1;
                      if (idx >= 0 && idx < widget.sections.length) {
                        widget.onSliceTap?.call(idx);
                      }
                    },
                  ),
                  sections: _slices(radius, t),
                ),
                duration: Duration.zero,
              ),
            ),
          ?_buildCenter(context),
        ],
      ),
    );
  }
}

/// Grouped income/expense bars from the six-month series (design §4.4, graft
/// from Kehribar). Income sage / expense gold, radius-4 tops, 3 y-labels max,
/// 350ms animate-in.
class SixMonthBars extends StatelessWidget {
  final List<String> labels;
  final List<int> incomeCents;
  final List<int> expenseCents;
  final String currency;
  final int subunitToUnit;
  final double height;

  const SixMonthBars({
    super.key,
    required this.labels,
    required this.incomeCents,
    required this.expenseCents,
    required this.currency,
    required this.subunitToUnit,
    this.height = 160,
  });

  String _compact(num cents) {
    final major = cents / subunitToUnit;
    if (major >= 1000000) return '${(major / 1000000).toStringAsFixed(1)}Mn';
    if (major >= 1000) return '${(major / 1000).toStringAsFixed(0)}B';
    return major.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final n = labels.length;

    var maxV = 0;
    for (final v in incomeCents) {
      if (v > maxV) maxV = v;
    }
    for (final v in expenseCents) {
      if (v > maxV) maxV = v;
    }
    final maxY = maxV == 0 ? 1.0 : maxV * 1.2;

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => c.surface3,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                formatMoney(rod.toY.round(), currency, subunitToUnit),
                text.labelSmall!.copyWith(color: c.inkHi),
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 2,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: c.divider, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: maxY / 2,
                getTitlesWidget: (value, meta) {
                  if (value < 0 || value > maxY) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      _compact(value),
                      style: text.labelSmall!.copyWith(color: c.inkLow),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= n) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: text.labelSmall!.copyWith(color: c.inkLow),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 3,
                barRods: [
                  BarChartRodData(
                    toY: (i < incomeCents.length ? incomeCents[i] : 0).toDouble(),
                    color: c.chartIncome,
                    width: 7,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                  BarChartRodData(
                    toY:
                        (i < expenseCents.length ? expenseCents[i] : 0).toDouble(),
                    color: c.chartExpense,
                    width: 7,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

/// Legend swatch used beside the donut / six-month chart.
class ChartLegendDot extends StatelessWidget {
  final Color color;
  const ChartLegendDot(this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Small helper so tabular label styling stays consistent.
TextStyle tabular(TextStyle style) => style.copyWith(fontFeatures: tabularFigures);
