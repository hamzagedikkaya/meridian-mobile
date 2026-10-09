import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/haptics.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import 'entrance.dart';

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
            duration: Motion.sweep,
            curve: Motion.enter,
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
              duration: Motion.sweep,
              curve: Motion.enter,
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

/// Six months of income and expense (design-analysis §4.24): no left axis,
/// 10 dp bars 4 dp apart with 3 dp top corners, expense filled
/// (`chartExpense`), income hollow with a 1.5 dp `chartIncome` outline —
/// the two series differ in shape, not only colour. Earlier months at 60 %,
/// the current one ([currentIndex], default the last) at full strength with
/// its label in inkHi w600. One dashed inkLow line marks the six-month
/// expense average, labelled on the right ("ort. ₺33B").
///
/// Touching a bar shows its amount (s3 tooltip, `overlayBorder`, radius 8)
/// and ticks ([Haptics.tick]) each time the touched month changes. On the
/// first visible frame of a tab's data (the [EntranceGate]) the bars grow
/// from zero; a refresh retargets them. Reduced motion draws them as they
/// are; touching still works.
///
/// Show it only when two or more months have data ([hasEnoughData]).
class SixMonthBars extends StatefulWidget {
  final List<String> labels;
  final List<int> incomeCents;
  final List<int> expenseCents;
  final String currency;
  final int subunitToUnit;
  final double height;

  /// The month in progress; null is the last one.
  final int? currentIndex;

  /// What a screen reader hears: the chart's one-sentence insight and its
  /// main values.
  final String? semanticsLabel;

  const SixMonthBars({
    super.key,
    required this.labels,
    required this.incomeCents,
    required this.expenseCents,
    required this.currency,
    required this.subunitToUnit,
    this.height = 160,
    this.currentIndex,
    this.semanticsLabel,
  });

  /// Whether at least two months have anything to draw.
  static bool hasEnoughData(List<int> income, List<int> expense) {
    var months = 0;
    for (var i = 0; i < math.max(income.length, expense.length); i++) {
      final a = i < income.length ? income[i] : 0;
      final b = i < expense.length ? expense[i] : 0;
      if (a != 0 || b != 0) months++;
    }
    return months >= 2;
  }

  @override
  State<SixMonthBars> createState() => _SixMonthBarsState();
}

class _SixMonthBarsState extends State<SixMonthBars> {
  /// How long the bars grow or retarget: a local alias of [Motion.sheetIn]
  /// (same 350 ms) until WP-1/WP-17 add a token named for it
  /// (`Motion.barGrow`).
  static const _barGrow = Motion.sheetIn;

