import 'package:flutter/material.dart';

import '../../../models/account.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../../core/formats.dart';
import '../../widgets/pressable_scale.dart';
import 'para_utils.dart';

/// 140dp finance account card for the Para snap PageView (design §4.4).
class AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback? onTap;

  const AccountCard({super.key, required this.account, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final color = hexColor(account.color);

    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Hero(
              tag: 'account-bar-${account.id}',
              child: Container(width: 4, color: color),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      accountTypeLabel(account.accountType),
                      style: text.labelSmall!.copyWith(color: c.inkMid),
                    ),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatMoney(
                          account.balanceCents,
                          account.currency,
                          account.subunitToUnit,
                        ),
                        style: text.displayMedium!.copyWith(
                          fontFeatures: tabularFigures,
                          color: c.inkHi,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed-hairline ghost card that ends the account carousel.
class AccountAddCard extends StatelessWidget {
  final VoidCallback? onTap;
  const AccountAddCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return PressableScale(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: c.hairline, radius: 16),
        child: SizedBox(
          height: 140,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: c.inkLow, size: 24),
                const SizedBox(height: 8),
                Text(
                  'Hesap ekle',
                  style: text.labelLarge!.copyWith(color: c.inkLow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(
          metric.extractPath(dist, dist + dash),
          paint,
        );
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
