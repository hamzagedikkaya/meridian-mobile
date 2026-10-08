import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../../core/formats.dart';
import '../../widgets/pressable_scale.dart';
import 'finance_utils.dart';

/// A finance account card of the snap carousel on Finance (design §4.4):
/// 140 dp, or as tall as larger text needs ([heightFor]) — a minimum
/// height, never a fixed one (design-research §6.2).
class AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback? onTap;

  const AccountCard({super.key, required this.account, this.onTap});

  /// The least height of a card, and of the carousel.
  static const minHeight = 140.0;

  static const _padding = 16.0;
  static const _nameGap = 2.0;

  /// The least room between the type and the balance.
  static const _balanceGap = 8.0;

  /// How tall a card — and so the carousel — is at the text size in use:
  /// [minHeight], or what a name, a type and a balance take on their one
  /// line each at a larger size.
  static double heightFor(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double lineOf(TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: '0', style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final content = _padding * 2 +
        lineOf(text.titleMedium) +
        _nameGap +
        lineOf(text.labelSmall) +
        _balanceGap +
        lineOf(text.displayMedium);
    return math.max(minHeight, content.ceilToDouble());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final color = hexColor(account.color);

    return PressableScale(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: minHeight),
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
                padding: const EdgeInsets.all(_padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: _nameGap),
                    Text(
                      context.l10n.accountType(account.accountType),
                      style: text.labelSmall!.copyWith(color: c.inkMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: _balanceGap),
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
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: AccountCard.minHeight),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: c.inkLow, size: 24),
                const SizedBox(height: 8),
                Text(
                  context.l10n.financeAddAccount,
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
