/// The server address after review (WP-14 review fixes, design-analysis
/// §7.1): only a ping of the address in the field counts — on the login
/// screen and in the server settings — a failed one can be tried again,
/// also by itself when the app comes back, and a new address says before
/// saving that it signs this phone out.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/login_screen.dart';
import 'package:meridian_mobile/ui/screens/profile/server_screen.dart';
import 'package:meridian_mobile/ui/widgets/server_url_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_stores.dart';

const _up = (ok: true, latencyMs: 38, version: '1.4.0');
const _down = (ok: false, latencyMs: null, version: null);

/// Pings that wait for the test to answer them, by address.
class _Pings {
  final sent = <String>[];
  final _answers = <Completer<HealthResult>>[];

  Future<HealthResult> call(String url) {
    sent.add(url);
    final answer = Completer<HealthResult>();
    _answers.add(answer);
    return answer.future;
  }

  /// Answers the [index]th ping sent.
  void answer(int index, HealthResult result) =>
      _answers[index].complete(result);
}

const _delegates = [
  AppL10n.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

late SharedPreferences _prefs;
late ProviderContainer _container;

/// The server settings, signed in to `meridian.test`, over a blank page.
Future<void> _pumpServer(WidgetTester tester, _Pings pings) async {
  _phone(tester);
  SharedPreferences.setMockInitialValues({
    PrefKeys.serverUrl: 'http://meridian.test:3000',
  });
  _prefs = await SharedPreferences.getInstance();
  final tokens = MemoryTokenStore(origin: 'http://meridian.test:3000');
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(path: '/server', builder: (_, _) => const ServerScreen()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(_prefs),
        ...signedInOverrides(tokens: tokens),
        serverPingProvider.overrideWithValue(pings.call),
      ],
      child: MaterialApp.router(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: _delegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  router.push('/server');
  await tester.pumpAndSettle();
  _container = ProviderScope.containerOf(
    tester.element(find.byType(ServerScreen)),
  );
}

/// Signed out, for the login screen.
class _SignedOut extends SessionController {
  @override
  SessionState build() => const SessionLoggedOut();
}

/// The login screen with [saved] as this phone's address.
Future<void> _pumpLogin(
  WidgetTester tester,
  _Pings pings, {
  String? saved,
}) async {
  _phone(tester);
  SharedPreferences.setMockInitialValues({PrefKeys.serverUrl: ?saved});
  _prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(_prefs),
        sessionProvider.overrideWith(_SignedOut.new),
        serverPingProvider.overrideWithValue(pings.call),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: _delegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const LoginScreen(),
      ),
    ),
  );
  await tester.pump();
  _container = ProviderScope.containerOf(
    tester.element(find.byType(LoginScreen)),
  );
}

Finder get _serverAddress => find.widgetWithText(TextField, 'Sunucu adresi');

bool _credentialsLocked(WidgetTester tester) => tester
    .widget<IgnorePointer>(
      find
          .ancestor(
            of: find.widgetWithText(TextField, 'E-posta'),
            matching: find.byType(IgnorePointer),
          )
          .first,
    )
    .ignoring;

void main() {
  group('server settings', () {
    testWidgets('a test that answers after the address was edited does not '
        'verify the new one: saving it still asks', (tester) async {
      final pings = _Pings();
      await _pumpServer(tester, pings);
      await tester.enterText(_serverAddress, '192.168.1.20:3000');
      await tester.pump();
      await tester.tap(find.text('Bağlantıyı test et'));
      await tester.pump();
      await tester.enterText(_serverAddress, '192.168.1.99:3000');
      await tester.pump();
      pings.answer(0, _up);
      await tester.pumpAndSettle();
      expect(find.textContaining('Bağlandı'), findsNothing);

      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('Bağlantı doğrulanmadı'), findsOneWidget);
      expect(_prefs.getString(PrefKeys.serverUrl), 'http://meridian.test:3000');
    });

    testWidgets('of two tests, the last one sent is the one shown', (
      tester,
    ) async {
      final pings = _Pings();
      await _pumpServer(tester, pings);
      await tester.enterText(_serverAddress, 'good.example');
      await tester.pump();
      await tester.tap(find.text('Bağlantıyı test et'));
      await tester.pump();
      await tester.enterText(_serverAddress, 'bad.example');
      await tester.pump();
      await tester.tap(find.text('Bağlantıyı test et'));
      await tester.pump();
      pings.answer(1, _down);
      pings.answer(0, _up);
      await tester.pumpAndSettle();
      expect(find.textContaining('Bağlanılamadı'), findsOneWidget);
      expect(find.textContaining('Bağlandı'), findsNothing);
    });

    testWidgets('a new address says before saving that it signs this phone '
        'out, and after saving that it needs a sign-in', (tester) async {
      final pings = _Pings();
      await _pumpServer(tester, pings);
      expect(find.textContaining('oturumu kapatır'), findsNothing);
      await tester.enterText(_serverAddress, 'mac.tailnet.ts.net:3000');
      await tester.pump();
      expect(find.textContaining('oturumu kapatır'), findsOneWidget);
      await tester.tap(find.text('Bağlantıyı test et'));
      await tester.pump();
      pings.answer(0, _up);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(
        find.text('Sunucu adresi kaydedildi — yeniden giriş yap'),
        findsOneWidget,
      );
      expect(_container.read(sessionProvider), isA<SessionLoggedOut>());
    });
  });

  group('login', () {
    testWidgets('a ping that answers after the address was edited neither '
        'verifies the new one nor saves the old one', (tester) async {
      final pings = _Pings();
      await _pumpLogin(tester, pings);
      await tester.enterText(_serverAddress, 'mac.tailnet.ts.net:3000');
      await tester.pump(const Duration(milliseconds: 1600));
      expect(pings.sent, ['mac.tailnet.ts.net:3000']);
      await tester.enterText(_serverAddress, 'mac.tailnet.ts.net:3001');
      await tester.pump();
      pings.answer(0, _up);
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(_credentialsLocked(tester), isTrue);
      expect(_prefs.getString(PrefKeys.serverUrl), isNull);
      // The debounce pings the address now in the field.
      await tester.pump(const Duration(milliseconds: 1600));
      expect(pings.sent.last, 'mac.tailnet.ts.net:3001');
      pings.answer(1, _up);
      await tester.pumpAndSettle();
      expect(_credentialsLocked(tester), isFalse);
      expect(
        _prefs.getString(PrefKeys.serverUrl),
        'http://mac.tailnet.ts.net:3001',
      );
    });

    testWidgets('a failed ping can be tried again from the field', (
      tester,
    ) async {
      final pings = _Pings();
      await _pumpLogin(tester, pings, saved: 'http://mac.tailnet.ts.net:3000');
      pings.answer(0, _down);
      await tester.pumpAndSettle();
      expect(_credentialsLocked(tester), isTrue);
      await tester.tap(find.byTooltip('Tekrar dene'));
      await tester.pump();
      expect(pings.sent, hasLength(2));
      pings.answer(1, _up);
      await tester.pumpAndSettle();
      expect(_credentialsLocked(tester), isFalse);
    });

    testWidgets('a failed ping is tried again when the app comes back', (
      tester,
    ) async {
      final pings = _Pings();
      await _pumpLogin(tester, pings, saved: 'http://mac.tailnet.ts.net:3000');
      pings.answer(0, _down);
      await tester.pumpAndSettle();
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(pings.sent, hasLength(2));
      pings.answer(1, _up);
      await tester.pumpAndSettle();
      expect(_credentialsLocked(tester), isFalse);
    });
  });
}
