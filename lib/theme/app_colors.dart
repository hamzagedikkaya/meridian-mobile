import 'package:flutter/material.dart';

/// Noktürn design tokens — see docs/design.md §2.
class NokturnColors extends ThemeExtension<NokturnColors> {
  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color hairline;
  final Color divider;
  final Color inkHi;
  final Color inkMid;
  final Color inkLow;
  final Color inkFaint;
  final Color gold;
  final Color goldBright;
  final Color goldDim;
  final Color onGold;
  final Color goldContainer;
  final Color onGoldContainer;
  final Color income;
  final Color incomeContainer;
  final Color error;
  final Color errorContainer;
  final Color warning;
  final Color warningContainer;
  final Color skeletonBone;
  final List<Color> chart;
  final Color chartIncome;
  final Color chartExpense;

  const NokturnColors({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.hairline,
    required this.divider,
    required this.inkHi,
    required this.inkMid,
    required this.inkLow,
    required this.inkFaint,
    required this.gold,
    required this.goldBright,
    required this.goldDim,
    required this.onGold,
    required this.goldContainer,
    required this.onGoldContainer,
    required this.income,
    required this.incomeContainer,
    required this.error,
    required this.errorContainer,
    required this.warning,
    required this.warningContainer,
    required this.skeletonBone,
    required this.chart,
    required this.chartIncome,
    required this.chartExpense,
  });

  static const dark = NokturnColors(
    bg: Color(0xFF171310),
    surface1: Color(0xFF1E1915),
    surface2: Color(0xFF262019),
    surface3: Color(0xFF2D2620),
    hairline: Color(0xFF322A22),
    divider: Color(0xFF2A231C),
    inkHi: Color(0xFFEFE9DF),
    inkMid: Color(0xFFB3A895),
    inkLow: Color(0xFF7A7060),
    inkFaint: Color(0xFF4E463B),
    gold: Color(0xFFD4A853),
    goldBright: Color(0xFFE7C883),
    goldDim: Color(0xFF8C6D2C),
    onGold: Color(0xFF221805),
    goldContainer: Color(0xFF3B2F14),
    onGoldContainer: Color(0xFFEBD9A9),
    income: Color(0xFF6FC08D),
    incomeContainer: Color(0xFF17301F),
    error: Color(0xFFE07862),
    errorContainer: Color(0xFF351E19),
    warning: Color(0xFFE39A4E),
    warningContainer: Color(0xFF33240F),
    skeletonBone: Color(0xFF241E18),
    chart: [
      Color(0xFFC9A45C),
      Color(0xFF7FA3C0),
      Color(0xFF8FBF9F),
      Color(0xFFB08FB3),
      Color(0xFFC98F7A),
      Color(0xFFA8A86B),
    ],
    chartIncome: Color(0xFF8FBF9F),
    chartExpense: Color(0xFFC9A45C),
  );

  static const light = NokturnColors(
    bg: Color(0xFFF6F1E8),
    surface1: Color(0xFFFCFAF5),
    surface2: Color(0xFFFFFFFF),
    surface3: Color(0xFFFFFFFF),
    hairline: Color(0xFFE5DDCE),
    divider: Color(0xFFEAE2D3),
    inkHi: Color(0xFF262019),
    inkMid: Color(0xFF5F574A),
    inkLow: Color(0xFF8A8172),
    inkFaint: Color(0xFFB5AC9C),
    gold: Color(0xFF96731D),
    goldBright: Color(0xFF7A5D14),
    goldDim: Color(0xFFC0A45E),
    onGold: Color(0xFFFFFFFF),
    goldContainer: Color(0xFFF0E3C2),
    onGoldContainer: Color(0xFF4A3A10),
    income: Color(0xFF2C7A4F),
    incomeContainer: Color(0xFFDDEEE2),
    error: Color(0xFFB5432E),
    errorContainer: Color(0xFFF6DFD9),
    warning: Color(0xFFA9631F),
    warningContainer: Color(0xFFF3E4C8),
    skeletonBone: Color(0xFFEDE6D8),
    chart: [
      Color(0xFFA98436),
      Color(0xFF5F84A3),
      Color(0xFF659E77),
      Color(0xFF906E93),
      Color(0xFFA96E58),
      Color(0xFF83833F),
    ],
    chartIncome: Color(0xFF659E77),
    chartExpense: Color(0xFFA98436),
  );

  @override
  NokturnColors copyWith() => this;

  @override
  NokturnColors lerp(NokturnColors? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

extension NokturnContext on BuildContext {
  NokturnColors get nok => Theme.of(this).extension<NokturnColors>()!;
}