  /// The first frame draws the bars at zero when the entrance plays; the
  /// next frame gives fl_chart the real values, which it animates to.
  bool _grown = true;
  bool _decided = false;
  int? _touched;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (entranceShouldPlay(context)) {
      _grown = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _grown = true);
      });
    }
  }

  void _onTouch(FlTouchEvent event, BarTouchResponse? response) {
    final index = event.isInterestedForInteractions
        ? response?.spot?.touchedBarGroupIndex
        : null;
    if (index != null && index != _touched) Haptics.tick();
    _touched = index;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final n = widget.labels.length;
    final current = widget.currentIndex ?? n - 1;

    int at(List<int> values, int i) => i < values.length ? values[i] : 0;
    var maxV = 0;
    for (var i = 0; i < n; i++) {
      maxV = math.max(maxV, math.max(at(widget.incomeCents, i), at(widget.expenseCents, i)));
    }
    final maxY = maxV == 0 ? 1.0 : maxV * 1.2;
    final expenses = [for (var i = 0; i < n; i++) at(widget.expenseCents, i)];
    final average =
        n == 0 ? 0 : expenses.fold<int>(0, (a, b) => a + b) / n;
    final averageLabel = l.chartAverage(formatMoneyCompact(
        average.round(), widget.currency, widget.subunitToUnit));
    final reduced = Motion.reduced(context);
    // The month labels' band grows with the text (§8.3); the bars keep
    // their room.
    final scaler = MediaQuery.textScalerOf(context);
    final monthStyle = text.labelSmall!.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: tabularFigures,
    );
    final monthLabels = math.max(
      _monthLabels,
      _monthLabelGap + chartLabelLineHeight(monthStyle, scaler) + 2,
    );
    final height = widget.height + monthLabels - _monthLabels;
    var widestMonth = 0.0;
    for (final label in widget.labels) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: monthStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widestMonth = math.max(widestMonth, tp.width);
      tp.dispose();
    }

    /// Large text: every other (or third…) month is labelled, counting back
    /// from the current one, so the labels never run into each other.
    int labelStep(double axis) {
      if (n < 2) return 1;
      final slot = axis / n;
      var step = 1;
      while (step < n && widestMonth + 6 > slot * step) {
        step++;
      }
      return step;
    }

    final chart = BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        minY: 0,
        barTouchData: BarTouchData(
          touchCallback: _onTouch,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => c.surface3,
            tooltipBorder: BorderSide(color: c.overlayBorder),
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final i = group.x;
              final cents = rodIndex == 0
                  ? at(widget.incomeCents, i)
                  : at(widget.expenseCents, i);
              return BarTooltipItem(
                formatMoney(cents, widget.currency, widget.subunitToUnit,
                    decimals: MoneyDecimals.auto),
                text.labelSmall!.copyWith(
                  color: c.inkHi,
                  fontFeatures: tabularFigures,
                ),
              );
            },
          ),
        ),
        // The average line is the one reference: no other grid line.
        gridData: const FlGridData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (average > 0)
              HorizontalLine(
                y: _grown ? average.toDouble() : 0,
                color: c.inkLow,
                strokeWidth: 1,
                dashArray: const [4, 4],
              ),
          ],
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          // Room on the right for the average's label, clear of the bars.
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: average > 0,
              reservedSize: _averageGutter,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: monthLabels,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= n) return const SizedBox.shrink();
                if ((current - i) % labelStep(meta.parentAxisSize) != 0) {
                  return const SizedBox.shrink();
                }
                final isCurrent = i == current;
                return Padding(
                  padding: const EdgeInsets.only(top: _monthLabelGap),
                  child: Text(
                    widget.labels[i],
                    style: text.labelSmall!.copyWith(
                      color: isCurrent ? c.inkHi : c.inkLow,
                      fontWeight: isCurrent ? FontWeight.w600 : null,
                      fontFeatures: tabularFigures,
                    ),
                    maxLines: 1,
                    softWrap: false,
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
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY: _grown ? at(widget.incomeCents, i).toDouble() : 0,
                  color: Colors.transparent,
                  width: 10,
                  borderSide: BorderSide(
                    color: c.chartIncome
                        .withValues(alpha: i == current ? 1 : 0.6),
                    width: 1.5,
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                ),
                BarChartRodData(
                  toY: _grown ? at(widget.expenseCents, i).toDouble() : 0,
                  color: c.chartExpense
                      .withValues(alpha: i == current ? 1 : 0.6),
                  width: 10,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ],
            ),
        ],
      ),
      // fl_chart's own implicit animation grows and retargets the bars.
      duration: reduced ? Duration.zero : _barGrow,
      curve: Motion.enter,
    );

    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          child: average <= 0
              ? chart
              : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: chart),
                    // The average's label, beside the end of its line.
                    Positioned(
                      right: 0,
                      width: _averageGutter - 4,
                      top: (height - monthLabels) *
                              (1 - average / maxY) -
                          8,
                      height: 16,
                      child: ExcludeSemantics(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            averageLabel,
                            style: text.labelSmall!.copyWith(
                              color: c.inkMid,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Width kept on the right for the average label; height of the month
  /// labels under the bars at 1× text, and the gap above them.
  static const _averageGutter = 64.0;
  static const _monthLabels = 22.0;
  static const _monthLabelGap = 6.0;
}

/// The height one line of [style] takes at [scaler]'s text size — for the
/// label bands under charts, which grow with the text (§8.3).
double chartLabelLineHeight(TextStyle style, TextScaler scaler) {
  final size = style.fontSize ?? 14;
  return scaler.scale(size) * (style.height ?? 1.2);
}

/// Legend swatch used beside the donut / six-month chart. [hollow] draws a
/// 1.5 dp ring, matching [SixMonthBars]' outlined income bars (§4.24).
class ChartLegendDot extends StatelessWidget {
  final Color color;
  final bool hollow;
  const ChartLegendDot(this.color, {super.key, this.hollow = false});

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: hollow ? null : color,
          border: hollow ? Border.all(color: color, width: 1.5) : null,
          shape: BoxShape.circle,
        ),
      );
}

/// Small helper so tabular label styling stays consistent.
TextStyle tabular(TextStyle style) => style.copyWith(fontFeatures: tabularFigures);
