import 'package:flutter/material.dart';

import '../../../core/formats.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';

/// Parse a "#RRGGBB" (or "#AARRGGBB") goal color, falling back to gold.
Color goalColor(String hex) {
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return const Color(0xFFD4A853);
  return Color(int.tryParse(h, radix: 16) ?? 0xFFD4A853);
}

String goalTypeOverline(AppL10n l, String targetType) => switch (targetType) {
      'financial' => l.goalsTypeFinancial,
      'habit' => l.goalsTypeHabit,
      _ => l.goalsTypeCustom,
    };

String goalStatusLabel(AppL10n l, String status) => switch (status) {
      'achieved' => l.goalsStatusAchieved,
      'abandoned' => l.goalsStatusAbandoned,
      _ => l.goalsStatusActive,
    };

bool goalIsFinancial(Goal g) => g.targetType == 'financial';

/// Currency + subunit for a financial goal: prefer the linked account, else
/// treat `unit` as the currency code (GAU → 1 subunit, else 100).
({String currency, int subunit}) goalMoneyMeta(Goal g) {
  final currency = g.related?.currency ?? g.unit;
  final subunit = g.related?.subunitToUnit ?? (currency == 'GAU' ? 1 : 100);
  return (currency: currency, subunit: subunit);
}

/// Trim a trailing `.0` from goal values (kg / level / days).
String formatGoalNumber(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// Money-correct rendering of a raw goal value (major units) for financial goals.
String formatGoalMoney(Goal g, double value) {
  final m = goalMoneyMeta(g);
  return formatMoney((value * m.subunit).round(), m.currency, m.subunit);
}

/// "42 / 100 kg" or, for financial goals, money on both sides. The unit comes
/// from the server (the user typed it), so it is not translated.
String goalProgressLabel(Goal g) {
  if (goalIsFinancial(g)) {
    return '${formatGoalMoney(g, g.currentValue)} / ${formatGoalMoney(g, g.targetValue)}';
  }
  final unit = g.unit.isEmpty ? '' : ' ${g.unit}';
  return '${formatGoalNumber(g.currentValue)} / ${formatGoalNumber(g.targetValue)}$unit';
}

/// Target-only label used in the achieved/abandoned rows.
String goalTargetLabel(Goal g) {
  if (goalIsFinancial(g)) return formatGoalMoney(g, g.targetValue);
  final unit = g.unit.isEmpty ? '' : ' ${g.unit}';
  return '${formatGoalNumber(g.targetValue)}$unit';
}

/// Scales the ProgressRing smoothly during the Hero flight (72dp ↔ 160dp).
Widget goalRingFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) {
  final hero =
      (direction == HeroFlightDirection.push ? toContext : fromContext).widget
          as Hero;
  return Material(
    color: Colors.transparent,
    child: FittedBox(fit: BoxFit.contain, child: hero.child),
  );
}
