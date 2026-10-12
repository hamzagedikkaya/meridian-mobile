@Tags(['golden'])
/// Giriş (Login) and its "where do I find the address?" sheet.
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-14.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/ui/screens/login_screen.dart';
import 'package:meridian_mobile/ui/widgets/server_url_field.dart';

import 'golden_harness.dart';

/// The login screen; the saved address answers, so the field has folded
/// into its "host · Değiştir" row and the credentials are at full strength.
Future<void> _pumpLogin(WidgetTester tester) async {
  await tester.pumpWidget(goldenHost(
    const LoginScreen(),
    [
      sharedPrefsProvider.overrideWithValue(goldenPrefs),
      serverPingProvider.overrideWithValue(
        (url) async => (ok: true, latencyMs: 12, version: '1.0.0'),
      ),
    ],
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpGoldens();

  goldenScreen('login', (tester, _) async {
    await _pumpLogin(tester);
  });

  goldenScreen('login_help_sheet', (tester, _) async {
    await _pumpLogin(tester);
    // The field open again, its help link under it.
    await tester.tap(find.byType(ServerUrlField));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ServerAddressHelpButton));
    await tester.pumpAndSettle();
  });
}
