import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/formats.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/progress_ring.dart';

/// Parse a "#RRGGBB" (or "#AARRGGBB") goal color, falling back to gold.
/// New code draws record colours through `entityTone` (theme/entity_color).
Color goalColor(String hex) =>
    parseEntityHex(hex, fallback: const Color(0xFFD4A853));

/// The goal's colours as the theme draws them (dot, ring fill).
EntityTone goalTone(Goal g, NokturnColors c) => entityTone(g.color, c);

/// [current] against [Goal.targetValue] as a whole percentage, 0–100 —
/// what a stepped value shows before the server has recalculated it. A
/// target of 0 is 0 %, never NaN.
int goalPercentOf(Goal g, double current) {
  if (g.targetValue <= 0) return 0;
  return (current / g.targetValue * 100).clamp(0, 100).round();
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
/// Written with the language's marks: thousands grouped and its decimal
/// mark ("98.765", "7,50" in Turkish; "98,765", "7.50" in English) — as
/// the keypad and the form show the same number.
String formatGoalNumber(double v) => NumberFormat(
  v == v.roundToDouble() ? '#,##0' : '#,##0.00',
).format(v);

/// Money-correct rendering of a raw goal value (major units) for financial goals.
String formatGoalMoney(
  Goal g,
  double value, {
  MoneyDecimals decimals = MoneyDecimals.always,
}) {
  final m = goalMoneyMeta(g);
  return formatMoney(
    (value * m.subunit).round(),
    m.currency,
    m.subunit,
    decimals: decimals,
  );
}

/// Where a goal card's money switches to the compact form (major units):
/// "₺47,5B / ₺50B" from a target of 100.000 up (design-analysis §7.11).
const goalCompactMoneyFrom = 100000;

/// The card's value line: "24 / 50 ders", or money with its decimals only
/// when there are any ("₺47.500 / ₺50.000") — compact from
/// [goalCompactMoneyFrom]. [current] overrides the goal's own value (a step
/// not yet answered).
String goalValueLabel(Goal g, {double? current}) {
  final now = current ?? g.currentValue;
  if (!goalIsFinancial(g)) return goalProgressLabel(g, current: now);
  final m = goalMoneyMeta(g);
  if (g.targetValue >= goalCompactMoneyFrom) {
    String compact(double v) =>
        formatMoneyCompact((v * m.subunit).round(), m.currency, m.subunit);
    return '${compact(now)} / ${compact(g.targetValue)}';
  }
  final auto = MoneyDecimals.auto;
  return '${formatGoalMoney(g, now, decimals: auto)} / '
      '${formatGoalMoney(g, g.targetValue, decimals: auto)}';
}

/// "42 / 100 kg" or, for financial goals, money on both sides. The unit comes
/// from the server (the user typed it), so it is not translated.
/// [current] overrides the goal's own value (a step not yet answered).
String goalProgressLabel(Goal g, {double? current}) {
  final now = current ?? g.currentValue;
  if (goalIsFinancial(g)) {
    return '${formatGoalMoney(g, now)} / ${formatGoalMoney(g, g.targetValue)}';
  }
  final unit = g.unit.isEmpty ? '' : '$nbsp${g.unit}';
  return '${formatGoalNumber(now)} / ${formatGoalNumber(g.targetValue)}$unit';
}

/// Target-only label used in the achieved/abandoned rows.
String goalTargetLabel(Goal g) {
  if (goalIsFinancial(g)) return formatGoalMoney(g, g.targetValue);
  final unit = g.unit.isEmpty ? '' : '$nbsp${g.unit}';
  return '${formatGoalNumber(g.targetValue)}$unit';
}

/// A ring's centre label kept to the circle's middle two thirds: a square
/// inside the stroke still lets a wide label's corners cross the circle at
/// large text, so it shrinks rather than touch the ring.
Widget goalRingCenter(double ringSize, Widget label) => SizedBox(
  width: ringSize * 0.66,
  child: FittedBox(fit: BoxFit.scaleDown, child: label),
);

/// [child] centred in at least the whole height it is given, scrolling
/// when it needs more (small screens, landscape, large text) — so a pull
/// still refreshes and its button stays in reach (§8.3).
Widget goalScrollableFill(Widget child) => LayoutBuilder(
  builder: (context, constraints) => SingleChildScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: constraints.maxHeight),
      child: Center(child: child),
    ),
  ),
);

/// The goal ring's Hero tag: the grid card's 72 dp ring flies to the
/// detail's 160 dp one (design-analysis §5.2).
String goalRingTag(int id) => 'goal-ring-$id';

/// The flight of the goal ring: the detail's ring at its value — never
/// sweeping from zero — scaled to the flight's rect, on a transparent
/// Material so its text keeps its style.
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
  final child = hero.child;
  final ring = child is ProgressRing
      ? ProgressRing(
          value: child.value,
          color: child.color,
          size: child.size,
          strokeWidth: child.strokeWidth,
          center: child.center,
          sweepOnMount: false,
          semanticsValue: '',
        )
      : child;
  return Material(
    type: MaterialType.transparency,
    child: FittedBox(fit: BoxFit.contain, child: ring),
  );
}
