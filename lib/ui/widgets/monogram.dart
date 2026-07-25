import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class Monogram extends StatelessWidget {
  final double size;

  const Monogram({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.gold,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      alignment: Alignment.center,
      child: Text(
        'M',
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontSize: size * 0.52,
          fontWeight: FontWeight.w600,
          color: c.onGold,
          height: 1,
        ),
      ),
    );
  }
}
