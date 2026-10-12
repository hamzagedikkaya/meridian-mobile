/// Sunucu ayarı (design-analysis §7.1, WP-14): the connection test and its
/// result line, the "save anyway" question as a sheet, and a new address
/// ending the session (its token belongs to the old server).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/profile/server_screen.dart';
import 'package:meridian_mobile/ui/widgets/server_url_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_stores.dart';

late SharedPreferences _prefs;
late MemoryTokenStore _tokens;
late ProviderContainer _container;

/// The server settings pushed over a blank page, signed in to
/// `meridian.test`; every ping answers [serverUp].
Future<void> _pump(WidgetTester tester, {required bool serverUp}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    PrefKeys.serverUrl: 'http://meridian.test:3000',
  });
  _prefs = await SharedPreferences.getInstance();
  _tokens = MemoryTokenStore(origin: 'http://meridian.test:3000');
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
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(_prefs),
        ...signedInOverrides(tokens: _tokens),
        serverPingProvider.overrideWithValue(
          (url) async => serverUp
              ? (ok: true, latencyMs: 38, version: '1.4.0')
              : (ok: false, latencyMs: null, version: null),
        ),
      ],
      child: MaterialApp.router(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
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

Finder get _address => find.widgetWithText(TextField, 'Sunucu adresi');

void main() {
  testWidgets('a test that answers: connected, the version and the round '
      'trip', (tester) async {
    await _pump(tester, serverUp: true);
    expect(find.text('Adresi nereden bulurum?'), findsOneWidget);
    await tester.tap(find.text('Bağlantıyı test et'));
    await tester.pumpAndSettle();
    expect(
      find.text('Bağlandı · Meridian v1.4.0 · 38\u00A0ms'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('saving an address that did not answer asks in a sheet; '
      '"Vazgeç" keeps the old one', (tester) async {
    await _pump(tester, serverUp: false);
    await tester.enterText(_address, '192.168.1.99:3000');
    await tester.tap(find.text('Bağlantıyı test et'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bağlanılamadı'), findsOneWidget);

    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Bağlantı doğrulanmadı'), findsOneWidget);

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ServerScreen), findsOneWidget);
    expect(_prefs.getString(PrefKeys.serverUrl), 'http://meridian.test:3000');
    expect(_container.read(sessionProvider), isA<SessionLoggedIn>());
  });

  testWidgets('"Yine de kaydet": the new address is kept and the session '
      'ends', (tester) async {
    await _pump(tester, serverUp: false);
    await tester.enterText(_address, '192.168.1.99:3000');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yine de kaydet'));
    await tester.pumpAndSettle();
    expect(_prefs.getString(PrefKeys.serverUrl), 'http://192.168.1.99:3000');
    expect(_tokens.token, isNull);
    expect(_container.read(sessionProvider), isA<SessionLoggedOut>());
    expect(find.byType(ServerScreen), findsNothing);
  });
}
