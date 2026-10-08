import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/models/me_options.dart';
import 'package:meridian_mobile/models/user.dart';

import '../support/fake_api.dart';

void main() {
  final options = MeOptions.fromJson(meOptionsJson());

  test('reads the currencies and the zones, with the offset in effect now', () {
    expect(options.currencies.map((c) => c.code), [
      'TRY',
      'USD',
      'EUR',
      'GBP',
      'GAU',
    ]);
    expect(options.currencies.last.subunitToUnit, 1);
    final london = options.timezones.first;
    expect(london.value, 'London');
    expect(london.iana, 'Europe/London');
    expect(london.utcOffset, const Duration(hours: 1));
  });

  test(
    'tolerates a zone with no usable offset and drops one with no value',
    () {
      final odd = MeOptions.fromJson({
        'timezones': [
          {
            'value': 'Mars',
            'name': 'Mars',
            'iana': 'Mars/Olympus',
            'utc_offset': 'soon',
          },
          {'name': 'no value'},
        ],
      });
      expect(odd.timezones, hasLength(1));
      expect(odd.timezones.single.utcOffset, isNull);
      expect(odd.currencies, isEmpty);
    },
  );

  test('finds the account\'s zone by its Rails name, else its IANA id', () {
    expect(options.zoneOf(value: 'Kyiv')?.iana, 'Europe/Kiev');
    expect(options.zoneOf(iana: 'Europe/Istanbul')?.value, 'Istanbul');
    expect(
      options.zoneOf(value: 'Nowhere', iana: 'Asia/Tokyo')?.value,
      'Tokyo',
    );
    expect(options.zoneOf(value: 'Nowhere'), isNull);
  });

  test('suggests the zones whose clock reads like this device\'s', () {
    expect(options.zonesAt(const Duration(hours: 3)).map((z) => z.value), [
      'Kyiv',
      'Istanbul',
    ]);
    expect(options.zonesAt(const Duration(hours: -5)), isEmpty);
  });

  test('search matches name, IANA id and offset, ignoring case and the '
      'Turkish i', () {
    final istanbul = options.zoneOf(value: 'Istanbul')!;
    expect(istanbul.matches(''), isTrue);
    expect(istanbul.matches('İSTANBUL'), isTrue);
    expect(istanbul.matches('istanbul'), isTrue);
    expect(istanbul.matches('europe/ist'), isTrue);
    expect(istanbul.matches('+03'), isTrue);
    expect(istanbul.matches('tokyo'), isFalse);
  });

  test(
    'search takes the offset as the hint writes it, and its short forms',
    () {
      final istanbul = options.zoneOf(value: 'Istanbul')!;
      // The picker's hint: "Şehir ya da UTC+03 ara".
      expect(istanbul.matches('UTC+03'), isTrue);
      expect(istanbul.matches('utc+3'), isTrue);
      expect(istanbul.matches('UTC +3'), isTrue);
      expect(istanbul.matches('GMT+3'), isTrue);
      expect(istanbul.matches('+3'), isTrue);
      expect(istanbul.matches('+03:00'), isTrue);
      expect(istanbul.matches('utc'), isTrue);
      expect(istanbul.matches('UTC+05'), isFalse);
      expect(istanbul.matches('utc-3'), isFalse);
    },
  );

  group('User.weeklyReviewDay', () {
    test('0 (Sunday) … 6 (Saturday)', () {
      expect(User.fromJson(userJson()).weeklyReviewDay, 0);
      expect(
        User.fromJson({
          ...userJson(),
          'weekly_review_day': '6',
        }).weeklyReviewDay,
        6,
      );
    });

    test('missing or out of range: unknown', () {
      final old = {...userJson()}..remove('weekly_review_day');
      expect(User.fromJson(old).weeklyReviewDay, isNull);
      expect(
        User.fromJson({...userJson(), 'weekly_review_day': 9}).weeklyReviewDay,
        isNull,
      );
    });
  });
}
