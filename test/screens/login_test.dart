/// Giriş (design-analysis §7.1, WP-14): the address field and its help,
/// the credentials that wait for the server, the checks made before
/// anything is sent, and how a refusal is said.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/core/haptics.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/login_screen.dart';
import 'package:meridian_mobile/ui/widgets/server_url_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_fonts.dart';

/// Signed out; records each sign-in and answers it with [refusal], if any.
class _Session extends SessionController {
  _Session(this.refusal);

  final ApiException? refusal;
  final logins = <(String, String)>[];

  @override
  SessionState build() => const SessionLoggedOut();

  @override
  Future<void> login(String email, String password) async {
    logins.add((email, password));
    final refusal = this.refusal;
    if (refusal != null) throw refusal;
    state = const SessionLoggedIn();
  }
}

late _Session _session;

/// The login screen; [saved] is the address stored on this phone (none on a
/// fresh install), and every ping answers [serverUp] — or [ping], when
/// given.
Future<void> _pump(
  WidgetTester tester, {
  String? saved = 'http://meridian.test:3000',
  bool serverUp = true,
  Future<HealthResult> Function(String url)? ping,
  ApiException? refusal,
  double textScale = 1.0,
  Locale locale = const Locale('tr'),
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({PrefKeys.serverUrl: ?saved});
  final prefs = await SharedPreferences.getInstance();
  _session = _Session(refusal);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sessionProvider.overrideWith(() => _session),
      serverPingProvider.overrideWithValue(
        ping ??
            (url) async => serverUp
                ? (ok: true, latencyMs: 12, version: '1.0.0')
                : (ok: false, latencyMs: null, version: null),
      ),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      locale: locale,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const LoginScreen(),
    ),
  ));
  if (settle) await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextField, label);

/// Whether the e-mail and password are out of reach (the server has not
/// answered).
bool _credentialsLocked(WidgetTester tester) => tester
    .widget<IgnorePointer>(find
        .ancestor(of: _field('E-posta'), matching: find.byType(IgnorePointer))
        .first)
    .ignoring;

/// No text on screen is cut short — measured with the app's own fonts.
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

const _reject = 'HapticFeedbackType.errorNotification';
const _confirm = 'HapticFeedbackType.successNotification';

