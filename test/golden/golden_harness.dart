/// The shared golden harness (design-analysis §8.10, §9.0 rule 5).
///
/// Every screen area has its own file, `test/golden/<area>_golden_test.dart`,
/// owned by that area's work package; this file is the common part:
///
/// * **Fixed clock.** [goldenNow] is Sunday 4 October 2026, 09:41. Fixtures
///   build their dates from it ([ymd], [daysAgo], [daysAhead]) and the app's
///   clock and "today" are pinned to it, so the images do not drift.
/// * **Matrix.** Each screen is shot per [GoldenVariant]: language × theme ×
///   text scale. [GoldenVariant.standard] is `tr-dark-1.0`, `en-dark-1.0`,
///   `tr-light-1.0`; main screens add `tr-dark-2.0`
///   ([GoldenVariant.withLargeText]).
/// * **Real fonts.** Fraunces, Inter and the Material icon font, at phone
///   size (360×780 dp, 3x).
///
/// Images land in `test/golden/images/<lang>-<theme>-<scale>/<screen>.png`.
///
/// A golden file is tagged `golden` and skipped by default (see
/// dart_test.yaml). Run it deliberately:
///
///     flutter test test/golden --run-skipped                  # compare
///     flutter test test/golden --run-skipped --update-goldens # refresh
///
/// A screen file looks like:
///
///     void main() {
///       setUpGoldens();
///       goldenScreen('habits', variants: GoldenVariant.withLargeText,
///           (tester, variant) async {
///         await tester.pumpWidget(goldenHost(const HabitsScreen(), [...]));
///         await tester.pumpAndSettle();
///       });
///     }
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/formats.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_fonts.dart';

// --- Clock -------------------------------------------------------------------

/// The moment every golden is shot at: Sunday 4 October 2026, 09:41.
final goldenNow = DateTime(2026, 10, 4, 9, 41);

/// `YYYY-MM-DD` of [d], as the API writes dates.
String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime daysAgo(int n) => goldenNow.subtract(Duration(days: n));
DateTime daysAhead(int n) => goldenNow.add(Duration(days: n));

// --- Matrix ------------------------------------------------------------------

/// One cell of the golden matrix: language × theme × text scale.
class GoldenVariant {
  const GoldenVariant(this.lang, this.brightness, this.textScale);

  final String lang;
  final Brightness brightness;
  final double textScale;

  /// `tr-dark-1.0` — also the image directory.
  String get name =>
      '$lang-${brightness == Brightness.dark ? 'dark' : 'light'}-'
      '${textScale.toStringAsFixed(1)}';

  static const trDark = GoldenVariant('tr', Brightness.dark, 1.0);
  static const enDark = GoldenVariant('en', Brightness.dark, 1.0);
  static const trLight = GoldenVariant('tr', Brightness.light, 1.0);
  static const trDarkLarge = GoldenVariant('tr', Brightness.dark, 2.0);

  /// Every screen.
  static const standard = [trDark, enDark, trLight];

  /// Main screens (§8.3): the standard set plus 200 % text.
  static const withLargeText = [trDark, enDark, trLight, trDarkLarge];

  @override
  String toString() => name;
}

/// The variant being shot — fixtures read it to translate their data.
GoldenVariant goldenVariant = GoldenVariant.trDark;

/// Fixture copy in the variant's language: [tr] itself in Turkish, its
/// entry in [en] in English (a missing one falls back to [tr]). An English
/// screenshot with Turkish account names would not show what an English
/// user sees.
String fx(String tr, Map<String, String> en) =>
    goldenVariant.lang == 'en' ? (en[tr] ?? tr) : tr;

// --- Setup -------------------------------------------------------------------

late SharedPreferences goldenPrefs;

/// Loads the real fonts and the icon font, pins the clock and gives
/// [goldenPrefs] a signed-in device's settings. Call once at the top of a
/// golden file's `main`.
void setUpGoldens() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppFonts();
    await _loadMaterialIcons();
    await initializeDateFormatting();
    setAppToday(goldenNow);
    SharedPreferences.setMockInitialValues({
      'server_url': 'http://meridian.test:3000',
      'theme_mode': 'dark',
    });
    goldenPrefs = await SharedPreferences.getInstance();
  });
  tearDownAll(() => setAppToday(null));
}

/// Shoots [screen] once per variant: sets the phone size and the active
/// [goldenVariant], runs [body] (which pumps the screen and lets it
/// settle), then compares with `images/<variant>/<screen>.png`.
void goldenScreen(
  String screen,
  Future<void> Function(WidgetTester tester, GoldenVariant variant) body, {
  List<GoldenVariant> variants = GoldenVariant.standard,
}) {
  for (final variant in variants) {
    testWidgets('$screen ${variant.name}', (tester) async {
      goldenVariant = variant;
      tester.view.physicalSize = const Size(1080, 2340); // 360×780 dp @ 3x
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await body(tester, variant);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('images/${variant.name}/$screen.png'),
      );
    });
  }
}

/// [home] in the app's theme and languages for the active [goldenVariant],
/// with the clock at [goldenNow] and [overrides] on top. A screen that reads
/// device settings adds `sharedPrefsProvider.overrideWithValue(goldenPrefs)`;
/// one that would fetch gets every read model it shows overridden.
Widget goldenHost(Widget home, List<Override> overrides) {
  final variant = goldenVariant;
  return ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(() => goldenNow),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(variant.brightness),
      locale: Locale(variant.lang),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(variant.textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

// --- Icons -------------------------------------------------------------------

/// Candidate Flutter SDK roots: FLUTTER_ROOT, else derived from the Dart
/// executable path (`root/bin/cache/dart-sdk/bin/dart`).
List<String> _flutterRoots() {
  final roots = <String>[];
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) roots.add(env);
  try {
    var dir = File(Platform.resolvedExecutable).parent; // …/dart-sdk/bin
    for (var i = 0; i < 4; i++) {
      dir = dir.parent;
    }
    roots.add(dir.path);
  } catch (_) {/* ignore */}
  return roots;
}

/// Loads the SDK's MaterialIcons font so `Icon`s render as real glyphs, not
/// boxes. Best-effort.
Future<void> _loadMaterialIcons() async {
  for (final root in _flutterRoots()) {
    final f = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (f.existsSync()) {
      final bytes = await f.readAsBytes();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      return;
    }
  }
}
