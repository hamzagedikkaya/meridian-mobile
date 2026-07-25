import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Minimal line sparkline — no dots/axes, gold→transparent gradient fill
/// (design §4.3 hero card).
class Sparkline extends StatelessWidget {
  final List<double> values;
  final double height;
  final Color? color;

  const Sparkline({
    super.key,
    required this.values,
    this.height = 48,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final line = color ?? c.gold;
    if (values.length < 2) return SizedBox(height: height);

    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minV - range * 0.1,
          maxY: maxV + range * 0.1,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: true,
              curveSmoothness: 0.3,
              color: line,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [line.withValues(alpha: 0.12), Colors.transparent],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
