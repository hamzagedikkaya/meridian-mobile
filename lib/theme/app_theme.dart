import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_metrics.dart';
import 'app_motion.dart';
import 'app_typography.dart';

/// The Noktürn v2 theme (design-analysis §3.3, §3.12, §4.8–4.18, §4.32).
///
/// Everything a stock Material widget needs to look right is set here, so a
/// screen only reaches for `context.nok` / `context.nokText` when it draws
/// something of its own. Shadows exist only in the light theme; the dark one
/// separates layers with surfaces and hairlines.
ThemeData buildTheme(Brightness brightness) {
  final c = NokturnColors.of(brightness);
  final dark = brightness == Brightness.dark;
  final text = buildTextTheme(c);
  final nokText = NokturnText.of(c);

  // Light-theme shadow: a warm 20 % ink, never black.
  const lightShadow = Color(0x33171310);
  final shadow = dark ? Colors.black : lightShadow;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.gold,
    onPrimary: c.onGold,
    primaryContainer: c.goldContainer,
    onPrimaryContainer: c.onGoldContainer,
    secondary: c.goldDim,
    onSecondary: c.onGold,
    // The date-range band and other secondary containers carry text, so
    // they take the readable gold pair (9.38:1), not goldDim + onGold.
    secondaryContainer: c.goldContainer,
    onSecondaryContainer: c.onGoldContainer,
    error: c.error,
    onError: c.onError,
    errorContainer: c.errorContainer,
    onErrorContainer: c.error,
    surface: c.bg,
    onSurface: c.inkHi,
    surfaceContainerLowest: c.bg,
    surfaceContainerLow: c.surface1,
    surfaceContainer: c.surface2,
    surfaceContainerHigh: c.surface3,
    surfaceContainerHighest: c.surface3,
    surfaceBright: c.surface3,
    surfaceDim: c.bg,
    onSurfaceVariant: c.inkMid,
    outline: c.inkDisabled,
    outlineVariant: c.hairline,
    inverseSurface: c.inkHi,
    onInverseSurface: c.bg,
    inversePrimary: c.goldDim,
    shadow: shadow,
    scrim: c.scrim,
    surfaceTint: Colors.transparent,
  );

  // Status and navigation bars: transparent, edge to edge (§3.12). Routes
  // without an AppBar give the same style through `nokSystemOverlay`.
  final overlay = nokSystemOverlay(brightness);

  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: Radii.mdAll,
        borderSide: BorderSide(color: color, width: width),
      );

  final overlayShape = RoundedRectangleBorder(
    borderRadius: Radii.mdAll,
    side: BorderSide(color: c.overlayBorder),
  );

  final buttonLabel = text.labelLarge!.copyWith(fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    shadowColor: shadow,
    textTheme: text,
    extensions: [c, nokText],
    // Ripples (D2): a gold InkRipple that reads on every surface, and a
    // faint gold highlight so a held row shows it is pressed.
    splashFactory: InkRipple.splashFactory,
    splashColor: c.gold.withValues(alpha: dark ? 0.10 : 0.12),
    highlightColor: c.gold.withValues(alpha: 0.04),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.gold,
      selectionColor: c.gold.withValues(alpha: 0.32),
      selectionHandleColor: c.gold,
    ),
    iconTheme: IconThemeData(color: c.inkMid, size: 24),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(Icons.arrow_back_rounded),
      closeButtonIconBuilder: (_) => const Icon(Icons.close_rounded),
    ),
    dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      // Known limitation: ThemeData.lerp flattens this WidgetStateColor to a
      // plain bg lerp, so during the 250 ms theme change a scrolled-under bar
      // shows bg (≈1.07:1 from s1) until the last frame. Same for the chip
      // side and the floating label below. Cosmetic only.
      backgroundColor: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.scrolledUnder) ? c.surface1 : c.bg,
      ),
      foregroundColor: c.inkHi,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // Pushed pages and forms; tab roots pass `headlineLarge` themselves.
      titleTextStyle: text.headlineSmall,
      iconTheme: IconThemeData(color: c.inkMid, size: 24),
      actionsIconTheme: IconThemeData(color: c.inkMid, size: 24),
      systemOverlayStyle: overlay,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: c.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // NOTE: M3 NavigationBar hardcodes its indicator to 64x32; the design's
      // 32x20 goldContainer pill can't be reached through the theme (no size
      // hook), so we only set its color here and accept the default size.
      indicatorColor: c.goldContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? text.labelSmall!
                .copyWith(color: c.gold, fontWeight: FontWeight.w600)
            : text.labelSmall!
                .copyWith(color: c.inkLow, fontWeight: FontWeight.w500),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? c.gold : c.inkLow,
        ),
      ),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: c.error,
      textColor: c.onError,
      textStyle: text.labelSmall!.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: tabularFigures,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: c.surface2,
      // 15 + 22 (bodyLarge line) + 15 = 52 dp, level with the primary
      // button. §4.11 says both "vertical: 14" and "52 dp"; 14 measures 50 dp,
      // so the height wins.
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: text.bodyLarge!.copyWith(color: c.inkMid),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (states) => text.bodySmall!.copyWith(
          color: states.contains(WidgetState.error)
              ? c.error
              : states.contains(WidgetState.focused)
                  ? c.gold
                  : c.inkMid,
        ),
      ),
      hintStyle: text.bodyLarge!.copyWith(color: c.inkLow),
      helperStyle: text.bodySmall!.copyWith(color: c.inkLow),
      errorStyle: text.bodySmall!.copyWith(color: c.error),
      errorMaxLines: 2,
      prefixIconColor: c.inkMid,
      suffixIconColor: c.inkMid,
      // inkDisabled: 3.79:1 on bg, 3.31:1 on the field's own fill.
      border: inputBorder(c.inkDisabled),
      enabledBorder: inputBorder(c.inkDisabled),
      focusedBorder: inputBorder(c.gold, 1.5),
      errorBorder: inputBorder(c.error),
      focusedErrorBorder: inputBorder(c.error, 1.5),
      disabledBorder: inputBorder(c.hairline),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        // Not full width: a caller that wants it wraps the button in
        // `SizedBox(width: double.infinity)`.
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: Gap.xxl),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: WidgetStatePropertyAll(nokText.button),
        iconSize: const WidgetStatePropertyAll(20),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? (dark ? c.surface3 : c.skeletonBone)
              : c.gold,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? c.inkDisabled : c.onGold,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? c.inkDisabled : c.onGold,
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? c.onGold.withValues(alpha: 0.10)
              : states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                  ? c.onGold.withValues(alpha: 0.08)
                  : null,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.inkHi,
        disabledForegroundColor: c.inkDisabled,
        side: BorderSide(color: c.inkDisabled),
        minimumSize: const Size(64, Hit.min),
        shape: const StadiumBorder(),
        textStyle: buttonLabel,
        iconSize: 18,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.gold,
        disabledForegroundColor: c.inkDisabled,
        minimumSize: Hit.minSize,
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        textStyle: buttonLabel,
        iconSize: 18,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.inkMid,
        disabledForegroundColor: c.inkDisabled,
        minimumSize: Hit.minSize,
        iconSize: 24,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.gold,
      foregroundColor: c.onGold,
      elevation: dark ? 0 : 3,
      focusElevation: dark ? 0 : 3,
      hoverElevation: dark ? 0 : 3,
      highlightElevation: dark ? 0 : 3,
      shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
      iconSize: 24,
      extendedSizeConstraints:
          const BoxConstraints.tightFor(height: 56),
      extendedPadding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      extendedIconLabelSpacing: Gap.sm,
      extendedTextStyle: nokText.button,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface2,
      selectedColor: c.goldContainer,
      disabledColor: c.surface2,
      checkmarkColor: c.onGoldContainer,
      // M3 chips never read secondaryLabelStyle; they resolve labelStyle's
      // colour against their states. The selected w600 weight cannot vary by
      // state in a theme — NokChip (WP-2) owns it.
      labelStyle: text.labelLarge!.copyWith(
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.onGoldContainer
              : c.inkMid,
        ),
      ),
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected) ? c.goldDim : c.hairline,
        ),
      ),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Gap.sm),
      iconTheme: IconThemeData(color: c.inkMid, size: 16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface3,
      modalBackgroundColor: c.surface3,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: dark ? 0 : 8,
      shadowColor: shadow,
      modalBarrierColor: c.scrim,
      showDragHandle: true,
      // 3.06:1 on s3 — a handle people need to find.
      dragHandleColor: c.inkDisabled,
      dragHandleSize: const Size(32, 4),
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      constraints: const BoxConstraints(maxWidth: 640),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface3,
      surfaceTintColor: Colors.transparent,
      elevation: dark ? 0 : 6,
      shadowColor: shadow,
      barrierColor: c.scrim,
      shape: const RoundedRectangleBorder(borderRadius: Radii.xlAll),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: Gap.xxl, vertical: Gap.xxl),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
      titleTextStyle: text.headlineMedium,
      contentTextStyle: text.bodyLarge!.copyWith(color: c.inkMid),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface3,
      contentTextStyle: text.bodyMedium!.copyWith(color: c.inkHi),
      actionTextColor: c.gold,
      behavior: SnackBarBehavior.floating,
      elevation: dark ? 0 : 6,
      shape: overlayShape,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface3,
      surfaceTintColor: Colors.transparent,
      shadowColor: shadow,
      elevation: dark ? 0 : 6,
      shape: overlayShape,
      textStyle: text.bodyLarge,
      labelTextStyle: WidgetStatePropertyAll(text.bodyLarge),
      iconColor: c.inkMid,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.surface3,
        borderRadius: Radii.smAll,
        border: Border.all(color: c.overlayBorder),
      ),
      textStyle: text.labelSmall!.copyWith(color: c.inkHi),
      waitDuration: Motion.tooltipWait,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: c.inkMid,
      collapsedIconColor: c.inkMid,
      textColor: c.inkHi,
      collapsedTextColor: c.inkHi,
      tilePadding: const EdgeInsets.symmetric(horizontal: Insets.rowH),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.onGold : c.inkMid,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.gold : c.surface3,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : c.inkDisabled,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.gold,
      linearTrackColor: c.track,
      circularTrackColor: c.track,
      refreshBackgroundColor: c.surface3,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: c.inkLow, width: 2),
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.gold : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(c.onGold),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: Insets.rowH),
      iconColor: c.inkMid,
      textColor: c.inkHi,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: c.surface3,
      surfaceTintColor: Colors.transparent,
      elevation: dark ? 0 : 6,
      shadowColor: shadow,
      shape: const RoundedRectangleBorder(borderRadius: Radii.xlAll),
      headerForegroundColor: c.inkHi,
      headerHeadlineStyle: text.headlineMedium,
      headerHelpStyle: text.labelMedium,
      weekdayStyle: text.bodySmall,
      dayStyle: text.bodyMedium!.copyWith(fontFeatures: tabularFigures),
      dayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? c.onGold
            : states.contains(WidgetState.disabled)
                ? c.inkDisabled
                : c.inkHi,
      ),
      dayBackgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.gold : null,
      ),
      todayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.onGold : c.gold,
      ),
      todayBackgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.gold : null,
      ),
      todayBorder: BorderSide(color: c.gold),
      yearStyle: text.bodyLarge!.copyWith(fontFeatures: tabularFigures),
      yearForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? c.onGold
            : states.contains(WidgetState.disabled)
                ? c.inkDisabled
                : c.inkHi,
      ),
      yearBackgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.gold : null,
      ),
      rangePickerBackgroundColor: c.surface3,
      rangePickerSurfaceTintColor: Colors.transparent,
      rangePickerHeaderForegroundColor: c.inkHi,
      rangePickerHeaderHeadlineStyle: text.headlineMedium,
      rangeSelectionBackgroundColor: c.goldContainer,
      dividerColor: c.hairline,
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: c.surface3,
      elevation: dark ? 0 : 6,
      shape: const RoundedRectangleBorder(borderRadius: Radii.xlAll),
      hourMinuteShape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
      hourMinuteColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? c.goldContainer
            : c.surface2,
      ),
      hourMinuteTextColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? c.onGoldContainer
            : c.inkHi,
      ),
      hourMinuteTextStyle: text.displayMedium,
      timeSelectorSeparatorColor: WidgetStatePropertyAll(c.inkHi),
      dialBackgroundColor: c.surface2,
      dialHandColor: c.gold,
      dialTextColor: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.onGold : c.inkHi,
      ),
      dayPeriodBorderSide: BorderSide(color: c.inkDisabled),
      dayPeriodColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? c.goldContainer
            : Colors.transparent,
      ),
      dayPeriodTextColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? c.onGoldContainer
            : c.inkMid,
      ),
      entryModeIconColor: c.inkMid,
      helpTextStyle: text.labelMedium,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android:
            ReducedMotionPageTransitionsBuilder(
                PredictiveBackPageTransitionsBuilder()),
        TargetPlatform.iOS:
            ReducedMotionPageTransitionsBuilder(CupertinoPageTransitionsBuilder()),
        TargetPlatform.macOS:
            ReducedMotionPageTransitionsBuilder(CupertinoPageTransitionsBuilder()),
      },
    ),
  );
}

