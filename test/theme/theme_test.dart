/// The theme's token plumbing: NokturnColors interpolates (so the 250 ms
/// light ↔ dark change fades instead of snapping), copyWith works, and the
/// ColorScheme / component themes carry the v2 decisions (§3.3, §4.32).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/theme/app_motion.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/theme/app_typography.dart';

void main() {
  group('NokturnColors', () {
    const dark = NokturnColors.dark;
    const light = NokturnColors.light;

    test('lerp(0.5) is halfway, not a snap to either side', () {
      final mid = dark.lerp(light, 0.5);
      expect(mid.bg, Color.lerp(dark.bg, light.bg, 0.5));
      expect(mid.bg, isNot(dark.bg));
      expect(mid.bg, isNot(light.bg));
      expect(mid.inkHi, Color.lerp(dark.inkHi, light.inkHi, 0.5));
      expect(mid.scrim, Color.lerp(dark.scrim, light.scrim, 0.5));
      expect(mid.chart[3], Color.lerp(dark.chart[3], light.chart[3], 0.5));
    });

    test('lerp ends on the palettes themselves', () {
      final start = dark.lerp(light, 0);
      final end = dark.lerp(light, 1);
      expect(start.gold, dark.gold);
      expect(end.gold, light.gold);
      expect(end.track, light.track);
      expect(dark.lerp(null, 0.5), same(dark));
    });

    test('lerp moves every frame of a theme change (no flicker step)', () {
      Color? previous;
      for (var t = 0.0; t <= 1.0; t += 0.1) {
        final c = dark.lerp(light, t).surface1;
        if (previous != null) expect(c, isNot(previous));
        previous = c;
      }
    });

    test('copyWith replaces only what it is given', () {
      final c = dark.copyWith(gold: const Color(0xFF000001));
      expect(c.gold, const Color(0xFF000001));
      expect(c.inkHi, dark.inkHi);
      expect(c.scrim, dark.scrim);
      expect(dark.copyWith().onWarning, dark.onWarning);
    });

    test('the theme animates the extension with the rest', () {
      final a = buildTheme(Brightness.dark);
      final b = buildTheme(Brightness.light);
      final mid = ThemeData.lerp(a, b, 0.5);
      expect(mid.extension<NokturnColors>()!.bg,
          Color.lerp(dark.bg, light.bg, 0.5));
      expect(mid.extension<NokturnText>(), isNotNull);
    });
  });

  group('buildTheme', () {
    for (final brightness in Brightness.values) {
      test('$brightness: ColorScheme mapping (§3.3)', () {
        final theme = buildTheme(brightness);
        final c = NokturnColors.of(brightness);
        final s = theme.colorScheme;
        expect(s.onError, c.onError);
        expect(s.outline, c.inkDisabled);
        expect(s.outlineVariant, c.hairline);
        expect(s.scrim, c.scrim);
        expect(s.secondaryContainer, c.goldContainer);
        expect(s.onSecondaryContainer, c.onGoldContainer);
        expect(s.surfaceBright, c.surface3);
        expect(s.surfaceDim, c.bg);
        expect(theme.bottomSheetTheme.modalBarrierColor, c.scrim);
        expect(theme.dialogTheme.barrierColor, c.scrim);
        expect(theme.splashFactory, InkRipple.splashFactory);
        expect(theme.highlightColor, c.gold.withValues(alpha: 0.04));
        expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter');
        expect(theme.appBarTheme.titleTextStyle!.fontSize, 20);
      });
    }

    test('Fraunces styles carry no tabular figures; Inter numerics do', () {
      final theme = buildTheme(Brightness.dark);
      for (final style in [
        theme.textTheme.displayLarge!,
        theme.textTheme.headlineSmall!,
      ]) {
        expect(style.fontFamily, 'Fraunces');
        expect(style.fontFeatures, isNull);
      }
      final nok = theme.extension<NokturnText>()!;
      expect(nok.numRow.fontFeatures, tabularFigures);
      expect(nok.reading.fontSize, 17);
    });

    test('shadows only in the light theme', () {
      final dark = buildTheme(Brightness.dark);
      final light = buildTheme(Brightness.light);
      expect(dark.floatingActionButtonTheme.elevation, 0);
      expect(light.floatingActionButtonTheme.elevation, 3);
      expect(dark.bottomSheetTheme.modalElevation, 0);
      expect(light.bottomSheetTheme.modalElevation, 8);
    });
  });

  group('reduced motion', () {
    Widget app({required bool reduce}) => MaterialApp(
          theme: buildTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const Text('next')),
              ),
              child: Text('open ${Motion.sheet(context).duration}'),
            ),
          ),
        );

    testWidgets('a pushed page is there in one frame', (tester) async {
      await tester.pumpWidget(app(reduce: true));
      expect(find.text('open 0:00:00.000000'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      await tester.pump();
      // No transition wraps the new page: it is fully opaque at once.
      final next = find.text('next');
      expect(next, findsOneWidget);
      expect(
        find.ancestor(of: next, matching: find.byType(FadeTransition)),
        findsNothing,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('otherwise the platform transition plays', (tester) async {
      await tester.pumpWidget(app(reduce: false));
      expect(find.text('open ${Motion.sheetIn}'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.ancestor(of: find.text('next'), matching: find.byType(FadeTransition)),
        findsWidgets,
      );
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
