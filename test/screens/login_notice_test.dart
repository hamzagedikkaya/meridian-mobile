/// What the login screen says about how the last session ended.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LoggedOut extends SessionController {
  _LoggedOut(this._state);
  final SessionLoggedOut _state;

  @override
  SessionState build() => _state;
}

Future<void> _pump(WidgetTester tester, SessionLoggedOut state) async {
  // No address yet: nothing is pinged.
  SharedPreferences.setMockInitialValues({PrefKeys.serverUrl: ''});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sessionProvider.overrideWith(() => _LoggedOut(state)),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      locale: const Locale('tr'),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: const LoginScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('signed out but the server never heard: said so', (tester) async {
    await _pump(tester, const SessionLoggedOut(revokeFailed: true));
    expect(find.textContaining('oturum sunucuda kapatılamadı'), findsOneWidget);
  });

  testWidgets('a session that expired mid-use: said so', (tester) async {
    await _pump(tester, const SessionLoggedOut(expired: true));
    expect(find.text('Oturum süresi doldu, tekrar giriş yap'), findsOneWidget);
  });

  testWidgets('a plain sign-out: nothing to say', (tester) async {
    await _pump(tester, const SessionLoggedOut());
    expect(find.byType(SnackBar), findsNothing);
  });
}
