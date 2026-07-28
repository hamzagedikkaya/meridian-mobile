import 'package:flutter/material.dart';

import '../../../../core/haptics.dart';
import '../../../../theme/app_colors.dart';

/// `energy_level` shown as 5 tiny dots — filled gold up to [level].
/// Pass [onChanged] to make it an interactive 5-dot picker (editor).
class EnergyDots extends StatelessWidget {
  final int level;
  final double size;
  final double gap;
  final ValueChanged<int>? onChanged;

  const EnergyDots({
    super.key,
    required this.level,
    this.size = 6,
    this.gap = 4,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) SizedBox(width: gap),
          _dot(context, i),
        ],
      ],
    );
  }

  Widget _dot(BuildContext context, int i) {
    final c = context.nok;
    final filled = i < level;
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? c.gold : c.inkFaint,
      ),
    );
    if (onChanged == null) return dot;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tick();
        onChanged!(level == i + 1 ? 0 : i + 1);
      },
      child: Padding(padding: const EdgeInsets.all(4), child: dot),
    );
  }
}