/// The system-bar style for [brightness]: transparent status and navigation
/// bars over the app's own background (edge to edge, §3.12), with light or
/// dark icons to match. AppBars get it from the theme; a route without an
/// AppBar (Today, sheets, the keypad, the journal editor) wraps itself in
/// `AnnotatedRegion<SystemUiOverlayStyle>(value: nokSystemOverlay(…))`.
SystemUiOverlayStyle nokSystemOverlay(Brightness brightness) =>
    (brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: true,
    );

/// A page transition that steps aside under reduced motion: the new page is
/// simply there. The system's "Remove animations" only shortens route
/// animations; the app's own switch (`reduceMotionProvider`) needs this to
/// take effect at all (§5.9). Otherwise it is [delegate], unchanged.
class ReducedMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const ReducedMotionPageTransitionsBuilder(this.delegate);

  final PageTransitionsBuilder delegate;

  @override
  Duration get transitionDuration => delegate.transitionDuration;

  @override
  Duration get reverseTransitionDuration => delegate.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition {
    final inner = delegate.delegatedTransition;
    if (inner == null) return null;
    return (context, animation, secondaryAnimation, allowSnapshotting, child) =>
        Motion.reduced(context)
            ? child
            : inner(
                context,
                animation,
                secondaryAnimation,
                allowSnapshotting,
                child,
              );
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      Motion.reduced(context)
          ? child
          : delegate.buildTransitions(
              route,
              context,
              animation,
              secondaryAnimation,
              child,
            );
}
