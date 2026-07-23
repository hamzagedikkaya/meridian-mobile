import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? NokturnColors.dark
      : NokturnColors.light;
  final text = buildTextTheme(c);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.gold,
    onPrimary: c.onGold,
    primaryContainer: c.goldContainer,
    onPrimaryContainer: c.onGoldContainer,
    secondary: c.goldDim,
    onSecondary: c.onGold,
    error: c.error,
    onError: c.inkHi,
    errorContainer: c.errorContainer,
    onErrorContainer: c.error,
    surface: c.bg,
    onSurface: c.inkHi,
    surfaceContainerLowest: c.bg,
    surfaceContainerLow: c.surface1,
    surfaceContainer: c.surface2,
    surfaceContainerHigh: c.surface3,
    surfaceContainerHighest: c.surface3,
    onSurfaceVariant: c.inkMid,
    outline: c.hairline,
    outlineVariant: c.divider,
    inverseSurface: c.inkHi,
    onInverseSurface: c.bg,
    inversePrimary: c.goldDim,
    shadow: Colors.black,
    scrim: const Color(0xFF171310),
    surfaceTint: Colors.transparent,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    textTheme: text,
    extensions: [c],
    splashColor: c.gold.withValues(alpha: 0.08),
    highlightColor: Colors.transparent,
    dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineLarge,
      iconTheme: IconThemeData(color: c.inkMid, size: 24),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: c.surface2,
      surfaceTintColor: Colors.transparent,
      // NOTE: M3 NavigationBar hardcodes its indicator to 64x32; the design's
      // 32x20 goldContainer pill can't be reached through the theme (no size
      // hook), so we only set its color here and accept the default size.
      indicatorColor: c.goldContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelSmall!.copyWith(
          color: states.contains(WidgetState.selected) ? c.gold : c.inkLow,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? c.gold : c.inkLow,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface2,
      contentPadding: const EdgeInsets.all(16),
      labelStyle: text.bodyLarge!.copyWith(color: c.inkMid),
      hintStyle: text.bodyLarge!.copyWith(color: c.inkLow),
      errorStyle: text.bodySmall!.copyWith(color: c.error),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.gold, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.error, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.gold,
        foregroundColor: c.onGold,
        disabledBackgroundColor: c.goldDim.withValues(alpha: 0.4),
        disabledForegroundColor: c.inkLow,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.gold,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.inkHi,
        side: BorderSide(color: c.hairline),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: text.labelLarge,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.gold,
      foregroundColor: c.onGold,
      elevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface3,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: text.headlineMedium,
      contentTextStyle: text.bodyMedium!.copyWith(color: c.inkMid),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface3,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: c.surface3,
      showDragHandle: true,
      dragHandleColor: c.inkFaint,
      dragHandleSize: const Size(32, 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface3,
      contentTextStyle: text.bodyMedium,
      actionTextColor: c.gold,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface2,
      selectedColor: c.goldContainer,
      labelStyle: text.labelLarge!.copyWith(color: c.inkHi),
      side: BorderSide(color: c.hairline),
      shape: const StadiumBorder(),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.gold,
      linearTrackColor: c.surface2,
      circularTrackColor: c.surface2,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: c.inkLow, width: 2),
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.gold : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(c.onGold),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.inkMid,
      textColor: c.inkHi,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
