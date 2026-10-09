/// The wiring in `MeridianApp` (main.dart): the light ↔ dark fade and the
/// app's reduced-motion switch reaching every screen below the router.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/router/app_router.dart';
import 'package:meridian_mobile/theme/app_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<bool> pumpApp(
    WidgetTester tester, {
    required Map<String, Object> stored,
    bool system = false,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    late bool reduced;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) {
          reduced = Motion.reduced(context);
          return const SizedBox();
        },
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(disableAnimations: system),
      child: ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          routerProvider.overrideWithValue(router),
        ],
        child: const MeridianApp(),
      ),
    ));
    await tester.pumpAndSettle();
    return reduced;
  }

  MaterialApp app(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp));

  testWidgets('fades the theme over 250 ms by default', (tester) async {
    final reduced = await pumpApp(tester, stored: {});
    expect(app(tester).themeAnimationDuration, Motion.themeChange);
    expect(Motion.themeChange, const Duration(milliseconds: 250));
    expect(app(tester).themeAnimationCurve, Motion.themeCurve);
    expect(reduced, isFalse);
  });

  testWidgets('the app switch snaps the theme and reaches the screens',
      (tester) async {
    final reduced =
        await pumpApp(tester, stored: {PrefKeys.reduceMotion: 'true'});
    expect(app(tester).themeAnimationDuration, Duration.zero);
    expect(reduced, isTrue);
  });

  testWidgets('the system flag snaps the theme too', (tester) async {
    final reduced = await pumpApp(tester, stored: {}, system: true);
    expect(app(tester).themeAnimationDuration, Duration.zero);
    expect(reduced, isTrue);
  });
}
