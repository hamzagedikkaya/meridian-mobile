import 'package:flutter/material.dart';
import '../../../../models/habit.dart';
import '../../../../theme/app_colors.dart';
import 'habit_visuals.dart';

/// 14-day chain — 8dp squares, 3dp gap, 2dp radius (design §4.5). Renders the
/// last 14 chain days, right-aligned.
class ChainRow extends StatelessWidget {
  final List<ChainDay> chain;
  final Color color;

  const ChainRow({super.key, required this.chain, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final days =
        chain.length > 14 ? chain.sublist(chain.length - 14) : chain;
    return Wrap(
      alignment: WrapAlignment.start,
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final d in days)
          _square(habitChainCell(d.status, color, c)),
      ],
    );
  }

  Widget _square(({Color fill, Color? border}) v) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: v.fill,
        borderRadius: BorderRadius.circular(2),
        border: v.border == null ? null : Border.all(color: v.border!),
      ),
    );
  }
}
