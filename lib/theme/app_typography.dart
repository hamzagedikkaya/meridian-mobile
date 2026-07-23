import 'package:flutter/material.dart';
import 'app_colors.dart';

const tabularFigures = [FontFeature.tabularFigures()];

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
