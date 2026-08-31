import 'package:flutter/material.dart';
import '../../../../models/habit.dart';
import '../../../../theme/app_colors.dart';
import 'habit_visuals.dart';

/// 84-day, 12-week mini-heatmap (design §4.5 detail sheet). Days are chunked
/// sequentially into weeks of 7 → columns.
class MiniHeatmap extends StatelessWidget {
  final List<ChainDay> chain;
  final Color color;

  const MiniHeatmap({super.key, required this.chain, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final days = chain.length > 84 ? chain.sublist(chain.length - 84) : chain;
    final weeks = <List<ChainDay>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, (i + 7).clamp(0, days.length)));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final week in weeks)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Column(
              children: [
                for (final d in week)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _cell(habitChainCell(d.status, color, c)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(({Color fill, Color? border}) v) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: v.fill,
        borderRadius: BorderRadius.circular(2),
        border: v.border == null ? null : Border.all(color: v.border!),
      ),
    );
  }
}
