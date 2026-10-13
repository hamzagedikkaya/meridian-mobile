/// The snackbar a create form leaves behind floats over the tab's FAB or
/// capture bar in the running app (design-analysis §4.17): every create
/// form is a full page over the tabs, so the tab's FAB and bar are hidden
/// at the moment the form — or the screen it returns to — says "saved".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart'
    show financeSetupDismissedKey;
import 'package:meridian_mobile/ui/widgets/capture_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

class _Session extends SessionController {
  @override
  SessionState build() => const SessionLoggedIn();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The app as it runs, signed in, on a 390 × 844 phone.
Future<void> _pumpApp(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // The setup card hidden: while it offers the first transaction, it
  // carries that action and the FAB is hidden.
  SharedPreferences.setMockInitialValues({
    'locale': 'tr',
    financeSetupDismissedKey: true,
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sessionProvider.overrideWith(_Session.new),
      dioProvider.overrideWithValue(api.dio),
    ],
    child: const MeridianApp(),
  ));
  await _settle(tester);
}

/// The snackbar on view: the one the shell's scaffold draws.
Rect _snackRect(WidgetTester tester, String text) => tester.getRect(
      find
          .ancestor(of: find.text(text), matching: find.byType(Material))
          .first,
    );

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('"İşlem kaydedildi", said once the form has gone, floats over '
      'the Finance FAB', (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api);
    await tester.tap(find.text('Finans'));
    await _settle(tester);
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    await _settle(tester);
    for (final digit in '250'.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.tap(find.text('Kaydet'));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('İşlem kaydedildi'), findsWidgets);
    final snack = _snackRect(tester, 'İşlem kaydedildi');
    final fabRect = tester.getRect(fab);
    expect(snack.overlaps(fabRect), isFalse,
        reason: 'snack $snack, FAB $fabRect');
    expect(snack.bottom, lessThanOrEqualTo(fabRect.top));
    // The FAB still takes taps.
    expect(fab.hitTestable(), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
  });

  testWidgets('"“Yoga” eklendi", said as the event form closes, floats over '
      'the Agenda capture bar', (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api);
    await tester.tap(find.text('Ajanda'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Etkinlik ekle'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Dişçi');
    await tester.tap(find.text('Kaydet'));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('“Yoga” eklendi'), findsWidgets);
    final snack = _snackRect(tester, '“Yoga” eklendi');
    final bar = tester.getRect(find.byType(CaptureBar));
    expect(snack.overlaps(bar.deflate(8)), isFalse,
        reason: 'snack $snack, bar $bar');
    // The bar still takes taps.
    expect(find.byType(CaptureBar).hitTestable(), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
  });
}
