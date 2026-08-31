/// The localization layer: date/number shaping per language, the copy maps that
/// translate API values, and the error contract the UI shows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/core/formats.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/l10n/app_l10n_en.dart';
import 'package:meridian_mobile/l10n/app_l10n_tr.dart';

const tr = AppL10nTr();
const en = AppL10nEn();

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('locale resolution', () {
    test('forLocale maps the two shipped languages, else Turkish', () {
      expect(AppL10n.forLocale(const Locale('tr')).localeCode, 'tr');
      expect(AppL10n.forLocale(const Locale('en')).localeCode, 'en');
      expect(AppL10n.forLocale(const Locale('de')).localeCode, 'tr');
    });

    test('the delegate supports tr/en only and syncs Intl.defaultLocale',
        () async {
      expect(AppL10n.delegate.isSupported(const Locale('tr')), isTrue);
      expect(AppL10n.delegate.isSupported(const Locale('en')), isTrue);
      expect(AppL10n.delegate.isSupported(const Locale('de')), isFalse);

      await AppL10n.delegate.load(const Locale('en'));
      expect(Intl.defaultLocale, 'en');
      await AppL10n.delegate.load(const Locale('tr'));
      expect(Intl.defaultLocale, 'tr');
    });

    testWidgets('context.l10n follows the app locale', (tester) async {
      Future<void> pump(Locale locale) => tester.pumpWidget(MaterialApp(
            locale: locale,
            supportedLocales: AppL10n.supportedLocales,
            localizationsDelegates: const [
              AppL10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) => Text(context.l10n.titleFinance),
            ),
          ));

      await pump(const Locale('tr'));
      expect(find.text('Finans'), findsOneWidget);

      await pump(const Locale('en'));
      await tester.pump();
      expect(find.text('Finance'), findsOneWidget);
    });
  });

  group('numbers and dates follow the language', () {
    test('percent sign goes where the language puts it', () {
      expect(tr.percent(82), '%82');
      expect(en.percent(82), '82%');
      expect(tr.percent(82.4), '%82');
    });

    test('money grouping and decimals', () {
      expect(formatMoney(123456789, 'TRY', 100, locale: 'tr'), '1.234.567,89 ₺');
      expect(formatMoney(123456789, 'TRY', 100, locale: 'en'), '1,234,567.89 ₺');
      // Gram-gold has a subunit of 1 in both languages — never 4,12.
      expect(formatMoney(412, 'GAU', 1, locale: 'tr'), '412 gr');
      expect(formatMoney(412, 'GAU', 1, locale: 'en'), '412 gr');
    });

    test('chart axis abbreviations', () {
      expect(tr.compactThousands(75000), '75B');
      expect(en.compactThousands(75000), '75K');
      expect(tr.compactMillions(1500000), '1,5Mn');
      expect(en.compactMillions(1500000), '1.5M');
    });

    test('dates use the locale word order', () {
      final date = DateTime(2026, 8, 27);
      expect(formatDate(date, locale: 'tr'), '27 Ağustos');
      expect(formatDate(date, locale: 'en'), 'August 27');
      expect(formatMonthShort(date, locale: 'tr'), 'Ağu');
      expect(formatMonthShort(date, locale: 'en'), 'Aug');
    });
  });

  group('relative days', () {
    final now = DateTime.now();
    DateTime day(int delta) => DateTime(now.year, now.month, now.day)
        .add(Duration(days: delta));

    test('dayDelta is signed around today', () {
      expect(dayDelta(day(0)), 0);
      expect(dayDelta(day(-1)), -1);
      expect(dayDelta(day(3)), 3);
    });

    test('today / yesterday / tomorrow, then a formatted date', () {
      expect(tr.relativeDay(day(0)), 'Bugün');
      expect(tr.relativeDay(day(-1)), 'Dün');
      expect(tr.relativeDay(day(1)), 'Yarın');
      expect(en.relativeDay(day(0)), 'Today');
      expect(en.relativeDay(day(-1)), 'Yesterday');
      expect(en.relativeDay(day(1)), 'Tomorrow');
      // 40 days out is no longer relative — it becomes a date.
      expect(tr.relativeDay(day(40)), isNot(contains('gün')));
    });

    test('distances read naturally in both languages', () {
      expect(tr.relativeDays(day(0)), 'bugün');
      expect(tr.relativeDays(day(3)), '3 gün sonra');
      expect(tr.relativeDays(day(-2)), '2 gün önce');
      expect(en.relativeDays(day(0)), 'today');
      expect(en.relativeDays(day(3)), 'in 3 days');
      expect(en.relativeDays(day(-2)), '2 days ago');
    });

    test('greetings cover the whole clock', () {
      for (final l in [tr, en]) {
        for (var hour = 0; hour < 24; hour++) {
          expect(l.greeting(hour), isNotEmpty);
        }
      }
      expect(tr.greeting(9), 'İyi sabahlar');
      expect(en.greeting(9), 'Good morning');
      expect(tr.greeting(2), 'İyi geceler');
      expect(en.greeting(20), 'Good evening');
    });
  });

  group('API values map to copy in both languages', () {
    test('account types', () {
      for (final type in ['cash', 'bank', 'credit_card', 'savings', 'crypto']) {
        expect(tr.accountType(type), isNotEmpty);
        expect(en.accountType(type), isNotEmpty);
      }
      expect(tr.accountType('credit_card'), 'Kredi Kartı');
      expect(en.accountType('credit_card'), 'Credit Card');
      // An unknown type still renders something sensible.
      expect(en.accountType('brokerage'), 'Account');
    });

    test('moods, weather, frequencies and journal ranges', () {
      for (final mood in ['great', 'good', 'neutral', 'bad', 'awful']) {
        expect(tr.moodLabel(mood), isNotEmpty);
        expect(en.moodLabel(mood), isNotEmpty);
      }
      expect(en.moodLabel('neutral'), 'Okay');
      expect(tr.weatherLabel('partly_cloudy'), 'Parçalı bulutlu');
      expect(en.weatherLabel('partly_cloudy'), 'Partly cloudy');
      expect(tr.subscriptionFrequency('monthly'), 'Aylık');
      expect(en.subscriptionFrequency('monthly'), 'Monthly');
      expect(tr.journalRange('6mo'), '6ay');
      expect(en.journalRange('6mo'), '6mo');
      expect(en.journalRange('anything-else'), 'All');
    });

    test('English pluralises entry counts', () {
      expect(en.journalEntriesCount(1), '1 entry');
      expect(en.journalEntriesCount(4), '4 entries');
      expect(tr.journalEntriesCount(4), '4 kayıt');
    });
  });

  group('ApiException copy', () {
    test('every kind has a sentence in both languages', () {
      for (final kind in ApiErrorKind.values) {
        final e = ApiException(kind, status: 500);
        expect(e.localized(tr), isNotEmpty);
        expect(e.localized(en), isNotEmpty);
      }
    });

    test('a validation error prefers the server\'s own message', () {
      final e = ApiException(
        ApiErrorKind.validation,
        status: 422,
        fieldErrors: const {'amount_cents': ['must be greater than 0']},
      );
      expect(e.localized(en), 'must be greater than 0');
      expect(e.isValidation, isTrue);
    });

    test('a validation error with no message falls back to the language', () {
      final e = ApiException(ApiErrorKind.validation, status: 422);
      expect(e.localized(tr), 'Geçersiz veri');
      expect(e.localized(en), 'Invalid data');
    });

    test('login vs session 401s say different things', () {
      expect(
        ApiException(ApiErrorKind.invalidCredentials).localized(en),
        'Wrong email or password',
      );
      expect(
        ApiException(ApiErrorKind.unauthorized).localized(en),
        'Your session expired',
      );
    });
  });
}
