import 'package:flutter/material.dart';

/// Noktürn v2 colour tokens — design-analysis §3.1–3.4.
///
/// Read them through `context.nok`. Every text/icon token below is measured
/// against the surfaces it sits on (`test/theme/contrast_test.dart`):
///
/// * **Text and icons** that carry information: [inkHi], [inkMid], [inkLow],
///   [gold], [income], [error], [warning] and the `on*` tokens — ≥ 4.5:1 on
///   their backgrounds.
/// * **Component borders and state marks**: [inkDisabled], [goldDim] and an
///   entity tone's `fill` (see `entity_color.dart`) — ≥ 3:1.
/// * **Decorative only** (no contrast promise, never information):
///   [hairline], [divider], [inkFaint], [track].
///
/// Usage rules (§3.4): text on [goldContainer] is always [onGoldContainer];
/// red only for a real overrun, overdue, error or destructive action; green
/// only for income and real positives (zero is not green); opacity never
/// describes a state; a state is never told by colour alone.
class NokturnColors extends ThemeExtension<NokturnColors> {
  // Surfaces, bottom to top.
  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color surface3;

  /// Decorative card, list and nav edge.
  final Color hairline;

  /// Separators inside a list.
  final Color divider;

  // Ink.
  final Color inkHi;
  final Color inkMid;

  /// Tertiary text: hints, axis labels, inactive nav, placeholders.
  final Color inkLow;

  /// Component borders (inputs, outlined buttons), disabled text, "missing"
  /// marks, inactive page dots, drag handles. ≥ 3:1, not for running text.
  final Color inkDisabled;

  /// Decorative only: dashed ghost borders, rules. Never text or a state.
  final Color inkFaint;

  // The one accent: gold means "yours".
  final Color gold;
  final Color goldBright;
  final Color goldDim;
  final Color onGold;
  final Color goldContainer;
  final Color onGoldContainer;

  // Semantic states.
  final Color income;
  final Color incomeContainer;
  final Color onIncome;
  final Color error;
  final Color errorContainer;
  final Color onError;
  final Color warning;
  final Color warningContainer;
  final Color onWarning;

  /// The groove under a ring or bar fill (decorative: the value is always
  /// also given as text).
  final Color track;
  final Color skeletonBone;

  /// The 1 dp edge of overlays: snackbar, menu, tooltip.
  final Color overlayBorder;

  /// Modal barrier under sheets and dialogs.
  final Color scrim;

