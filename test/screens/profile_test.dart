/// Profile from the phone alone (contract §2, design-research §5.7): every
/// setting a row with its value, each opening its editor; the server's
/// refusals under the field they are about; the password's new token kept;
/// and signing out everywhere.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_mobile/core/haptics.dart';
import 'package:meridian_mobile/core/locale_mode.dart';
import 'package:meridian_mobile/core/reduce_motion.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/router/app_router.dart';
import 'package:meridian_mobile/theme/app_motion.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/profile/profile_screen.dart';
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart'
    show RejectShake;

import '../support/fake_api.dart';
import '../support/fake_stores.dart';

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
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr'), Locale('en')],
      home: const ProfileScreen(),
    );

void _tallSurface(WidgetTester tester, {Size size = const Size(1500, 6600)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps until the fake API has answered and the screen has caught up —
/// without waiting on a spinner that never ends.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The Profile screen signed in as the fake API's user ("Demo", Istanbul,
/// TRY, weekly review on Sunday), with the real repository and session over
/// [api] and in-memory token and draft stores.
class _Harness {
  _Harness(this.api, this.tokens, this.drafts);

  final FakeApi api;
  final MemoryTokenStore tokens;
  final MemoryDraftStore drafts;
  late ProviderContainer container;

  SessionState get session => container.read(sessionProvider);
}

Future<_Harness> _pumpSignedIn(
  WidgetTester tester, {
  FakeApi? api,
  String? draft,
  List<Override> overrides = const [],
  Size surface = const Size(1500, 6600),
}) async {
  _tallSurface(tester, size: surface);
  final h = _Harness(
    api ?? FakeApi(),
    MemoryTokenStore(origin: 'http://meridian.test'),
    MemoryDraftStore(draft),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(_prefs),
        dioProvider.overrideWithValue(h.api.dio),
        ...signedInOverrides(tokens: h.tokens, drafts: h.drafts),
        deviceUtcOffsetProvider.overrideWithValue(const Duration(hours: 3)),
        apiHealthProvider.overrideWith(
          (ref) async => (ok: true, latencyMs: 12, version: '1.0.0'),
        ),
        ...overrides,
      ],
      retry: (_, _) => null,
      child: const _LocaleAwareApp(),
    ),
  );
  await _settle(tester);
  h.container = ProviderScope.containerOf(
    tester.element(find.byType(ProfileScreen)),
  );
  return h;
}

/// Taps the settings row titled [title] (its title, not a same-named field).
Future<void> _openRow(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await _settle(tester);
}

Finder _field(String label) => find.widgetWithText(TextField, label);

/// A 360×800 dp phone with text at 200%.
Size _largeTextPhone(WidgetTester tester) {
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  return const Size(1080, 2400);
}

/// Whether [finder]'s centre is on screen and a tap there reaches it.
void _expectTappable(WidgetTester tester, Finder finder) {
  final centre = tester.getCenter(finder);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(centre.dy, lessThan(screen.height));
  final hits = tester.hitTestOnBinding(centre).path.map((e) => e.target);
  expect(hits.whereType<RenderObject>(), contains(tester.renderObject(finder)));
}

/// No text on screen is cut short: every label and value is whole, at any
/// text size (design-analysis §4.7).
void _expectNothingCut(WidgetTester tester) {
  for (final text in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  )) {
    expect(
      text.didExceedMaxLines,
      isFalse,
      reason: '"${text.text.toPlainText()}" is cut',
    );
  }
}

