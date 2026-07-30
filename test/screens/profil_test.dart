import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/profil/profil_screen.dart';

// Fixture shaped like GET /me → user (api-samples.json).
final _demoUser = User(
  id: 9,
  displayName: 'Demo User',
  initials: 'DU',
  email: 'demo@meridian.local',
  currency: 'TRY',
  subunitToUnit: 100,
  locale: 'tr',
  themePreference: 'dark',
);

late SharedPreferences _prefs;

MaterialApp _app() => MaterialApp(
      theme: buildTheme(Brightness.dark),
      locale: const Locale('tr'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr'), Locale('en')],
      home: const ProfilScreen(),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('renders with a logged-in user and an online API', (tester) async {
    // Tall surface so the lazy ListView builds every row (incl. bottom "Çıkış Yap").
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(_prefs),
        currentUserProvider.overrideWithValue(_demoUser),
        apiHealthProvider.overrideWith(
          (ref) async => (ok: true, latencyMs: 12, version: '1.0.0'),
        ),
      ],
      child: _app(),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Header + section scaffolding.
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Demo User'), findsOneWidget);
    expect(find.text('demo@meridian.local'), findsOneWidget);
    expect(find.text('DU'), findsOneWidget); // initials avatar

    // Grouped settings sections (Turkish strings from design §4.8).
    expect(find.text('Uygulama'), findsOneWidget);
    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('Koyu'), findsOneWidget);
    expect(find.text('Para birimi'), findsOneWidget);
    expect(find.text('Sunucu'), findsWidgets);
    expect(find.text('Çıkış Yap'), findsOneWidget);

    // Online health → green "Çevrimiçi", no spinner.
    expect(find.text('Çevrimiçi'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('edge: null user (still loading) and unreachable API do not crash',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(_prefs),
        currentUserProvider.overrideWithValue(null),
        apiHealthProvider.overrideWith(
          (ref) async => (ok: false, latencyMs: null, version: null),
        ),
      ],
      child: _app(),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Fallback name + placeholder currency, no email row.
    expect(find.text('Kullanıcı'), findsOneWidget);
    expect(find.text('demo@meridian.local'), findsNothing);
    expect(find.text('—'), findsOneWidget); // currency placeholder

    // Screen chrome still present.
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Çıkış Yap'), findsOneWidget);

    // Unreachable health → red "Ulaşılamıyor".
    expect(find.text('Ulaşılamıyor'), findsOneWidget);
  });
}
