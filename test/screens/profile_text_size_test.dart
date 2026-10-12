/// Profil at every text size (design-analysis §7.13, §8.3), measured with
/// the app's own fonts on a 360 dp phone: from the header to "Çıkış yap",
/// no label or value is cut, in Turkish and English, from 100 % to 200 %.
/// The test font draws every glyph a full em wide, so only the real fonts
/// show what a phone would cut.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/profile/profile_screen.dart';

import '../support/app_fonts.dart';

// A long name and e-mail, the longest values the rows hold.
const _user = User(
  id: 9,
  displayName: 'Hamza Gedikkaya',
  initials: 'HG',
  email: 'hamza.gedikkaya@meridian.local',
  currency: 'TRY',
  subunitToUnit: 100,
  locale: 'tr',
  themePreference: 'dark',
  timezone: 'Buenos Aires',
  timezoneIana: 'America/Argentina/Buenos_Aires',
  utcOffset: Duration(hours: -3),
  weeklyReviewDay: 0,
);

/// Every paragraph laid out now: none is cut short.
void _expectNothingCut(WidgetTester tester, String where) {
  for (final text in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  )) {
    expect(
      text.didExceedMaxLines,
      isFalse,
      reason: '"${text.text.toPlainText()}" is cut ($where)',
    );
  }
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await initializeDateFormatting();
  });

  for (final locale in const [Locale('tr'), Locale('en')]) {
    for (final scale in const [1.0, 1.3, 1.5, 2.0]) {
      testWidgets('${locale.languageCode} at ${scale}x: every row whole, top '
          'to bottom', (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          PrefKeys.serverUrl: 'http://meridian.test:3000',
        });
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            currentUserProvider.overrideWithValue(_user),
            apiHealthProvider.overrideWith(
              (ref) async => (ok: true, latencyMs: 38, version: '1.0.0'),
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
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const ProfileScreen(),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // A screenful at a time, down to the end of the list.
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        var screens = 0;
        while (true) {
          _expectNothingCut(tester, 'at ${position.pixels.round()} dp');
          if (position.pixels >= position.maxScrollExtent) break;
          position.jumpTo(
            (position.pixels + position.viewportDimension * 0.8)
                .clamp(0, position.maxScrollExtent),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(++screens, lessThan(40), reason: 'the list ends');
        }
        expect(
          find.text(locale.languageCode == 'tr' ? 'Çıkış yap' : 'Sign out'),
          findsOneWidget,
        );
      });
    }
  }
}
