import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/formats.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/date_utils.dart';
import 'package:meridian_mobile/models/user.dart';

import '../support/fake_api.dart';
import '../support/read_models.dart';

/// The Dart VM that ships with the Flutter running these tests.
String? _dartVm() {
  final flutter = Platform.environment['FLUTTER_ROOT'];
  if (flutter == null) return null;
  final dart = File([
    flutter,
    'bin',
    'cache',
    'dart-sdk',
    'bin',
    Platform.isWindows ? 'dart.exe' : 'dart',
  ].join(Platform.pathSeparator));
  return dart.existsSync() ? dart.path : null;
}

void main() {
  group('untilNextDay', () {
    test('lands just after the next local midnight', () {
      for (final now in [
        DateTime(2026, 10, 4, 23, 59, 30),
        DateTime(2026, 10, 4, 12),
        DateTime(2026, 10, 4),
        DateTime(2026, 12, 31, 18, 30),
      ]) {
        final wait = untilNextDay(now);
        final at = now.add(wait);
        final nextDay = DateTime(now.year, now.month, now.day + 1);
        expect(dateOnly(at), dateOnly(nextDay), reason: '$now');
        expect(at.isAfter(nextDay), isTrue, reason: '$now');
        expect(at.difference(nextDay), lessThanOrEqualTo(const Duration(seconds: 1)),
            reason: '$now');
      }
    });

    test('stays between one second and 26 hours', () {
      final wait = untilNextDay(DateTime(2026, 10, 4, 23, 59, 59, 999));
      expect(wait, greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(untilNextDay(DateTime(2026, 10, 4)),
          lessThanOrEqualTo(const Duration(hours: 26)));
    });

    // This VM keeps the machine's time zone, which may never change its
    // clocks (Türkiye's has not since 2016), so these run the same checks in
    // a second Dart VM with TZ set to zones that do: Berlin at 02:00/03:00
    // (a 23- and a 25-hour day), Santiago at midnight itself (a day that
    // starts at 01:00, and an hour before midnight that happens twice).
    group('across daylight-saving changes', () {
      const zones = {
        'Europe/Berlin': ['2026-03-29', '2026-10-25'],
        'America/Santiago': ['2026-04-04', '2026-09-05'],
      };
      for (final MapEntry(key: zone, value: days) in zones.entries) {
        test(zone, () async {
          final dart = _dartVm();
          if (dart == null) {
            markTestSkipped('no Dart VM next to Flutter (FLUTTER_ROOT unset)');
            return;
          }
          final run = await Process.run(
            dart,
            [
              '--packages=.dart_tool/package_config.json',
              'test/support/dst_probe.dart',
              ...days,
            ],
            environment: {'TZ': zone},
          );
          final out = '${run.stdout}${run.stderr}';
          if (out.contains('nodst')) {
            markTestSkipped('this machine has no time zone data for $zone');
            return;
          }
          expect(run.exitCode, 0, reason: out);
          // Nine moments of each day, all checked.
          final passed = out.split('\n').where((line) => line.startsWith('ok '));
          expect(passed, hasLength(9 * days.length), reason: out);
        });
      }
    });
  });

  // The account is in Istanbul; these run in a second Dart VM whose TZ —
  // the phone's zone — is far from it, on either side.
  group('a phone in another time zone than the account', () {
    for (final zone in ['America/New_York', 'Asia/Tokyo', 'UTC']) {
      test(zone, () async {
        final dart = _dartVm();
        if (dart == null) {
          markTestSkipped('no Dart VM next to Flutter (FLUTTER_ROOT unset)');
          return;
        }
        final run = await Process.run(
          dart,
          [
            '--packages=.dart_tool/package_config.json',
            'test/support/zone_probe.dart',
          ],
          environment: {'TZ': zone},
        );
        final out = '${run.stdout}${run.stderr}';
        expect(run.exitCode, 0, reason: out);
        expect(out.split('\n').where((line) => line.startsWith('ok ')),
            hasLength(6),
            reason: out);
      });
    }
  });

  testWidgets('the day rolls over at midnight, and on resume after a '
      'suspension', (tester) async {
    var now = DateTime(2026, 10, 4, 23, 59, 50);
    final container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    final days = <DateTime>[];
    container.listen(currentDayProvider, (_, day) => days.add(day),
        fireImmediately: true);
    expect(days, [DateTime(2026, 10, 4)]);

    // The timer is armed for 10 s to midnight + 1 s of slack.
    await tester.pump(const Duration(seconds: 10));
    expect(days, hasLength(1));
    now = DateTime(2026, 10, 5, 0, 0, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(days.last, DateTime(2026, 10, 5));

    // Suspended across the next midnight: the OS froze the timer, so it is
    // the resume that notices the new day.
    now = DateTime(2026, 10, 7, 8, 15);
    container.read(currentDayProvider.notifier).sync();
    expect(days.last, DateTime(2026, 10, 7));

    // Resuming on the same day changes nothing.
    container.read(currentDayProvider.notifier).sync();
    expect(days, hasLength(3));

    container.dispose(); // cancels the midnight timer
  });

  test('a new day refetches date-relative read models and keeps them on '
      'screen meanwhile', () async {
    var now = DateTime(2026, 10, 4, 23, 59);
    final api = FakeApi();
    final container = containerFor(
      api,
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    container.listen(homeProvider, (_, _) {});
    container.listen(journalProvider('30d'), (_, _) {});
    container.listen(accountsProvider, (_, _) {});
    await settle(api);
    api.clearLog();

    api.hold('GET /home');
    now = DateTime(2026, 10, 5, 0, 1);
    container.read(currentDayProvider.notifier).sync();
    await settle(api);

    final home = container.read(homeProvider);
    expect(home.isLoading, isTrue);
    expect(home.hasValue, isTrue, reason: 'yesterday stays up while today loads');

    api.release('GET /home');
    await settle(api);
    // Balances do not depend on the date.
    expect(api.gets.toSet(), {'/home', '/journal_entries'});
  });

  test('a hidden tab picks up the new day the moment it is shown', () async {
    var now = DateTime(2026, 10, 4, 23, 59);
    final api = FakeApi();
    final container = containerFor(
      api,
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    final journalTab = container.listen(journalProvider('30d'), (_, _) {});
    await settle(api);
    journalTab.pause();
    api.clearLog();

    now = DateTime(2026, 10, 5, 7);
    container.read(currentDayProvider.notifier).sync();
    await settle(api);
    expect(api.gets, isEmpty, reason: 'hidden: nothing fetched yet');

    journalTab.resume();
    await settle(api);
    expect(api.gets, ['/journal_entries']);
  });

  group('showing a screen again', () {
    late DateTime now;
    late FakeApi api;
    late ProviderContainer container;
    late ProviderSubscription<Object?> goalsTab;

    setUp(() async {
      now = DateTime(2026, 10, 4, 9);
      api = FakeApi();
      container = containerFor(
        api,
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      goalsTab = container.listen(goalsProvider, (_, _) {});
      await settle(api);
      goalsTab.pause(); // switched to another tab
      api.clearLog();
    });

    test('refetches data older than a minute (edits made on the web)',
        () async {
      now = now.add(const Duration(minutes: 3));
      goalsTab.resume();
      await settle(api);
      expect(api.gets, ['/goals']);
      expect(container.read(goalsProvider).hasValue, isTrue);
    });

    test('leaves recent data alone', () async {
      now = now.add(const Duration(seconds: 20));
      goalsTab.resume();
      await settle(api);
      expect(api.gets, isEmpty);
    });
  });

  group('the account\'s day (its zone, from /me), not the device\'s', () {
    const istanbul = Duration(hours: 3);

    User account({Duration? offset = istanbul}) => User(
          id: 9,
          displayName: 'Demo',
          initials: 'D',
          email: 'demo@meridian.local',
          currency: 'TRY',
          subunitToUnit: 100,
          locale: 'tr',
          themePreference: 'dark',
          timezone: 'Istanbul',
          timezoneIana: 'Europe/Istanbul',
          utcOffset: offset,
        );

    testWidgets('today and its midnight follow the account\'s zone, and the '
        'labels count from it', (tester) async {
      // 23:59:30 in Istanbul, whatever zone this machine is in.
      var now = DateTime.utc(2026, 10, 4, 20, 59, 30);
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          currentUserProvider.overrideWithValue(account()),
        ],
      );
      final days = <DateTime>[];
      container.listen(currentDayProvider, (_, day) => days.add(day),
          fireImmediately: true);
      expect(days, [DateTime(2026, 10, 4)]);
      expect(appToday(), DateTime(2026, 10, 4));

      await tester.pump(const Duration(seconds: 30));
      expect(days, hasLength(1));
      now = DateTime.utc(2026, 10, 4, 21, 0, 1); // 00:00:01 in Istanbul
      await tester.pump(const Duration(seconds: 1));
      expect(days.last, DateTime(2026, 10, 5));
      expect(appToday(), DateTime(2026, 10, 5));
      expect(dayDelta(DateTime(2026, 10, 4)), -1);

      container.dispose();
      final device = DateTime.now();
      expect(appToday(), DateTime(device.year, device.month, device.day),
          reason: 'nothing keeps the account\'s day any more');
    });

    test('until /me has answered, the device\'s zone stands in', () {
      final now = DateTime(2026, 10, 4, 23, 30);
      final container = ProviderContainer.test(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          currentUserProvider.overrideWithValue(account(offset: null)),
        ],
      );
      expect(container.read(currentDayProvider), DateTime(2026, 10, 4));
    });

    test('date-relative reads ask for the account\'s today', () async {
      final api = FakeApi();
      String? from;
      api.onRequest('GET /events', (request) {
        from = '${request.queryParameters['from']}';
        return {'events': const []};
      });
      final container = containerFor(
        api,
        overrides: [
          // 22:30 UTC: still the 4th in London, the 5th in Istanbul.
          clockProvider
              .overrideWithValue(() => DateTime.utc(2026, 10, 4, 22, 30)),
          currentUserProvider.overrideWithValue(account()),
        ],
      );
      container.listen(eventsTodayProvider, (_, _) {});
      await settle(api);
      expect(from, '2026-10-05');
    });

    group('zoneMismatchProvider', () {
      ProviderContainer phone(Duration device, {Duration? offset = istanbul}) =>
          ProviderContainer.test(
            overrides: [
              currentUserProvider.overrideWithValue(account(offset: offset)),
              deviceUtcOffsetProvider.overrideWithValue(device),
            ],
          );

      test('says so when the phone is in another zone', () {
        final mismatch =
            phone(const Duration(hours: -4)).read(zoneMismatchProvider)!;
        expect(mismatch.zone, 'Europe/Istanbul');
        expect(mismatch.account, istanbul);
        expect(mismatch.device, const Duration(hours: -4));
      });

      test('says nothing when they agree, or before the account\'s zone is '
          'known', () {
        expect(phone(istanbul).read(zoneMismatchProvider), isNull);
        expect(
          phone(const Duration(hours: -4), offset: null)
              .read(zoneMismatchProvider),
          isNull,
        );
      });
    });
  });
}
