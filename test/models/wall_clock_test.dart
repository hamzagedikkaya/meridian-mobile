/// Datetimes from the server read as the account's wall clock, and "today"
/// counted in the account's zone (contract G1.1).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/formats.dart';
import 'package:meridian_mobile/models/date_utils.dart';

void main() {
  group('parseDateTime reads the account\'s wall clock', () {
    test('the date and time as written, whatever the offset', () {
      final evening = parseDateTime('2026-10-04T18:00:00.000+03:00')!;
      expect((evening.year, evening.month, evening.day), (2026, 10, 4));
      expect((evening.hour, evening.minute), (18, 0));
      expect(evening.isUtc, isFalse);

      // 01:00 on the 5th in Istanbul is still the 4th in UTC: the day is
      // the account's, not UTC's (the bug the critic found before G1).
      final early = parseDateTime('2026-10-05T01:00:00+03:00')!;
      expect((early.day, early.hour), (5, 1));

      final west = parseDateTime('2026-10-04T23:30:00-05:00')!;
      expect((west.day, west.hour, west.minute), (4, 23, 30));
    });

    test('a server from before G1 wrote wall-clock times with Z: read as '
        'written', () {
      final t = parseDateTime('2026-10-04T09:00:00.000Z')!;
      expect((t.hour, t.minute), (9, 0));
    });

    test('fractions, compact offsets and no offset at all', () {
      final t = parseDateTime('2026-10-04T18:05:09.123456+0300')!;
      expect((t.second, t.millisecond, t.microsecond), (9, 123, 456));
      expect(parseDateTime('2026-10-04T18:05')!.minute, 5);
      expect(parseDateTime('2026-10-04T18:05:00+03')!.hour, 18);
    });

    test('a date alone is that day at 00:00', () {
      expect(parseDateTime('2026-10-04'), DateTime(2026, 10, 4));
    });

    test('null and garbage are null, not a thrown payload', () {
      expect(parseDateTime(null), isNull);
      expect(parseDateTime(''), isNull);
      expect(parseDateTime('soon'), isNull);
      expect(parseDateTime(42), isNull);
    });

    test('sent back without an offset, it is the same wall-clock time — which '
        'the server reads in the account\'s zone', () {
      final t = parseDateTime('2026-10-05T09:00:00.000+03:00')!;
      expect(t.toIso8601String(), '2026-10-05T09:00:00.000');
    });
  });

  group('UTC offsets', () {
    test('parse and format', () {
      expect(parseUtcOffset('+03:00'), const Duration(hours: 3));
      expect(parseUtcOffset('-05:30'), const Duration(hours: -5, minutes: -30));
      expect(parseUtcOffset('+0545'), const Duration(hours: 5, minutes: 45));
      expect(parseUtcOffset('Z'), Duration.zero);
      expect(parseUtcOffset('Istanbul'), isNull);
      expect(parseUtcOffset(null), isNull);
      expect(parseUtcOffset('+25:00'), isNull);
      expect(formatUtcOffset(const Duration(hours: 3)), '+03:00');
      expect(
        formatUtcOffset(const Duration(hours: -5, minutes: -30)),
        '-05:30',
      );
      expect(formatUtcOffset(Duration.zero), '+00:00');
    });
  });

  group('dayIn: the date in the account\'s zone', () {
    const istanbul = Duration(hours: 3);
    test('late evening UTC is already tomorrow in Istanbul', () {
      final now = DateTime.utc(2026, 10, 4, 22, 30);
      expect(dayIn(now, istanbul), DateTime(2026, 10, 5));
      expect(dayIn(now, const Duration(hours: -5)), DateTime(2026, 10, 4));
    });

    test('without an offset, the device\'s own date', () {
      final now = DateTime(2026, 10, 4, 23, 59);
      expect(dayIn(now, null), DateTime(2026, 10, 4));
    });
  });

  group('untilNextDayIn: until the account\'s midnight', () {
    test('lands just after it', () {
      const istanbul = Duration(hours: 3);
      final now = DateTime.utc(2026, 10, 4, 20, 59, 30); // 23:59:30 there
      final wait = untilNextDayIn(now, istanbul);
      expect(wait, const Duration(seconds: 31));
      expect(dayIn(now.add(wait), istanbul), DateTime(2026, 10, 5));
    });

    test('a zone behind UTC', () {
      final now = DateTime.utc(2026, 10, 5, 4, 0); // 23:00 on the 4th in NYC
      final wait = untilNextDayIn(now, const Duration(hours: -5));
      expect(wait, const Duration(hours: 1, seconds: 1));
    });

    test('stays between one second and 26 hours', () {
      final now = DateTime.utc(2026, 10, 4, 21);
      expect(
        untilNextDayIn(now, const Duration(hours: 3)),
        lessThanOrEqualTo(const Duration(hours: 26)),
      );
      expect(
        untilNextDayIn(
          DateTime.utc(2026, 10, 4, 20, 59, 59, 999),
          const Duration(hours: 3),
        ),
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
    });
  });

  group('relative days count from the app\'s today', () {
    tearDown(() => setAppToday(null));

    test('the account\'s today, once set', () {
      setAppToday(DateTime(2026, 10, 5));
      expect(appToday(), DateTime(2026, 10, 5));
      expect(dayDelta(DateTime(2026, 10, 5, 23, 59)), 0);
      expect(dayDelta(DateTime(2026, 10, 4)), -1);
      expect(dayDelta(DateTime(2026, 10, 6)), 1);
    });

    test('a 23-hour daylight-saving day is still one day', () {
      // Calendar arithmetic, not a 24-hour division of the instants.
      expect(
        dayDelta(DateTime(2026, 3, 30), now: DateTime(2026, 3, 29, 12)),
        1,
      );
      expect(dayDelta(DateTime(2026, 10, 26), now: DateTime(2026, 10, 25)), 1);
    });

    test('back to the device\'s date when unset', () {
      setAppToday(DateTime(2000, 1, 1));
      setAppToday(null);
      final now = DateTime.now();
      expect(appToday(), DateTime(now.year, now.month, now.day));
    });
  });
}
