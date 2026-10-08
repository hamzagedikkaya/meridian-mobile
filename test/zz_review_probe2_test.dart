import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('undo snackbar lifetime', (tester) async {
    tester.view.physicalSize = const Size(1170, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = FakeApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(api.dio),
          sharedPrefsProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          locale: const Locale('tr'),
          supportedLocales: AppL10n.supportedLocales,
          localizationsDelegates: const [
            AppL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const TodayScreen(),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('todo-39')));
    await _settle(tester);
    // ignore: avoid_print
    print('snackbar right after: ${find.byType(SnackBar).evaluate().length}');
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    // ignore: avoid_print
    print('snackbar after 42s: ${find.byType(SnackBar).evaluate().length}');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(days: 1));
  });
}
