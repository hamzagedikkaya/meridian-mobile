import 'package:flutter/material.dart';
import '../../../../models/habit.dart';
import '../../../../theme/app_colors.dart';

/// 30 dots in a wrap (10dp circles, 6dp gap): perfect gold / partial gold 40% /
/// missed surface2+hairline / no_habits transparent (design §4.5).
class PerfectDayDots extends StatelessWidget {
  final List<ChainDay> chain;
  final double dot;

  const PerfectDayDots({super.key, required this.chain, this.dot = 10});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final d in chain) _dot(d.status, c)],
    );
  }

  Widget _dot(ChainStatus status, NokturnColors c) {
    Color fill = Colors.transparent;
    Color? border;
    switch (status) {
      case ChainStatus.perfect:
      case ChainStatus.completed:
        fill = c.gold;
      case ChainStatus.partial:
        fill = c.gold.withValues(alpha: 0.4);
      case ChainStatus.todayPending:
        border = c.gold;
      case ChainStatus.missed:
        fill = c.surface2;
        border = c.hairline;
      case ChainStatus.noHabits:
        fill = Colors.transparent;
    }
    return Container(
      width: dot,
      height: dot,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border),
      ),
    );
  }
}
