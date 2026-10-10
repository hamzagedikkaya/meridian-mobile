import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import 'money_text.dart';
import 'pressable_scale.dart';

/// This month's net at a glance — the chip in Today's header that stands in
/// for a money card (design-analysis §4.20, D4).
///
/// A 36 dp pill (48 dp target) on surface1 with a hairline: "Bu ay"
/// (bodySmall inkMid), the net as a row amount — income with "+" above
/// zero, inkHi with "−" below, plain inkMid at exactly zero — and a 16 dp
/// chevron. Tapping it calls [onTap] (it opens Finance).
///
/// With no account yet ([netCents] null) it reads "Nakit hesabıyla başla ›"
/// and calls [onStart] — the same one-tap cash account as Finance's setup
/// card. Hide the chip while that card is on screen (D42: never two
/// controls for one action).
class MoneyGlance extends StatelessWidget {
  /// This month's net, in minor units; null when there is no account.
  final int? netCents;
  final String currency;
  final int subunitToUnit;
  final VoidCallback onTap;

  /// Opens a cash account; used when [netCents] is null.
  final VoidCallback? onStart;

  /// Whether the net keeps ",00" ([MoneyDecimals.auto] drops it from a
  /// whole amount, as a chip should — §3.7).
  // TODO(WP-2): §3.7 makes auto the chip's default; WP-5 passes it from
  // Today until then.
  final MoneyDecimals decimals;

  const MoneyGlance({
    super.key,
    required this.netCents,
    required this.currency,
    required this.subunitToUnit,
    required this.onTap,
    this.onStart,
    this.decimals = MoneyDecimals.always,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final net = netCents;

    final List<Widget> parts;
    final String semantics;
    final VoidCallback? tap;
    if (net == null) {
      parts = [
        Flexible(
          child: Text(
            l.moneyGlanceStart,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall!.copyWith(color: c.gold),
          ),
        ),
      ];
      semantics = l.moneyGlanceStart;
      tap = onStart;
    } else {
      final amount = formatMoney(
        net,
        currency,
        subunitToUnit,
        signed: net > 0,
        decimals: decimals,
      );
      parts = [
        // An amount is never cut (§3.7): given less room than it needs, the
        // words shrink to fit — the pill and its 48 dp target do not.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.moneyGlanceThisMonth, style: text.bodySmall),
                const SizedBox(width: 6),
                MoneyText(
                  net,
                  currency: currency,
                  subunitToUnit: subunitToUnit,
                  signed: net > 0,
                  positiveGreen: true,
                  color: net == 0 ? c.inkMid : null,
                  decimals: decimals,
                ),
              ],
            ),
          ),
        ),
      ];
      semantics = l.moneyGlanceSemantics(amount);
      tap = onTap;
    }

    return Semantics(
      button: true,
      label: semantics,
      onTap: tap,
      excludeSemantics: true,
      child: PressableScale.small(
        onTap: tap,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              // 12 dp inside, the 1 dp edge included.
              padding: const EdgeInsets.symmetric(horizontal: Gap.md - 1),
              decoration: ShapeDecoration(
                color: c.surface1,
                shape: StadiumBorder(side: BorderSide(color: c.hairline)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...parts,
                  const SizedBox(width: Gap.xs),
                  Icon(Icons.chevron_right_rounded, size: 16, color: c.inkLow),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