/// The haptics played from now on, by their `HapticFeedbackType`.
List<String?> _recordHaptics() {
  final played = <String?>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      played.add(call.arguments as String?);
    }
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return played;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
    Haptics.debugReset(androidSdk: 34);
  });

  testWidgets('a calm settings list: every setting with its value', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    expect(tester.takeException(), isNull);

    // Header.
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('demo@meridian.local'), findsWidgets);

    // Account.
    expect(find.text('Hesap'), findsOneWidget);
    expect(find.text('Ad'), findsOneWidget);
    expect(find.text('Demo'), findsWidgets);
    expect(find.text('E-posta'), findsOneWidget);
    expect(find.text('Şifre'), findsOneWidget);
    expect(find.text('Değiştir'), findsOneWidget);
    expect(find.text('Para birimi'), findsOneWidget);
    expect(find.text('TRY · ₺'), findsOneWidget);
    expect(find.text('Saat dilimi'), findsOneWidget);
    expect(find.text('Europe/Istanbul, UTC+3'), findsOneWidget);
    expect(find.text('Haftalık değerlendirme'), findsOneWidget);
    expect(find.text('Pazar'), findsOneWidget);

    // App, server, about.
    expect(find.text('Uygulama'), findsOneWidget);
    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('Koyu'), findsOneWidget);
    expect(find.text('Dil'), findsOneWidget);
    expect(find.text('Türkçe'), findsOneWidget);
    expect(find.text('Sunucu'), findsWidgets);
    expect(find.textContaining('Bağlı\u00A0·\u00A012\u00A0ms'), findsOneWidget);

    // Signing out says it is for every device.
    expect(find.text('Çıkış yap'), findsOneWidget);
    expect(find.text('Tüm cihazlarda oturumu kapatır'), findsOneWidget);
  });

  testWidgets('each row reads as one item: its name, its value, a button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpSignedIn(tester);
    expect(
      tester.getSemantics(find.text('TRY · ₺')),
      matchesSemantics(
        label: 'Para birimi\nTRY · ₺',
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('large text on a small phone: rows grow instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
    _expectNothingCut(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    _expectNothingCut(tester);
  });

  testWidgets(
    'edge: null user (still loading) and unreachable API do not crash',
    (tester) async {
      _tallSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(_prefs),
            currentUserProvider.overrideWithValue(null),
            apiHealthProvider.overrideWith(
              (ref) async => (ok: false, latencyMs: null, version: null),
            ),
          ],
          child: _app(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Fallback name; the account rows show a placeholder and cannot be
      // edited until the server has said what they hold.
      expect(find.text('Kullanıcı'), findsOneWidget);
      expect(find.text('demo@meridian.local'), findsNothing);
      // Name, e-mail, currency, time zone and weekly review placeholders.
      expect(find.text('—'), findsNWidgets(5));
      await tester.tap(find.text('Para birimi'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

    // Screen chrome still present.
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Çıkış yap'), findsOneWidget);

    // Unreachable health → a red dot and "Ulaşılamıyor".
    expect(find.textContaining('Ulaşılamıyor'), findsOneWidget);
  });

  testWidgets('picking English re-renders the screen in English',
      (tester) async {
    _tallSurface(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(_prefs),
        currentUserProvider.overrideWithValue(_demoUser),
        apiHealthProvider.overrideWith(
          (ref) async => (ok: true, latencyMs: 12, version: '1.0.0'),
        ),
      ],
      child: const _LocaleAwareApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Profil'), findsOneWidget);

    await tester.tap(find.text('Dil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Profil'), findsNothing);
    // The choice is remembered for the next launch.
    expect(_prefs.getString(PrefKeys.locale), 'en');

    // And back again.
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Türkçe'));
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('picking a theme applies it and writes it to the account; a '
      'failure there is said, and the theme stays', (tester) async {
    final api = FakeApi()..failNetwork('PATCH /me');
    final h = await _pumpSignedIn(tester, api: api);
    await _openRow(tester, 'Tema');
    await tester.tap(find.text('Açık').last);
    await _settle(tester);
    expect(_prefs.getString(PrefKeys.themeMode), 'light');
    expect(h.api.bodiesOf('PATCH /me').single, {'theme_preference': 'light'});
    expect(
      find.text('Tema sunucuya kaydedilemedi — bu cihazda geçerli'),
      findsOneWidget,
    );
    expect(find.text('Açık'), findsOneWidget);
  });

  group('the account\'s time zone', () {
    const istanbul = User(
      id: 9,
      displayName: 'Demo User',
      initials: 'DU',
      email: 'demo@meridian.local',
      currency: 'TRY',
      subunitToUnit: 100,
      locale: 'tr',
      themePreference: 'dark',
      timezone: 'Istanbul',
      timezoneIana: 'Europe/Istanbul',
      utcOffset: Duration(hours: 3),
    );

    Future<void> pump(WidgetTester tester, Duration device) async {
      _tallSurface(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(_prefs),
          currentUserProvider.overrideWithValue(istanbul),
          deviceUtcOffsetProvider.overrideWithValue(device),
          apiHealthProvider.overrideWith(
            (ref) async => (ok: true, latencyMs: 12, version: '1.0.0'),
          ),
        ],
        child: _app(),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('is shown with its offset', (tester) async {
      await pump(tester, const Duration(hours: 3));
      expect(find.text('Saat dilimi'), findsOneWidget);
      expect(find.text('Europe/Istanbul, UTC+3'), findsOneWidget);
      expect(find.textContaining('Bu cihaz'), findsNothing);
    });

    testWidgets('says so when this phone is in another zone', (tester) async {
      await pump(tester, const Duration(hours: -4));
      expect(
        find.text('Bu cihaz UTC-04:00 kullanıyor. Günler ve saatler hesabının '
            'saat dilimine göre gösterilir.'),
        findsOneWidget,
      );
    });
  });

  group('name', () {
    testWidgets('an empty name is caught here; a new one is saved and shows '
        'at once', (tester) async {
      final h = await _pumpSignedIn(tester);
      await _openRow(tester, 'Ad');
      expect(find.text('Uygulamada ve web\'de böyle görünür.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(find.text('Boş bırakılamaz'), findsOneWidget);
      expect(h.api.bodiesOf('PATCH /me'), isEmpty);

      h.api.on('PATCH /me', {'user': userJson(name: 'Hamza Gedik')});
      await tester.enterText(find.byType(TextField), ' Hamza Gedik ');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(h.api.bodiesOf('PATCH /me').single, {'name': 'Hamza Gedik'});
      expect(find.byType(TextField), findsNothing, reason: 'the sheet closed');
      expect(find.text('Adın güncellendi'), findsOneWidget);
      expect(find.text('Hamza Gedik'), findsWidgets);
    });

    testWidgets('tapping the header edits the name too', (tester) async {
      await _pumpSignedIn(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await _settle(tester);
      expect(find.widgetWithText(TextField, 'Demo'), findsOneWidget);
    });

    testWidgets('the server\'s refusal shows under the field', (tester) async {
      final api = FakeApi()
        ..on('PATCH /me', {
          'errors': {
            'name': ['Ad çok uzun'],
          },
          'code': 'validation_failed',
          'details': {
            'name': [
              {'error': 'too_long', 'count': 80},
            ],
          },
        }, status: 422);
      await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'Ad');
      await tester.enterText(find.byType(TextField), 'Uzun bir ad');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(find.text('En fazla 80 karakter olabilir'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget, reason: 'still open');
    });

    testWidgets('no answer: "couldn\'t save", and the text is kept', (
      tester,
    ) async {
      final api = FakeApi()..failNetwork('PATCH /me');
      await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'Ad');
      await tester.enterText(find.byType(TextField), 'Yeni Ad');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(find.text('Kaydedilemedi · Tekrar dene'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Yeni Ad'), findsOneWidget);
    });
  });

  group('e-mail', () {
    testWidgets('needs the current password, which is asked for here first', (
      tester,
    ) async {
      final h = await _pumpSignedIn(tester);
      await _openRow(tester, 'E-posta');
      expect(
        find.text(
          'E-posta giriş adın olduğu için değiştirmek mevcut şifreni ister.',
        ),
        findsOneWidget,
      );
      await tester.enterText(_field('Yeni e-posta'), 'yeni@example.com');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(find.text('Mevcut şifreni gir'), findsOneWidget);
      expect(h.api.bodiesOf('PATCH /me'), isEmpty);
    });

    testWidgets('a wrong current password and an address in use show under '
        'their fields', (tester) async {
      final api = FakeApi()
        ..on('PATCH /me', {
          'errors': {
            'email': ['E-posta zaten kullanılıyor'],
            'current_password': ['Mevcut şifre geçersiz'],
          },
          'code': 'invalid_current_password',
          'details': {
            'email': [
              {'error': 'taken', 'value': 'taken@example.com'},
            ],
            'current_password': [
              {'error': 'invalid'},
            ],
          },
        }, status: 422);
      final h = await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'E-posta');
      await tester.enterText(_field('Yeni e-posta'), 'taken@example.com');
      await tester.enterText(_field('Mevcut şifre'), 'yanlis');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(h.api.bodiesOf('PATCH /me').single, {
        'email': 'taken@example.com',
        'current_password': 'yanlis',
      });
      expect(find.text('Mevcut şifre yanlış'), findsOneWidget);
      expect(find.text('Bu zaten kullanılıyor'), findsOneWidget);
      // The password is kept, selected, for the user to fix.
      final password = tester.widget<TextField>(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(TextField),
            )
            .last,
      );
      expect(password.controller!.text, 'yanlis');
    });

    testWidgets('"done" on the keyboard while it is being saved spends no '
        'second password attempt', (tester) async {
      final api = FakeApi()..hold('PATCH /me');
      await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'E-posta');
      await tester.enterText(_field('Yeni e-posta'), 'yeni@example.com');
      await tester.enterText(_field('Mevcut şifre'), 'eski');
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      // The password field still has the focus.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      api.release('PATCH /me');
      await _settle(tester);
      expect(api.bodiesOf('PATCH /me'), hasLength(1));
    });

    testWidgets('the password-check limit (429) is said above the button', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('PATCH /me', {
          'error': 'too_many_requests',
          'code': 'too_many_requests',
        }, status: 429);
      await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'E-posta');
      await tester.enterText(_field('Yeni e-posta'), 'yeni@example.com');
      await tester.enterText(_field('Mevcut şifre'), 'eski');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(
        find.text(
          'Çok fazla şifre denemesi. Birkaç dakika bekleyip tekrar dene.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('saved: the new address shows', (tester) async {
      final api = FakeApi()
        ..on('PATCH /me', {
          'user': {...userJson(), 'email': 'yeni@example.com'},
        });
      await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'E-posta');
      await tester.enterText(_field('Yeni e-posta'), 'Yeni@Example.com');
      await tester.enterText(_field('Mevcut şifre'), 'eski');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(find.text('E-posta adresin güncellendi'), findsOneWidget);
      expect(find.text('yeni@example.com'), findsWidgets);
    });
  });

  group('password', () {
    Future<void> fill(
      WidgetTester tester, {
      String current = 'eski-sifre',
      String password = 'yeni-sifre-1',
      String? confirmation,
    }) async {
      await tester.enterText(_field('Mevcut şifre'), current);
      await tester.enterText(_field('Yeni şifre'), password);
      await tester.enterText(
        _field('Yeni şifre (tekrar)'),
        confirmation ?? password,
      );
      await tester.tap(find.text('Şifreyi değiştir').last);
      await _settle(tester);
    }

    testWidgets('a mismatch or a short one is caught here', (tester) async {
      final h = await _pumpSignedIn(tester);
      await _openRow(tester, 'Şifre');
      await fill(tester, password: 'abc', confirmation: 'abd');
      expect(find.text('En az 6 karakter olmalı'), findsOneWidget);
      expect(find.text('Yeni şifreyle eşleşmiyor'), findsOneWidget);
      expect(h.api.bodiesOf('PATCH /me/password'), isEmpty);
    });

    testWidgets('saved: the new token is kept, so this phone stays signed in', (
      tester,
    ) async {
      final h = await _pumpSignedIn(tester);
      await _openRow(tester, 'Şifre');
      expect(
        find.text(
          'Şifre değişince diğer tüm cihazlarda oturum kapanır; '
          'bu telefonda açık kalır.',
        ),
        findsOneWidget,
      );
      await fill(tester);
      expect(h.api.bodiesOf('PATCH /me/password').single, {
        'current_password': 'eski-sifre',
        'password': 'yeni-sifre-1',
        'password_confirmation': 'yeni-sifre-1',
      });
      expect(h.tokens.token, 'new-token');
      expect(h.session, isA<SessionLoggedIn>());
      expect(
        find.text(
          'Şifren değişti. Diğer cihazlarda yeniden giriş yapman '
          'gerekecek.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a wrong current password shows under it, and the token '
        'stays', (tester) async {
      final api = FakeApi()
        ..on('PATCH /me/password', {
          'errors': {
            'current_password': ['Mevcut şifre geçersiz'],
          },
          'code': 'invalid_current_password',
          'details': {
            'current_password': [
              {'error': 'invalid'},
            ],
          },
        }, status: 422);
      final h = await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'Şifre');
      await fill(tester);
      expect(find.text('Mevcut şifre yanlış'), findsOneWidget);
      expect(h.tokens.token, 'old-token');
      // Kept, selected, to be fixed or typed over — never cleared.
      final current = tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('current_password')),
              matching: find.byType(TextField),
            ),
          )
          .controller!;
      expect(current.text, 'eski-sifre');
      expect(
        current.selection,
        const TextSelection(baseOffset: 0, extentOffset: 10),
      );
    });

    testWidgets('the keyboard\'s done key while it is being saved sends '
        'nothing more, and this phone stays signed in', (tester) async {
      final api = FakeApi()..hold('PATCH /me/password');
      final h = await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'Şifre');
      await tester.enterText(_field('Mevcut şifre'), 'eski-sifre');
      await tester.enterText(_field('Yeni şifre'), 'yeni-sifre-1');
      await tester.enterText(_field('Yeni şifre (tekrar)'), 'yeni-sifre-1');
      await tester.tap(find.text('Şifreyi değiştir').last);
      await tester.pump();
      // The confirmation still has the focus: "done" on its keyboard.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      api.release('PATCH /me/password');
      await _settle(tester);
      expect(api.bodiesOf('PATCH /me/password'), hasLength(1));
      expect(h.tokens.token, 'new-token');
      expect(h.session, isA<SessionLoggedIn>());
    });

    testWidgets('the server\'s own rules show under the new password', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('PATCH /me/password', {
          'errors': {
            'password': ['Şifre çok uzun'],
          },
          'code': 'validation_failed',
          'details': {
            'password': [
              {'error': 'too_long', 'count': 128},
            ],
          },
        }, status: 422);
      await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'Şifre');
      await fill(tester);
      expect(find.text('En fazla 128 karakter olabilir'), findsOneWidget);
    });

    testWidgets('the rate limit (429) is said, nothing changes', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('PATCH /me/password', {
          'error': 'too_many_requests',
          'code': 'too_many_requests',
        }, status: 429);
      final h = await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'Şifre');
      await fill(tester);
      expect(
        find.text(
          'Çok fazla şifre denemesi. Birkaç dakika bekleyip tekrar dene.',
        ),
        findsOneWidget,
      );
      expect(h.tokens.token, 'old-token');
    });
  });

  group('currency', () {
    testWidgets('picked from the server\'s list, after saying nothing is '
        'converted', (tester) async {
      // The server has the new currency from then on: GET /me, which a
      // currency change re-reads, says so too.
      final usd = {
        'user': {...userJson(), 'currency': 'USD'},
      };
      final api = FakeApi()
        ..on('PATCH /me', usd)
        ..on('GET /me', usd);
      final h = await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'Para birimi');
      expect(find.text('Mevcut tutarlar dönüştürülmez.'), findsOneWidget);
      expect(find.text('Türk lirası (TRY)'), findsOneWidget);

      await tester.tap(find.text('ABD doları (USD)'));
      await _settle(tester);
      expect(find.text('USD kullanılsın mı?'), findsOneWidget);
      expect(
        find.textContaining('₺5.000,00, \$5.000,00 olur'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Değiştir'));
      await _settle(tester);

      expect(h.api.bodiesOf('PATCH /me').single, {'currency': 'USD'});
      expect(find.text('USD · \$'), findsOneWidget);
      expect(find.text('Para birimi: USD'), findsOneWidget);
    });

    testWidgets('cancelled: nothing is sent', (tester) async {
      final h = await _pumpSignedIn(tester);
      await _openRow(tester, 'Para birimi');
      await tester.tap(find.text('Gram altın (GAU)'));
      await _settle(tester);
      expect(find.textContaining('500.000\u00A0gr'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await _settle(tester);
      expect(h.api.bodiesOf('PATCH /me'), isEmpty);
    });

    testWidgets('the options cannot be loaded: said, with a retry', (
      tester,
    ) async {
      final api = FakeApi()..fail('GET /me/options', 500);
      await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'Para birimi');
      expect(find.text('Seçenekler yüklenemedi'), findsOneWidget);
      api.on('GET /me/options', meOptionsJson());
      await tester.tap(find.text('Tekrar dene'));
      await _settle(tester);
      expect(find.text('ABD doları (USD)'), findsOneWidget);
    });
  });

  group('time zone', () {
    testWidgets('the zones that read like this phone come first; search '
        'finds the rest', (tester) async {
      final tokyo = {
        'user': {
          ...userJson(),
          'timezone': 'Tokyo',
          'timezone_iana': 'Asia/Tokyo',
          'utc_offset': '+09:00',
        },
      };
      final api = FakeApi()
        ..on('PATCH /me', tokyo)
        ..on('GET /me', tokyo);
      final h = await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'Saat dilimi');
      expect(find.text('Bu cihazın saati (UTC+03:00)'), findsOneWidget);
      expect(find.text('Tüm saat dilimleri'), findsOneWidget);
      // Istanbul is the account's: checked, in both groups.
      expect(find.text('Istanbul'), findsNWidgets(2));
      expect(find.byIcon(Icons.check), findsNWidgets(2));

      await tester.enterText(find.byType(TextField), 'tok');
      await _settle(tester);
      expect(find.text('Istanbul'), findsNothing);
      await tester.tap(find.text('Tokyo'));
      await _settle(tester);

      expect(h.api.bodiesOf('PATCH /me').single, {'timezone': 'Tokyo'});
      expect(find.text('Asia/Tokyo, UTC+9'), findsOneWidget);
      // Every screen and the account itself are read again.
      expect(h.api.gets, containsAll(['/me', '/me/options']));
      // The phone (UTC+03:00) is now in another zone than the account.
      expect(
        find.textContaining('Bu cihaz UTC+03:00 kullanıyor'),
        findsOneWidget,
      );
    });

    testWidgets('large text on a small phone with the keyboard up: the '
        'picker scrolls instead of overflowing', (tester) async {
      _largeTextPhone(tester);
      await _pumpSignedIn(tester, surface: const Size(1080, 1920));
      await tester.ensureVisible(find.text('Saat dilimi'));
      await _settle(tester);
      await _openRow(tester, 'Saat dilimi');
      expect(find.byType(BottomSheet), findsOneWidget);
      // Typing in the search brings the keyboard up.
      await tester.enterText(find.byType(TextField), 'UTC+09');
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      // The zones scroll under the search field, which stays on screen.
      await tester.drag(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(CustomScrollView),
        ),
        const Offset(0, -300),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      _expectTappable(tester, find.byType(TextField));
      _expectTappable(tester, find.widgetWithText(ListTile, 'Tokyo'));
    });

    testWidgets('a search that finds nothing says so', (tester) async {
      await _pumpSignedIn(tester);
      await _openRow(tester, 'Saat dilimi');
      await tester.enterText(find.byType(TextField), 'atlantis');
      await _settle(tester);
      expect(find.text('Eşleşen saat dilimi yok'), findsOneWidget);
    });

    testWidgets('a refusal is said in the picker, which stays open', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('PATCH /me', {
          'errors': {
            'timezone': ['Saat dilimi geçerli bir seçenek değil'],
          },
          'code': 'validation_failed',
          'details': {
            'timezone': [
              {'error': 'inclusion', 'value': 'Tokyo'},
            ],
          },
        }, status: 422);
      await _pumpSignedIn(tester, api: api);
      await _openRow(tester, 'Saat dilimi');
      await tester.tap(find.text('Tokyo'));
      await _settle(tester);
      expect(find.text('Geçerli bir seçenek değil'), findsOneWidget);
      expect(find.text('Tüm saat dilimleri'), findsOneWidget);
    });
  });

  testWidgets('weekly review day: Monday first, saved as its number', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('PATCH /me', {
        'user': {...userJson(), 'weekly_review_day': 1},
      });
    final h = await _pumpSignedIn(tester, api: api);
    await _openRow(tester, 'Haftalık değerlendirme');
    final days = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .toList();
    expect(days.first, 'Pazartesi');
    expect(days.last, 'Pazar');
    await tester.tap(find.text('Pazartesi'));
    await _settle(tester);
    expect(h.api.bodiesOf('PATCH /me').single, {'weekly_review_day': 1});
    expect(find.text('Haftalık değerlendirme günü: Pazartesi'), findsOneWidget);
  });

  group('signing out', () {
    testWidgets('the sheet says every device is signed out; confirming '
        'revokes the token on the server and wipes this phone', (tester) async {
      final h = await _pumpSignedIn(tester);
      await tester.tap(find.text('Çıkış yap'));
      await _settle(tester);
      expect(find.text('Çıkış yapılsın mı?'), findsOneWidget);
      expect(
        find.textContaining('sunucudaki oturumun iptal edilir'),
        findsOneWidget,
      );
      expect(find.textContaining('günlük taslağın'), findsNothing);

      // Signing out is a routine end, not a success: no haptic (§5.8).
      final played = _recordHaptics();
      await tester.tap(find.widgetWithText(FilledButton, 'Çıkış yap'));
      await _settle(tester);
      expect(played, isEmpty);
      expect(h.api.requests, contains('DELETE /session'));
      expect(
        h.session,
        isA<SessionLoggedOut>().having(
          (s) => s.revokeFailed,
          'revokeFailed',
          isFalse,
        ),
      );
      expect(h.tokens.token, isNull);
    });

    testWidgets('an unsaved journal draft is warned about', (tester) async {
      await _pumpSignedIn(
        tester,
        draft: jsonEncode({'title': '', 'body': 'Yarım kalan yazı'}),
      );
      await tester.tap(find.text('Çıkış yap'));
      await _settle(tester);
      expect(
        find.text('Kaydedilmemiş günlük taslağın da silinir.'),
        findsOneWidget,
      );
    });

    for (final draft in [
      null,
      jsonEncode({'title': '', 'body': 'Yarım'}),
    ]) {
      testWidgets(
        'large text on a small phone${draft == null ? '' : ', with '
                  'a draft'}: both buttons stay on screen',
        (tester) async {
          final h = await _pumpSignedIn(
            tester,
            draft: draft,
            surface: _largeTextPhone(tester),
          );
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.text('Çıkış yap'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          // At 2.0x the row stacks (icon line, then the title): bring the
          // whole row clear of the navigation bar before tapping it.
          await tester.ensureVisible(find.text('Çıkış yap'));
          await _settle(tester);
          await tester.tap(find.text('Çıkış yap'));
          await _settle(tester);
          expect(tester.takeException(), isNull);
          if (draft != null) {
            expect(find.textContaining('günlük taslağın'), findsOneWidget);
          }
          final signOut = find.widgetWithText(FilledButton, 'Çıkış yap');
          _expectTappable(tester, signOut);
          _expectTappable(tester, find.widgetWithText(TextButton, 'Vazgeç'));
          await tester.tap(signOut);
          await _settle(tester);
          expect(h.api.requests, contains('DELETE /session'));
        },
      );
    }

    testWidgets('cancel keeps the session', (tester) async {
      final h = await _pumpSignedIn(tester);
      await tester.tap(find.text('Çıkış yap'));
      await _settle(tester);
      await tester.tap(find.text('Vazgeç'));
      await _settle(tester);
      expect(h.api.requests, isNot(contains('DELETE /session')));
      expect(h.session, isA<SessionLoggedIn>());
    });

    testWidgets('the server cannot be reached: signed out here anyway, and '
        'the state says the session was not ended there', (tester) async {
      final api = FakeApi()..failNetwork('DELETE /session');
      final h = await _pumpSignedIn(tester, api: api);
      await tester.tap(find.text('Çıkış yap'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Çıkış yap'));
      await _settle(tester);
      expect(
        h.session,
        isA<SessionLoggedOut>().having(
          (s) => s.revokeFailed,
          'revokeFailed',
          isTrue,
        ),
      );
      expect(h.tokens.token, isNull);
    });
  });

  testWidgets('the server in one row: the address, a dot and the round '
      'trip', (tester) async {
    await _prefs.setString(PrefKeys.serverUrl, 'http://192.168.1.24:3000');
    await _pumpSignedIn(tester);
    final row = find.textContaining('192.168.1.24:3000');
    expect(
      tester.widget<Text>(row).textSpan!.toPlainText(),
      '192.168.1.24:3000 · \uFFFCBağlı\u00A0·\u00A012\u00A0ms',
    );
    expect(find.text('API durumu'), findsNothing);
  });

  group('"Hareketi azalt"', () {
    testWidgets('a switch that applies at once and stays on this device', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpSignedIn(tester);
      final context = tester.element(find.byType(ProfileScreen));
      expect(Motion.reduced(context), isFalse);
      expect(
        tester.getSemantics(find.text('Hareketi azalt')),
        matchesSemantics(
          label: 'Hareketi azalt\nGeçişler ve sayılar anında değişir',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasToggledState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: false,
        ),
      );

      await tester.tap(find.text('Hareketi azalt'));
      await tester.pump();
      expect(_prefs.getString(PrefKeys.reduceMotion), 'true');
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      // The app folds it into the one signal every animation reads.
      expect(
        Motion.reduced(tester.element(find.byType(ProfileScreen))),
        isTrue,
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(_prefs.getString(PrefKeys.reduceMotion), 'false');
      expect(
        Motion.reduced(tester.element(find.byType(ProfileScreen))),
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('on: an editor sheet opens and closes in one frame', (
      tester,
    ) async {
      _prefs.setString(PrefKeys.reduceMotion, 'true');
      await _pumpSignedIn(tester);
      await tester.tap(find.text('Ad'));
      await tester.pump();
      expect(find.byType(BottomSheet), findsOneWidget);
      final opened = tester.getRect(find.byType(BottomSheet));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(find.byType(BottomSheet)), opened,
          reason: 'already in place on the first frame');
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  testWidgets('a wrong current password shakes the field', (tester) async {
    final api = FakeApi()
      ..on('PATCH /me/password', {
        'errors': {
          'current_password': ['Mevcut şifre geçersiz'],
        },
        'code': 'invalid_current_password',
        'details': {
          'current_password': [
            {'error': 'invalid'},
          ],
        },
      }, status: 422);
    await _pumpSignedIn(tester, api: api);
    await _openRow(tester, 'Şifre');
    final shake = find.ancestor(
      of: _field('Mevcut şifre'),
      matching: find.byType(RejectShake),
    );
    expect(tester.widget<RejectShake>(shake).trigger, 0);
    await tester.enterText(_field('Mevcut şifre'), 'yanlis');
    await tester.enterText(_field('Yeni şifre'), 'yeni-sifre');
    await tester.enterText(_field('Yeni şifre (tekrar)'), 'yeni-sifre');
    final played = _recordHaptics();
    await tester.tap(find.text('Şifreyi değiştir').last);
    for (var i = 0;
        i < 20 && tester.widget<RejectShake>(shake).trigger == 0;
        i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(tester.widget<RejectShake>(shake).trigger, 1);
    // ...and REJECT, once (§5.8).
    expect(played, ['HapticFeedbackType.errorNotification']);
    await tester.pump(const Duration(milliseconds: 50));
    final moved = tester
        .widgetList<Transform>(
          find.descendant(of: shake, matching: find.byType(Transform)),
        )
        .first
        .transform
        .getTranslation()
        .x;
    expect(moved, isNot(0));
    await _settle(tester);
    expect(find.text('Mevcut şifre yanlış'), findsOneWidget);
  });

  group('the Data section', () {
    /// The app as it runs, signed in over [FakeApi], on Profile.
    Future<GoRouter> pumpApp(WidgetTester tester) async {
      _tallSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(_prefs),
            dioProvider.overrideWithValue(api.dio),
            ...signedInOverrides(
              tokens: MemoryTokenStore(origin: 'http://meridian.test'),
            ),
            apiHealthProvider.overrideWith(
              (ref) async => (ok: true, latencyMs: 12, version: '1.0.0'),
            ),
          ],
          retry: (_, _) => null,
          child: const MeridianApp(),
        ),
      );
      await _settle(tester);
      final router = ProviderScope.containerOf(
        tester.element(find.byType(MeridianApp)),
      ).read(routerProvider);
      router.push('/profile');
      await _settle(tester);
      return router;
    }

    String location(GoRouter router) => router.state.uri.toString();

    testWidgets('every management page, one row away; back comes to '
        'Profile, then Today', (tester) async {
      final router = await pumpApp(tester);
      expect(find.text('Veri'), findsOneWidget);
      for (final (row, path) in [
        ('Hesaplar', '/finance/accounts'),
        ('Kategoriler', '/finance/categories'),
        ('Abonelikler', '/finance/subscriptions'),
        ('Görev listeleri', '/agenda/lists'),
        ('Arşivlenmiş alışkanlıklar', '/habits/archived'),
        ('Hedefler', '/goals'),
      ]) {
        await tester.tap(find.text(row));
        await _settle(tester);
        expect(location(router), path, reason: row);
        expect(find.byType(ProfileScreen).hitTestable(), findsNothing);
        await tester.binding.handlePopRoute();
        await _settle(tester);
        expect(location(router), '/profile', reason: 'back from $row');
      }
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(location(router), '/today');
    });

    testWidgets('the server row opens the server settings', (tester) async {
      final router = await pumpApp(tester);
      await tester.tap(find.text('Sunucu adresi'));
      await _settle(tester);
      expect(location(router), '/profile/server');
    });
  });

  testWidgets('pull to refresh re-reads the account', (tester) async {
    final h = await _pumpSignedIn(tester);
    h.api.on('GET /me', {'user': userJson(name: 'Webden')});
    await tester.fling(find.byType(ListView), const Offset(0, 800), 1000);
    await tester.pumpAndSettle();
    expect(h.api.gets, contains('/me'));
    expect(find.text('Webden'), findsWidgets);
  });
}

/// Minimal stand-in for MeridianApp: the locale comes from the provider.
class _LocaleAwareApp extends ConsumerWidget {
  const _LocaleAwareApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      theme: buildTheme(Brightness.dark),
      locale: ref.watch(localeProvider),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      // As MeridianApp does: the app's "Reduce motion" switch joins the
      // system's flag.
      builder: (context, child) => MotionPreference(
        reduce: ref.watch(reduceMotionProvider),
        child: child!,
      ),
      home: const ProfileScreen(),
    );
  }
}
