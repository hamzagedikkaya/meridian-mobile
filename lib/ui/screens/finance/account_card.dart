import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../core/formats.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/pressable_scale.dart';

/// The tag of an account's balance flying from its Finance tile to the
/// header of its page (design-analysis §5.2, D8) — the only part that flies.
String accountBalanceHeroTag(int id) => 'account-balance-$id';

/// [child] (an account's balance) as the end of its hero flight: the
/// shuttle scales the arriving text into the rect between the two ends, so
/// the 20 sp tile balance grows into the 32 sp header one. No flight under
/// reduced motion.
class AccountBalanceHero extends StatelessWidget {
  final int accountId;
  final Widget child;

  const AccountBalanceHero({
    super.key,
    required this.accountId,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return HeroMode(
      enabled: !Motion.reduced(context),
      child: Hero(
        tag: accountBalanceHeroTag(accountId),
        transitionOnUserGestures: true,
        flightShuttleBuilder: (_, _, direction, from, to) {
          final arriving = (direction == HeroFlightDirection.push ? to : from)
              .widget as Hero;
          return Material(
            type: MaterialType.transparency,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              child: arriving.child,
            ),
          );
        },
        child: child,
      ),
    );
  }
}

/// An account in Finance's accounts strip (design-analysis §7.6): 148 dp
/// wide and 92 dp tall — taller when larger text needs it ([heightFor]),
/// never cut. A card-shaped `Material` (s1, hairline, 16 dp corners) with
/// the account's colour as a 3 dp bar inside its left edge, the name
/// (titleSmall, one line), the type (labelSmall inkMid) and the balance in
/// Fraunces (`MoneyText.title`, shrinking rather than "…"), which flies to
/// the account's page.
///
/// A tap opens the account; a long press its actions (edit, archive). A
/// screen reader hears "Cüzdan, Nakit, ₺3.250".
class AccountTile extends StatelessWidget {
  final Account account;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AccountTile({
    super.key,
    required this.account,
    this.onTap,
    this.onLongPress,
  });

  static const width = 148.0;

  /// The least height of a tile, and of the strip.
  static const minHeight = 92.0;

  static const _padding = 12.0;
  static const _bar = 3.0;
  static const _barGap = 10.0;

  /// How tall a tile — and so the strip — is at the text size in use:
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
        lineOf(text.titleSmall) +
        lineOf(text.labelSmall) +
        Gap.xs +
        lineOf(text.headlineSmall);
    return math.max(minHeight, content.ceilToDouble());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final type = l.accountType(account.accountType);
    final balance = formatMoney(
      account.balanceCents,
      account.currency,
      account.subunitToUnit,
      decimals: MoneyDecimals.auto,
    );
    final tone = entityTone(account.color, c);
    return Semantics(
      button: true,
      label: l.accountTileSemantics(account.name, type, balance),
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: PressableScale(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: width,
          height: heightFor(context),
          child: Material(
            color: c.surface1,
            shape: NokturnCard.shapeOf(c),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // The account's colour, inset from the edges so it never
                // rides the hairline.
                PositionedDirectional(
                  start: _padding,
                  top: _padding,
                  bottom: _padding,
                  width: _bar,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tone.fill,
                      borderRadius: BorderRadius.circular(_bar / 2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    _padding + _bar + _barGap,
                    _padding,
                    _padding,
                    _padding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        style: text.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        type,
                        style: text.labelSmall!.copyWith(color: c.inkMid),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      AccountBalanceHero(
                        accountId: account.id,
                        child: MoneyText(
                          account.balanceCents,
                          currency: account.currency,
                          subunitToUnit: account.subunitToUnit,
                          variant: MoneyVariant.title,
                          decimals: MoneyDecimals.auto,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed tile that ends the accounts strip: "+ Hesap", the account
/// form.
class AccountAddTile extends StatelessWidget {
  final VoidCallback? onTap;
  const AccountAddTile({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final label = context.l10n.accountFab;
    return Semantics(
      button: true,
      label: context.l10n.accountNew,
      excludeSemantics: true,
      onTap: onTap,
      child: PressableScale(
        onTap: onTap,
        child: SizedBox(
          width: AccountTile.width,
          height: AccountTile.heightFor(context),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: Radii.lgAll,
              child: CustomPaint(
                painter: _DashedBorderPainter(color: c.inkFaint, radius: 16),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: c.inkMid, size: 20),
                      const SizedBox(width: Gap.xs),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelLarge!.copyWith(color: c.inkMid),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
      (Offset.zero & size).deflate(0.5),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 4.0;
    for (final PathMetric metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(metric.extractPath(dist, dist + dash), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