  // Charts.
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
    required this.inkDisabled,
    required this.inkFaint,
    required this.gold,
    required this.goldBright,
    required this.goldDim,
    required this.onGold,
    required this.goldContainer,
    required this.onGoldContainer,
    required this.income,
    required this.incomeContainer,
    required this.onIncome,
    required this.error,
    required this.errorContainer,
    required this.onError,
    required this.warning,
    required this.warningContainer,
    required this.onWarning,
    required this.track,
    required this.skeletonBone,
    required this.overlayBorder,
    required this.scrim,
    required this.chart,
    required this.chartIncome,
    required this.chartExpense,
  });

  /// The default palette (§3.1).
  static const dark = NokturnColors(
    bg: Color(0xFF171310),
    surface1: Color(0xFF1E1915),
    surface2: Color(0xFF262019),
    surface3: Color(0xFF2D2620),
    hairline: Color(0xFF322A22),
    divider: Color(0xFF2A231C),
    inkHi: Color(0xFFEFE9DF),
    inkMid: Color(0xFFB3A895),
    inkLow: Color(0xFF9A907F),
    inkDisabled: Color(0xFF7A7060),
    inkFaint: Color(0xFF4E463B),
    gold: Color(0xFFD4A853),
    goldBright: Color(0xFFE7C883),
    goldDim: Color(0xFF8C6D2C),
    onGold: Color(0xFF221805),
    goldContainer: Color(0xFF3B2F14),
    onGoldContainer: Color(0xFFEBD9A9),
    income: Color(0xFF6FC08D),
    incomeContainer: Color(0xFF17301F),
    onIncome: Color(0xFF171310),
    error: Color(0xFFE07862),
    errorContainer: Color(0xFF351E19),
    onError: Color(0xFF171310),
    warning: Color(0xFFE39A4E),
    warningContainer: Color(0xFF33240F),
    onWarning: Color(0xFF171310),
    track: Color(0xFF3A3229),
    skeletonBone: Color(0xFF2D2620),
    overlayBorder: Color(0xFF3D342A),
    scrim: Color(0x8F000000),
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

  /// The warm-paper palette (§3.2).
  static const light = NokturnColors(
    bg: Color(0xFFF6F1E8),
    surface1: Color(0xFFFCFAF5),
    surface2: Color(0xFFFFFFFF),
    surface3: Color(0xFFFFFFFF),
    hairline: Color(0xFFE5DDCE),
    divider: Color(0xFFEAE2D3),
    inkHi: Color(0xFF262019),
    inkMid: Color(0xFF5F574A),
    inkLow: Color(0xFF736B5E),
    inkDisabled: Color(0xFF8A8172),
    inkFaint: Color(0xFFB5AC9C),
    gold: Color(0xFF86661A),
    goldBright: Color(0xFF7A5D14),
    goldDim: Color(0xFFA48842),
    onGold: Color(0xFFFFFFFF),
    goldContainer: Color(0xFFF0E3C2),
    onGoldContainer: Color(0xFF4A3A10),
    income: Color(0xFF287148),
    incomeContainer: Color(0xFFDDEEE2),
    onIncome: Color(0xFFFFFFFF),
    error: Color(0xFFA83E2A),
    errorContainer: Color(0xFFF6DFD9),
    onError: Color(0xFFFFFFFF),
    warning: Color(0xFF8F5216),
    warningContainer: Color(0xFFF3E4C8),
    onWarning: Color(0xFFFFFFFF),
    track: Color(0xFFE6DDCC),
    skeletonBone: Color(0xFFEDE6D8),
    overlayBorder: Color(0xFFE5DDCE),
    scrim: Color(0x52171310),
    chart: [
      Color(0xFFA98436),
      Color(0xFF5F84A3),
      Color(0xFF5F9871),
      Color(0xFF906E93),
      Color(0xFFA96E58),
      Color(0xFF83833F),
    ],
    chartIncome: Color(0xFF5F9871),
    chartExpense: Color(0xFFA98436),
  );

  /// The palette for [brightness].
  static NokturnColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The surface an entity colour is measured against (§3.5): s3 in the dark
  /// theme (the lightest dark surface), bg in the light one (the darkest).
  Color get toneSurface => isDark ? surface3 : bg;

  /// Whether this is a dark palette — read from [bg]: a palette caught in a
  /// theme animation flips when its bg luminance crosses 0.5, which is about
  /// 77 % of the way along a straight dark → light lerp, not the midpoint.
  bool get isDark => bg.computeLuminance() < 0.5;

  @override
  NokturnColors copyWith({
    Color? bg,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? hairline,
    Color? divider,
    Color? inkHi,
    Color? inkMid,
    Color? inkLow,
    Color? inkDisabled,
    Color? inkFaint,
    Color? gold,
    Color? goldBright,
    Color? goldDim,
    Color? onGold,
    Color? goldContainer,
    Color? onGoldContainer,
    Color? income,
    Color? incomeContainer,
    Color? onIncome,
    Color? error,
    Color? errorContainer,
    Color? onError,
    Color? warning,
    Color? warningContainer,
    Color? onWarning,
    Color? track,
    Color? skeletonBone,
    Color? overlayBorder,
    Color? scrim,
    List<Color>? chart,
    Color? chartIncome,
    Color? chartExpense,
  }) =>
      NokturnColors(
        bg: bg ?? this.bg,
        surface1: surface1 ?? this.surface1,
        surface2: surface2 ?? this.surface2,
        surface3: surface3 ?? this.surface3,
        hairline: hairline ?? this.hairline,
        divider: divider ?? this.divider,
        inkHi: inkHi ?? this.inkHi,
        inkMid: inkMid ?? this.inkMid,
        inkLow: inkLow ?? this.inkLow,
        inkDisabled: inkDisabled ?? this.inkDisabled,
        inkFaint: inkFaint ?? this.inkFaint,
        gold: gold ?? this.gold,
        goldBright: goldBright ?? this.goldBright,
        goldDim: goldDim ?? this.goldDim,
        onGold: onGold ?? this.onGold,
        goldContainer: goldContainer ?? this.goldContainer,
        onGoldContainer: onGoldContainer ?? this.onGoldContainer,
        income: income ?? this.income,
        incomeContainer: incomeContainer ?? this.incomeContainer,
        onIncome: onIncome ?? this.onIncome,
        error: error ?? this.error,
        errorContainer: errorContainer ?? this.errorContainer,
        onError: onError ?? this.onError,
        warning: warning ?? this.warning,
        warningContainer: warningContainer ?? this.warningContainer,
        onWarning: onWarning ?? this.onWarning,
        track: track ?? this.track,
        skeletonBone: skeletonBone ?? this.skeletonBone,
        overlayBorder: overlayBorder ?? this.overlayBorder,
        scrim: scrim ?? this.scrim,
        chart: chart ?? this.chart,
        chartIncome: chartIncome ?? this.chartIncome,
        chartExpense: chartExpense ?? this.chartExpense,
      );

  /// A real interpolation, so the 250 ms light ↔ dark change
  /// (`MaterialApp.themeAnimationDuration`) fades every token instead of
  /// snapping halfway through.
  @override
  NokturnColors lerp(NokturnColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NokturnColors(
      bg: mix(bg, other.bg),
      surface1: mix(surface1, other.surface1),
      surface2: mix(surface2, other.surface2),
      surface3: mix(surface3, other.surface3),
      hairline: mix(hairline, other.hairline),
      divider: mix(divider, other.divider),
      inkHi: mix(inkHi, other.inkHi),
      inkMid: mix(inkMid, other.inkMid),
      inkLow: mix(inkLow, other.inkLow),
      inkDisabled: mix(inkDisabled, other.inkDisabled),
      inkFaint: mix(inkFaint, other.inkFaint),
      gold: mix(gold, other.gold),
      goldBright: mix(goldBright, other.goldBright),
      goldDim: mix(goldDim, other.goldDim),
      onGold: mix(onGold, other.onGold),
      goldContainer: mix(goldContainer, other.goldContainer),
      onGoldContainer: mix(onGoldContainer, other.onGoldContainer),
      income: mix(income, other.income),
      incomeContainer: mix(incomeContainer, other.incomeContainer),
      onIncome: mix(onIncome, other.onIncome),
      error: mix(error, other.error),
      errorContainer: mix(errorContainer, other.errorContainer),
      onError: mix(onError, other.onError),
      warning: mix(warning, other.warning),
      warningContainer: mix(warningContainer, other.warningContainer),
      onWarning: mix(onWarning, other.onWarning),
      track: mix(track, other.track),
      skeletonBone: mix(skeletonBone, other.skeletonBone),
      overlayBorder: mix(overlayBorder, other.overlayBorder),
      scrim: mix(scrim, other.scrim),
      chart: [
        for (var i = 0; i < chart.length; i++)
          i < other.chart.length ? mix(chart[i], other.chart[i]) : chart[i],
      ],
      chartIncome: mix(chartIncome, other.chartIncome),
      chartExpense: mix(chartExpense, other.chartExpense),
    );
  }
}

extension NokturnContext on BuildContext {
  NokturnColors get nok => Theme.of(this).extension<NokturnColors>()!;
}