void main() {
  // Measured as on a phone: the test font's full-em glyphs would hide a
  // line that is cut there (and cut one that fits).
  setUpAll(loadAppFonts);
  setUp(() => Haptics.debugReset(androidSdk: 34));

  testWidgets('a fresh install: the address is empty — never the '
      'emulator\'s 10.0.2.2 — and the credentials wait for it', (tester) async {
    await _pump(tester, saved: null);
    final address = tester.widget<TextField>(_field('Sunucu adresi'));
    expect(address.controller!.text, isEmpty);
    expect(find.textContaining('10.0.2.2'), findsNothing);
    expect(
      find.text('http://192.168.1.20:3000 ya da http://mac.tailnet.ts.net:3000'),
      findsOneWidget,
    );
    expect(_credentialsLocked(tester), isTrue);

    // The address answers: it folds into one row, the credentials come up.
    await tester.enterText(_field('Sunucu adresi'), '192.168.1.24:3000');
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.24:3000'), findsOneWidget);
    expect(find.text('Değiştir'), findsOneWidget);
    expect(_credentialsLocked(tester), isFalse);

    // "Değiştir" opens the field again.
    await tester.tap(find.text('Değiştir'));
    await tester.pumpAndSettle();
    expect(_field('Sunucu adresi'), findsOneWidget);
  });

  testWidgets('an address that does not answer says to check Wi-Fi or '
      'Tailscale', (tester) async {
    await _pump(tester, serverUp: false);
    expect(
      find.textContaining('Wi-Fi veya Tailscale bağlantını kontrol et'),
      findsOneWidget,
    );
    expect(_credentialsLocked(tester), isTrue);
  });

  testWidgets('"Adresi nereden bulurum?" opens three short steps',
      (tester) async {
    await _pump(tester, serverUp: false);
    await tester.tap(find.text('Adresi nereden bulurum?'));
    await tester.pumpAndSettle();
    expect(find.text('Sunucu adresini bul'), findsOneWidget);
    expect(find.text('Aynı ağdaysan: yerel IP'), findsOneWidget);
    expect(find.text('Başka yerdeysen: Tailscale adı'), findsOneWidget);
    expect(find.text('Sonuna port: 3000'), findsOneWidget);
    expect(find.textContaining('MagicDNS'), findsOneWidget);
    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();
    expect(find.text('Sunucu adresini bul'), findsNothing);
  });

  testWidgets('empty fields are said before anything is sent',
      (tester) async {
    await _pump(tester);
    expect(_credentialsLocked(tester), isFalse);
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(find.text('E-posta gir'), findsOneWidget);
    expect(find.text('Şifre gir'), findsOneWidget);
    expect(_session.logins, isEmpty);

    // Typing clears the line for that field only.
    await tester.enterText(_field('E-posta'), 'demo@meridian.local');
    await tester.pumpAndSettle();
    expect(find.text('E-posta gir'), findsNothing);
    expect(find.text('Şifre gir'), findsOneWidget);
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(_session.logins, isEmpty);

    await tester.enterText(_field('Şifre'), 'gizli-sifre');
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(_session.logins, [('demo@meridian.local', 'gizli-sifre')]);
  });

  for (final (name, refusal, said) in [
    (
      'a wrong password',
      ApiException(ApiErrorKind.invalidCredentials, status: 401),
      'E-posta veya şifre hatalı',
    ),
    (
      'too many tries (429)',
      ApiException(ApiErrorKind.rateLimited, status: 429),
      'Çok fazla deneme — biraz bekleyip tekrar dene',
    ),
  ]) {
    testWidgets('$name is said above the button', (tester) async {
      await _pump(tester, refusal: refusal);
      await tester.enterText(_field('E-posta'), 'demo@meridian.local');
      await tester.enterText(_field('Şifre'), 'yanlis');
      await tester.tap(find.text('Giriş yap'));
      await tester.pumpAndSettle();
      expect(find.text(said), findsOneWidget);
      final line = tester.getRect(find.text(said));
      final button = tester.getRect(find.text('Giriş yap'));
      expect(line.bottom, lessThan(button.top));

      // Typing again takes it away.
      await tester.enterText(_field('Şifre'), 'yeniden');
      await tester.pumpAndSettle();
      expect(find.text(said), findsNothing);
    });
  }

  testWidgets('large text: nothing overflows', (tester) async {
    await _pump(tester, saved: null, textScale: 2.0);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Adresi nereden bulurum?'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('every word is read whole, with the app\'s fonts on a 360 dp phone',
      () {
    for (final (locale, unreachable) in const [
      (Locale('en'), 'your Wi-Fi or Tailscale connection'),
      (Locale('tr'), 'Wi-Fi veya Tailscale bağlantını kontrol et'),
    ]) {
      for (final scale in const [1.0, 1.3, 1.5, 2.0]) {
        final name = '${locale.languageCode} at ${scale}x';

        testWidgets('$name: the Wi-Fi / Tailscale advice when the server '
            'does not answer', (tester) async {
          await _pump(tester,
              serverUp: false, locale: locale, textScale: scale);
          expect(tester.takeException(), isNull);
          expect(find.textContaining(unreachable), findsOneWidget);
          _expectNothingCut(tester);
        });

        testWidgets('$name: both address examples in the empty field',
            (tester) async {
          await _pump(tester, saved: null, locale: locale, textScale: scale);
          expect(tester.takeException(), isNull);
          expect(find.textContaining('mac.tailnet.ts.net:3000'),
              findsOneWidget);
          _expectNothingCut(tester);
        });
      }
    }
  });

  testWidgets('the address field keeps its height as it is typed in, so '
      'nothing under it moves', (tester) async {
    await _pump(tester, saved: null);
    final field = _field('Sunucu adresi');
    final empty = tester.getSize(field).height;
    final help = tester.getTopLeft(find.text('Adresi nereden bulurum?')).dy;
    await tester.enterText(field, '1');
    await tester.pump();
    expect(tester.getSize(field).height, empty);
    expect(tester.getTopLeft(find.text('Adresi nereden bulurum?')).dy, help);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('a saved address is pinged first: the credentials wait for '
      'its answer', (tester) async {
    final answer = Completer<HealthResult>();
    await _pump(tester, ping: (_) => answer.future, settle: false);
    await tester.pump();
    expect(_credentialsLocked(tester), isTrue);
    answer.complete((ok: true, latencyMs: 12, version: '1.0.0'));
    await tester.pumpAndSettle();
    expect(_credentialsLocked(tester), isFalse);
  });

  group('haptics (§5.8)', () {
    testWidgets('empty fields: REJECT, and nothing is sent', (tester) async {
      await _pump(tester);
      final played = _recordHaptics();
      await tester.tap(find.text('Giriş yap'));
      await tester.pumpAndSettle();
      expect(played, [_reject]);
      expect(_session.logins, isEmpty);
    });

    for (final (name, refusal) in [
      (
        'a wrong password (401)',
        ApiException(ApiErrorKind.invalidCredentials, status: 401),
      ),
      (
        'too many tries (429)',
        ApiException(ApiErrorKind.rateLimited, status: 429),
      ),
    ]) {
      testWidgets('$name: REJECT', (tester) async {
        await _pump(tester, refusal: refusal);
        await tester.enterText(_field('E-posta'), 'demo@meridian.local');
        await tester.enterText(_field('Şifre'), 'yanlis');
        final played = _recordHaptics();
        await tester.tap(find.text('Giriş yap'));
        await tester.pumpAndSettle();
        expect(played, [_reject]);
      });
    }

    testWidgets('signed in: CONFIRM', (tester) async {
      await _pump(tester);
      await tester.enterText(_field('E-posta'), 'demo@meridian.local');
      await tester.enterText(_field('Şifre'), 'gizli-sifre');
      final played = _recordHaptics();
      await tester.tap(find.text('Giriş yap'));
      await tester.pumpAndSettle();
      expect(_session.logins, hasLength(1));
      expect(played, [_confirm]);
    });
  });
}
