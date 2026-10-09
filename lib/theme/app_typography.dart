import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Tabular (fixed-width) figures. Only Inter has them: Fraunces ships no
/// `tnum`, so the feature does nothing on a Fraunces style — numbers set in
/// Fraunces that change get fixed digit slots from `RollingNumber` instead.
const tabularFigures = [FontFeature.tabularFigures()];

/// The type scale (design-analysis §3.6): Fraunces 600 for headlines and the
/// big numbers, Inter 400/500/600 for the interface. Never ask for w700 — it
/// is not bundled and would be synthesised.
///
/// | Role | Use |
/// |---|---|
/// | displayLarge 40/46 | Finance hero net, amount entry |
/// | displayMedium 32/38 | Account balance, goal %, 160 dp ring centre |
/// | displaySmall 28/34 | Keypad digits, journal day number |
/// | headlineLarge 26/32 | Tab-root titles, Today greeting |
/// | headlineMedium 22/28 | Dialog titles, entity sheet titles |
/// | headlineSmall 20/26 | Pushed page and form app bars, EmptyState |
/// | titleLarge 18/24 | Sheet titles |
/// | titleMedium 16/22 | Every row, section and card title |
/// | titleSmall 14/20 | Day headers (mixed case, inkMid), emphasised labels |
/// | bodyLarge 15/22 | Input text |
/// | bodyMedium 14/20 | Body copy, empty states |
/// | bodySmall 13/18 | Row meta (inkMid) |
/// | labelLarge 14/20 | Chip and text-button labels |
/// | labelMedium 12/16 | UPPERCASE overlines only (uppercased in l10n) |
/// | labelSmall 11/14 | Badges, axes, nav labels, small meta |
///
/// Fraunces is never used under 20 sp, in running text, chips, buttons or
/// overlines.
TextTheme buildTextTheme(NokturnColors c) {
  TextStyle fraunces(double size, double line, {double tracking = 0}) =>
      TextStyle(
        fontFamily: 'Fraunces',
        fontSize: size,
        height: line / size,
        fontWeight: FontWeight.w600,
        letterSpacing: tracking,
        color: c.inkHi,
      );

  TextStyle inter(double size, double line, FontWeight weight,
          {double tracking = 0, Color? color}) =>
      TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        height: line / size,
        fontWeight: weight,
        letterSpacing: tracking,
        color: color ?? c.inkHi,
      );

  return TextTheme(
    displayLarge: fraunces(40, 46, tracking: -0.5),
    displayMedium: fraunces(32, 38, tracking: -0.25),
    displaySmall: fraunces(28, 34),
    headlineLarge: fraunces(26, 32),
    headlineMedium: fraunces(22, 28),
    headlineSmall: fraunces(20, 26),
    titleLarge: inter(18, 24, FontWeight.w600),
    titleMedium: inter(16, 22, FontWeight.w600),
    titleSmall: inter(14, 20, FontWeight.w600, tracking: 0.1),
    bodyLarge: inter(15, 22, FontWeight.w400),
    bodyMedium: inter(14, 20, FontWeight.w400),
    bodySmall: inter(13, 18, FontWeight.w400, tracking: 0.1, color: c.inkMid),
    labelLarge: inter(14, 20, FontWeight.w500, tracking: 0.1),
    labelMedium: inter(12, 16, FontWeight.w500, tracking: 0.8, color: c.inkMid),
    labelSmall: inter(11, 14, FontWeight.w500, tracking: 0.4, color: c.inkMid),
  );
}

/// The numeric and reading styles the Material roles do not cover
/// (§3.6). Read them through `context.nokText`:
///
///     Text(amount, style: context.nokText.numRow)
///
/// All are Inter; the numeric ones carry [tabularFigures] so columns of
/// figures line up and counters do not jitter. Colours default to `inkHi`;
/// pass a semantic colour with `copyWith(color: …)`.
class NokturnText extends ThemeExtension<NokturnText> {
  /// Row amounts — Inter 15/20 w600, tabular.
  final TextStyle numRow;

  /// StatTile values — Inter 20/24 w600, tabular, −0.2.
  final TextStyle numStat;

  /// Meta numbers, goal "x / y", counters — Inter 13/18 w500, tabular.
  final TextStyle numMeta;

  /// Agenda times — Inter 13/18 w500, tabular, no tracking.
  final TextStyle time;

  /// FilledButton and FAB labels — Inter 15/20 w600, +0.1.
  final TextStyle button;

  /// Journal body — Inter 17/28 w400.
  final TextStyle reading;

  const NokturnText({
    required this.numRow,
    required this.numStat,
    required this.numMeta,
    required this.time,
    required this.button,
    required this.reading,
  });

  factory NokturnText.of(NokturnColors c) {
    TextStyle inter(double size, double line, FontWeight weight,
            {double tracking = 0, bool tabular = false}) =>
        TextStyle(
          fontFamily: 'Inter',
          fontSize: size,
          height: line / size,
          fontWeight: weight,
          letterSpacing: tracking,
          color: c.inkHi,
          fontFeatures: tabular ? tabularFigures : null,
        );

    return NokturnText(
      numRow: inter(15, 20, FontWeight.w600, tabular: true),
      numStat: inter(20, 24, FontWeight.w600, tracking: -0.2, tabular: true),
      numMeta: inter(13, 18, FontWeight.w500, tabular: true),
      time: inter(13, 18, FontWeight.w500, tabular: true),
      button: inter(15, 20, FontWeight.w600, tracking: 0.1),
      reading: inter(17, 28, FontWeight.w400),
    );
  }

  @override
  NokturnText copyWith({
    TextStyle? numRow,
    TextStyle? numStat,
    TextStyle? numMeta,
    TextStyle? time,
    TextStyle? button,
    TextStyle? reading,
  }) =>
      NokturnText(
        numRow: numRow ?? this.numRow,
        numStat: numStat ?? this.numStat,
        numMeta: numMeta ?? this.numMeta,
        time: time ?? this.time,
        button: button ?? this.button,
        reading: reading ?? this.reading,
      );

  @override
  NokturnText lerp(NokturnText? other, double t) {
    if (other == null) return this;
    TextStyle mix(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return NokturnText(
      numRow: mix(numRow, other.numRow),
      numStat: mix(numStat, other.numStat),
      numMeta: mix(numMeta, other.numMeta),
      time: mix(time, other.time),
      button: mix(button, other.button),
      reading: mix(reading, other.reading),
    );
  }
}

extension NokturnTextContext on BuildContext {
  /// The numeric and reading styles — mirrors `context.nok` for colours.
  NokturnText get nokText => Theme.of(this).extension<NokturnText>()!;
}
