import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/data/actions.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/sync.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/ui/widgets/sync_hint.dart';

import '../support/fake_api.dart';
import '../support/read_models.dart';

HomeHabit _homeRow(ProviderContainer c, int id) => c
    .read(homeProvider)
    .value!
    .data
    .todayHabits
    .firstWhere((h) => h.id == id);

Habit _habit(ProviderContainer c, int id) => c
    .read(habitsProvider)
    .value!
    .data
    .habits
    .firstWhere((h) => h.id == id);

bool _homeDone(ProviderContainer c, int id) => _homeRow(c, id).completedToday;

bool _habitsDone(ProviderContainer c, int id) =>
    _habit(c, id).today.completed;

List<int> _habitIds(ProviderContainer c) => [
      for (final h in c.read(habitsProvider).value!.data.habits) h.id,
    ];

int _patches(FakeApi api, int id) =>
    api.requests.where((r) => r == _log(id)).length;

/// The write a tap on habit [id] sends for the fake server's today.
String _log(int id, [String day = '2026-10-04']) => 'PUT /habits/$id/logs/$day';

const _log7 = 'PUT /habits/7/logs/2026-10-04';
const _log8 = 'PUT /habits/8/logs/2026-10-04';

/// GET /habits after a habit was added on the web.
Map<String, dynamic> _habitsWithOneAddedOnTheWeb() => {
      'habits': [
        habitJson(),
        habitJson(id: 8, name: 'Su', targetCount: 3, count: 1),
        habitJson(id: 9, name: 'Web'),
      ],
      'meta': habitsMeta(totalActive: 3),
    };

void main() {
  late FakeApi api;
  late ProviderContainer container;

  setUp(() async {
    api = FakeApi();
    container = containerFor(api);
    container.listen(homeProvider, (_, _) {});
    container.listen(habitsProvider, (_, _) {});
    await settle(api);
    api.clearLog();
  });

  group('HabitActions.setToday', () {
    test('ticks Today and Habits in the same frame, before the server answers',
        () async {
      api.hold(_log7);
      final actions = container.read(habitActionsProvider);
      final request = actions.setToday(7, 1);

      expect(_homeDone(container, 7), isTrue);
      expect(_habitsDone(container, 7), isTrue);
      expect(container.read(habitsProvider).value!.data.completedToday, 1);
      expect(actions.isBusy(7), isTrue);

      // The server now has it done.
      api.on('GET /home', homeJson(habit7Done: true));
      api.release(_log7);
      expect(await request, isTrue);
      // The count asked for, for the day the server reported as today.
      expect(api.bodiesOf(_log7).single, {'count': 1});
      expect(actions.isBusy(7), isFalse);
      // The server's answer replaced the habit on both tabs, its streak
      // included.
      expect(_habit(container, 7).currentStreak, 3);
      expect(_homeRow(container, 7).currentStreak, 3);

      await settle(api);
      // Home's derived numbers (streaks, %, perfect day) come from the
      // server; the Habits list needs no refetch — the response was the
      // truth already. A goal may track the habit: /home recalculates the
      // goal bars it shows itself.
      expect(api.gets, ['/home']);
      expect(_homeDone(container, 7), isTrue);
      expect(_habitsDone(container, 7), isTrue);
    });

    test('a counted habit is set to the count the tap asked for, on both '
        'tabs', () async {
      api.hold(_log8);
      final request = container.read(habitActionsProvider).setToday(8, 2);

      final today = _habit(container, 8).today;
      expect(today.count, 2);
      expect(today.completed, isFalse);
      final row = _homeRow(container, 8);
      expect(row.todayCount, 2);
      expect(row.completedToday, isFalse);

      api.release(_log8);
      expect(await request, isTrue);
      expect(api.bodiesOf(_log8).single, {'count': 2});
    });

    test('a stale screen cannot flip a habit the wrong way: a tap that asks '
        'for "done" on a habit the server already has done keeps it done',
        () async {
      // Ticked on the web meanwhile; this screen still shows it open.
      final request = container.read(habitActionsProvider).setToday(7, 1);
      expect(await request, isTrue);
      expect(api.bodiesOf(_log7).single, {'count': 1},
          reason: 'a count, never a flip');
      expect(_homeDone(container, 7), isTrue);
      expect(_habitsDone(container, 7), isTrue);
    });

    test('a weekly habit\'s day is done or not: the patch stores its target, '
        'as the server does', () async {
      final weekly = {
        ...habitJson(id: 8, name: 'Su', targetCount: 3, count: 0),
        'frequency': 'weekly',
      };
      api.on('GET /habits', {
        'habits': [habitJson(), weekly],
        'meta': habitsMeta(),
      });
      container.read(dataSyncProvider).refresh([habitsProvider]);
      await settle(api);
      final actions = container.read(habitActionsProvider);
      expect(actions.isDaily(8), isFalse);
      expect(actions.isDaily(7), isTrue);

      api.hold(_log8);
      final request = actions.setToday(8, 3);
      expect(_habit(container, 8).today.count, 3);
      expect(_habitsDone(container, 8), isTrue);
      // Today's row, which does not know the frequency, follows the list.
      expect(_homeRow(container, 8).completedToday, isTrue);
      api.release(_log8);
      expect(await request, isTrue);
    });

    test('asking how often a habit repeats never fetches a hidden Habits '
        'tab (Today asks while it builds)', () async {
      final api = FakeApi();
      final c = containerFor(api);
      c.listen(homeProvider, (_, _) {});
      final habitsTab = c.listen(habitsProvider, (_, _) {});
      await settle(api);
      habitsTab.pause(); // the user is on Today
      // A write elsewhere leaves the hidden list due for a refetch.
      c.read(dataSyncProvider).refresh([habitsProvider]);
      await settle(api);
      api.clearLog();

      final actions = c.read(habitActionsProvider);
      expect(actions.isDaily(8), isTrue, reason: 'learned from the list');
      expect(actions.isDaily(999), isNull);
      await settle(api);
      expect(api.gets, isEmpty);
    });

    test('logs the day the tapped screen shows, not the device\'s date',
        () async {
      await container
          .read(habitActionsProvider)
          .setToday(7, 1, day: DateTime(2026, 10, 3));
      expect(api.requests, contains(_log(7, '2026-10-03')));
      // A screen showing another day is not patched.
      expect(_homeRow(container, 7).completedToday, isFalse);
    });

    test('a refusal is rolled back and carries its code (archived meanwhile)',
        () async {
      api.on(_log7, {
        'errors': {
          'base': ['Arşivlenmiş alışkanlık işaretlenemez.'],
        },
        'code': 'habit_archived',
      }, status: 422);
      await expectLater(
        container.read(habitActionsProvider).setToday(7, 1),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'habit_archived')),
      );
      expect(_homeDone(container, 7), isFalse);
      expect(_habitsDone(container, 7), isFalse);
      // The refusal says both lists are out of date: they ask again, and
      // drop the habit, instead of refusing every further tap.
      await settle(api);
      expect(api.gets, containsAll(['/home', '/habits']));
    });

    test('rolls both tabs back when the server cannot be reached', () async {
      api.failNetwork(_log7);
      await expectLater(
        container.read(habitActionsProvider).setToday(7, 1),
        throwsA(isA<ApiException>()),
      );
      expect(_homeDone(container, 7), isFalse);
      expect(_habitsDone(container, 7), isFalse);
      await settle(api);
      // The outcome is unknown, so both ask the server again.
      expect(api.gets.toSet(), {'/home', '/habits'});
    });

    group('a refetch in flight when the tap lands', () {
      late List<bool> seen;

      setUp(() async {
        seen = [];
        container.listen(habitsProvider, (_, next) {
          final habits = next.value?.data.habits;
          if (habits != null) {
            seen.add(habits.firstWhere((h) => h.id == 7).today.completed);
          }
        });
        // A refresh (re-tap, pull-to-refresh, shown again) is on its way,
        // and the server has news: a habit added on the web.
        api.on('GET /habits', _habitsWithOneAddedOnTheWeb());
        api.hold('GET /habits');
        container.read(dataSyncProvider).refresh([habitsProvider]);
        await settle(api);
      });

      test('and lands after the answer: its news is kept, and the tick never '
          'flicks back (the Habits flicker)', () async {
        await container.read(habitActionsProvider).setToday(7, 1);
        // The refetch left before the server saw the tap.
        api.release('GET /habits');
        await settle(api);

        expect(_habitIds(container), [7, 8, 9]);
        expect(_habitsDone(container, 7), isTrue);
        expect(seen.skipWhile((done) => !done), everyElement(isTrue),
            reason: 'once ticked, no frame shows it unticked: $seen');
        expect(api.gets.where((p) => p == '/habits'), hasLength(1));
      });

      test('and lands before the answer: its news is shown at once, with the '
          'tap on it', () async {
        api.hold(_log7);
        final tick = container.read(habitActionsProvider).setToday(7, 1);
        api.release('GET /habits');
        await settle(api);
        expect(_habitIds(container), [7, 8, 9]);
        expect(_habitsDone(container, 7), isTrue);

        api.release(_log7);
        expect(await tick, isTrue);
        await settle(api);
        expect(_habitIds(container), [7, 8, 9]);
        expect(_habitsDone(container, 7), isTrue);
        expect(seen.skipWhile((done) => !done), everyElement(isTrue),
            reason: 'once ticked, no frame shows it unticked: $seen');
        expect(api.gets.where((p) => p == '/habits'), hasLength(1));
      });
    });

    group('a refresh that lands before the answer, after the server applied '
        'the tap (pull-to-refresh, a re-tap, resume, midnight)', () {
      late List<bool> today;
      late List<bool> list;

      setUp(() {
        today = [];
        list = [];
        container.listen(homeProvider, (_, next) {
          final row = next.value?.data.todayHabits.firstWhere((h) => h.id == 7);
          if (row != null) today.add(row.completedToday);
        });
        container.listen(habitsProvider, (_, next) {
          final habit = next.value?.data.habits.firstWhere((h) => h.id == 7);
          if (habit != null) list.add(habit.today.completed);
        });
      });

      test('keeps the tick: it is set, not toggled again', () async {
        api.hold(_log7);
        final tick = container.read(habitActionsProvider).setToday(7, 1);
        expect(_homeDone(container, 7), isTrue);

        // The server has applied it; its answer is still on the way.
        api.on('GET /home', homeJson(habit7Done: true));
        api.on('GET /habits', habitsJson(habit7Done: true));
        container
            .read(dataSyncProvider)
            .refresh([homeProvider, habitsProvider]);
        await settle(api);
        expect(_homeDone(container, 7), isTrue);
        expect(_habitsDone(container, 7), isTrue);
        expect(container.read(habitsProvider).value!.data.completedToday, 1);

        api.release(_log7);
        expect(await tick, isTrue);
        await settle(api);
        expect(_homeDone(container, 7), isTrue);
        expect(_habitsDone(container, 7), isTrue);
        for (final (name, seen) in [('Today', today), ('Habits', list)]) {
          expect(seen.skipWhile((done) => !done), everyElement(isTrue),
              reason: '$name: once ticked, no frame shows it unticked: $seen');
        }
      });

      test('a counted habit keeps the count it was tapped to', () async {
        api.hold(_log8);
        final tap = container.read(habitActionsProvider).setToday(8, 2);
        expect(_homeRow(container, 8).todayCount, 2);

        // Su (8) is at 2/3 on the server already.
        final home = homeJson();
        home['today_habits'] = [
          for (final h in home['today_habits'] as List<Map<String, dynamic>>)
            h['id'] == 8 ? {...h, 'today_count': 2} : h,
        ];
        api.on('GET /home', home);
        container.read(dataSyncProvider).refresh([homeProvider]);
        await settle(api);
        expect(_homeRow(container, 8).todayCount, 2, reason: 'not 3');

        api.release(_log8);
        expect(await tap, isTrue);
        expect(_homeRow(container, 8).todayCount, 2);
      });
    });

    group('a hidden Habits list that is due for a refetch', () {
      // Yesterday Su (8) was done 3/3; the server now has it at 1/3.
      final before = {
        'habits': [
          habitJson(),
          habitJson(
              id: 8, name: 'Su', targetCount: 3, count: 3, completed: true),
        ],
        'meta': habitsMeta(completedToday: 1),
      };
      final triggers = <String, void Function(ProviderContainer, void Function())>{
        'after a new day': (c, nextDay) {
          nextDay();
          c.read(currentDayProvider.notifier).sync();
        },
        'after refreshAll (back from the background, Today pulled)': (c, _) =>
            c.read(dataSyncProvider).refreshAll(),
      };

      for (final MapEntry(key: trigger, value: makeDue) in triggers.entries) {
        test('$trigger: a tick on Today keeps the refetched list', () async {
          var now = DateTime(2026, 10, 4, 22);
          final api = FakeApi();
          final c = containerFor(
            api,
            overrides: [clockProvider.overrideWithValue(() => now)],
          );
          api.on('GET /habits', before);
          c.listen(homeProvider, (_, _) {});
          final habitsTab = c.listen(habitsProvider, (_, _) {});
          await settle(api);
          habitsTab.pause(); // the user is on Today
          api.on('GET /habits', habitsJson());
          makeDue(c, () => now = DateTime(2026, 10, 5, 7));
          await settle(api);
          api.clearLog();

          await c.read(habitActionsProvider).setToday(7, 1);
          await settle(api);
          habitsTab.resume(); // the user opens Habits
          await settle(api);

          final su = _habit(c, 8).today;
          expect((su.count, su.completed), (1, false),
              reason: 'the refetched list, not the one from before');
          expect(_habitsDone(c, 7), isTrue, reason: 'with the tick on it');
          expect(api.gets.where((p) => p == '/habits'), hasLength(1));
        });
      }
    });

    test('a Habits list opened while the tap is on its way gets the answer on '
        'its first fetch (which may predate it)', () async {
      final api2 = FakeApi();
      final c = containerFor(api2);
      c.listen(homeProvider, (_, _) {});
      await settle(api2);
      api2.clearLog();

      api2.hold(_log7);
      api2.hold('GET /habits');
      final request = c.read(habitActionsProvider).setToday(7, 1);
      // The Habits tab is opened for the first time while the tick is on its
      // way: its first GET /habits is still unanswered when the tick lands.
      c.listen(habitsProvider, (_, _) {});
      await settle(api2);
      api2.release(_log7);
      expect(await request, isTrue);
      // That GET left before the server answered, so it lists 7 as open.
      api2.release('GET /habits');
      await settle(api2);

      expect(_habitsDone(c, 7), isTrue);
      expect(_habit(c, 7).currentStreak, 3);
      expect(api2.gets.where((g) => g == '/habits'), hasLength(1));
    });

    group('a tick that straddles midnight', () {
      // GET /habits on the new day, with Koşu (7) [done] there.
      Map<String, dynamic> nextDay({bool done = false}) => {
            'habits': [
              {
                ...habitJson(completed: done, count: done ? 1 : 0),
                'today': {
                  'date': '2026-10-05',
                  'completed': done,
                  'count': done ? 1 : 0,
                },
              },
              {
                ...habitJson(id: 8, name: 'Su', targetCount: 3),
                'today': {'date': '2026-10-05', 'completed': false, 'count': 0},
              },
            ],
            'meta': habitsMeta(completedToday: done ? 1 : 0),
          };

      late DateTime now;
      late FakeApi api;
      late ProviderContainer c;

      setUp(() async {
        now = DateTime(2026, 10, 4, 23, 59, 58);
        api = FakeApi();
        c = containerFor(
          api,
          overrides: [clockProvider.overrideWithValue(() => now)],
        );
        c.listen(homeProvider, (_, _) {});
        c.listen(habitsProvider, (_, _) {});
        await settle(api);
        api.clearLog();
      });

      test('answered after the new day\'s list left: that list shows as the '
          'server sent it, not with the old day\'s answer on it', () async {
        api.hold(_log7);
        final tick = c.read(habitActionsProvider).setToday(7, 1);
        expect(_habitsDone(c, 7), isTrue);

        // Midnight: the new day's list leaves before the answer arrives,
        // and lands after it.
        api
          ..on('GET /habits', nextDay())
          ..hold('GET /habits');
        now = DateTime(2026, 10, 5, 0, 0, 1);
        c.read(currentDayProvider.notifier).sync();
        await settle(api);
        expect(api.gets, contains('/habits'));

        // The server ticked it on the 4th — the day the tap asked for.
        api.release(_log7);
        expect(await tick, isTrue);
        expect(api.requests, contains(_log7));
        api.release('GET /habits');
        await settle(api);

        final habit = _habit(c, 7);
        expect(habit.today.date, DateTime(2026, 10, 5));
        expect(habit.today.completed, isFalse);
        expect(c.read(habitsProvider).value!.data.completedToday, 0);
      });

      test('Today\'s new day, landing while the tap is on its way, does not '
          'show the old day\'s tap', () async {
        api.hold(_log7);
        final tick = c.read(habitActionsProvider).setToday(7, 1);
        expect(_homeDone(c, 7), isTrue);

        // Midnight: the new day's /home, with Koşu (7) open.
        api.on('GET /home', {...homeJson(), 'today': '2026-10-05'});
        now = DateTime(2026, 10, 5, 0, 0, 1);
        c.read(currentDayProvider.notifier).sync();
        await settle(api);
        expect(c.read(homeProvider).value!.data.today, DateTime(2026, 10, 5));
        expect(_homeDone(c, 7), isFalse,
            reason: 'the tap was for the 4th, not for this day');

        api.release(_log7);
        expect(await tick, isTrue);
        await settle(api);
        expect(_homeDone(c, 7), isFalse);
      });

      test('answered once the server\'s day moved on: the day the tap asked '
          'for is logged, the list (still on the old day) leaves the answer '
          'out, and the write\'s own refetch brings the new day', () async {
        api
          ..on(_log7, {
            'habit': {
              ...habitJson(streak: 3),
              'today': {'date': '2026-10-05', 'completed': false, 'count': 0},
            },
            'meta': habitsMeta(),
            'log': {'date': '2026-10-04', 'count': 1, 'completed': true},
          })
          ..on('GET /habits', nextDay());
        expect(await c.read(habitActionsProvider).setToday(7, 1), isTrue);
        await settle(api);

        expect(api.gets, contains('/habits'),
            reason: 'the answer is not about the day the list showed');
        final habit = _habit(c, 7);
        expect(habit.today.date, DateTime(2026, 10, 5));
        expect(habit.today.completed, isFalse);
      });
    });

    group('a tap keeps what the screen showed besides the data', () {
      test('a refetch on its way: still loading — the hint stays — until '
          'it lands', () async {
        api.hold('GET /habits');
        container.read(dataSyncProvider).refresh([habitsProvider]);
        await settle(api);
        expect(container.read(habitsProvider).isRefetching, isTrue);

        expect(await container.read(habitActionsProvider).setToday(7, 1),
            isTrue);
        expect(_habitsDone(container, 7), isTrue);
        expect(container.read(habitsProvider).isRefetching, isTrue,
            reason: 'the refetch is still on its way');

        api.release('GET /habits');
        await settle(api);
        expect(container.read(habitsProvider).isLoading, isFalse);
        expect(_habitsDone(container, 7), isTrue);
      });

      test('the last refresh failed: the offline banner stays up through the '
          'tap, its answer and a rollback', () async {
        api.failNetwork('GET /habits');
        container.read(dataSyncProvider).refresh([habitsProvider]);
        await settle(api);
        expect(container.read(habitsProvider).refreshFailed, isTrue);

        api.hold(_log7);
        final tick = container.read(habitActionsProvider).setToday(7, 1);
        expect(_habitsDone(container, 7), isTrue);
        expect(container.read(habitsProvider).refreshFailed, isTrue);
        api.release(_log7);
        expect(await tick, isTrue);
        expect(container.read(habitsProvider).refreshFailed, isTrue);

        api.failNetwork(_log8);
        await expectLater(
          container.read(habitActionsProvider).setToday(8, 2),
          throwsA(isA<ApiException>()),
        );
        expect(container.read(habitsProvider).refreshFailed, isTrue);
        expect(_habitsDone(container, 7), isTrue);
      });
    });

    test('a tick on Today shows on a hidden Habits tab without a refetch',
        () async {
      final hidden = FakeApi();
      final c = containerFor(hidden);
      c.listen(homeProvider, (_, _) {});
      final habitsTab = c.listen(habitsProvider, (_, _) {});
      await settle(hidden);
      habitsTab.pause();
      hidden.clearLog();

      await c.read(habitActionsProvider).setToday(7, 1);
      await settle(hidden);
      habitsTab.resume();
      await settle(hidden);

      expect(_habitsDone(c, 7), isTrue);
      expect(hidden.gets, ['/home']);
    });

    group('quick taps', () {
      test('on a counted habit all count: each shows at once and is sent '
          'once the one before it is answered, and the server ends on the '
          'last', () async {
        api.hold(_log8);
        final actions = container.read(habitActionsProvider);
        // What the user sees: 1/3, then 2/3 after the first tap.
        final first = actions.setToday(8, 2);
        final second = actions.setToday(8, 3);

        // 1/3 → 3/3 at once, on both tabs.
        expect(_habit(container, 8).today.count, 3);
        expect(_habitsDone(container, 8), isTrue);
        expect(_homeRow(container, 8).todayCount, 3);
        await settle(api);
        expect(_patches(api, 8), 1, reason: 'the second waits for the first');

        api.release(_log8);
        expect(await first, isTrue);
        expect(await second, isTrue);
        expect(_patches(api, 8), 2);
        expect(api.bodiesOf(_log8), [
          {'count': 2},
          {'count': 3},
        ]);
        expect(_habit(container, 8).today.count, 3);
        expect(_homeRow(container, 8).todayCount, 3);
        expect(actions.isBusy(8), isFalse);
        await settle(api);
        // One /home refetch once both are in; Habits had both answers.
        expect(api.gets, ['/home']);
      });

      test('behind a tap that fails are taken back unsent', () async {
        api.failNetwork(_log8);
        api.hold(_log8);
        final actions = container.read(habitActionsProvider);
        final first = actions.setToday(8, 2);
        final second = actions.setToday(8, 3);
        expect(_habit(container, 8).today.count, 3);

        api.release(_log8);
        await expectLater(first, throwsA(isA<ApiException>()));
        expect(await second, isFalse);
        expect(_habit(container, 8).today.count, 1);
        expect(_homeRow(container, 8).todayCount, 1);
        expect(_patches(api, 8), 1);
        expect(actions.isBusy(8), isFalse);
      });

      test('on two habits never step the done count back, whichever answer '
          'comes first', () async {
        for (final firstAnswered in [7, 10]) {
          final api = FakeApi();
          final c = containerFor(api);
          api.on('GET /habits', {
            'habits': [habitJson(), habitJson(id: 10, name: 'Kitap')],
            'meta': habitsMeta(),
          });
          c.listen(homeProvider, (_, _) {});
          c.listen(habitsProvider, (_, _) {});
          await settle(api);
          // Each answer's header counts only what the server had then.
          api.on(_log(7), {
            'habit': habitJson(completed: true, count: 1),
            'meta': habitsMeta(completedToday: firstAnswered == 7 ? 1 : 2),
          });
          api.on(_log(10), {
            'habit': habitJson(id: 10, name: 'Kitap', completed: true, count: 1),
            'meta': habitsMeta(completedToday: firstAnswered == 10 ? 1 : 2),
          });
          final counts = <int>[];
          c.listen(habitsProvider, (_, next) {
            final bundle = next.value?.data;
            if (bundle != null) counts.add(bundle.completedToday);
          });
          api.hold(_log(7));
          api.hold(_log(10));
          final actions = c.read(habitActionsProvider);
          final ticks = [actions.setToday(7, 1), actions.setToday(10, 1)];

          final lastAnswered = firstAnswered == 7 ? 10 : 7;
          api.release(_log(firstAnswered));
          await settle(api);
          api.release(_log(lastAnswered));
          expect(await Future.wait(ticks), [true, true]);

          for (var i = 1; i < counts.length; i++) {
            expect(counts[i], greaterThanOrEqualTo(counts[i - 1]),
                reason: '$firstAnswered answered first: $counts');
          }
          expect(counts.last, 2);
        }
      });
    });
  });

  group('HabitCadence: how often a habit repeats, which /home does not say',
      () {
    test('with Today alone, the Habits list is read once, through its read '
        'model, which it does not keep', () async {
      final api = FakeApi();
      final c = containerFor(api);
      c.listen(homeProvider, (_, _) {});
      await settle(api);
      expect(api.gets, ['/home', '/habits']);
      expect(c.read(habitCadenceProvider), {7: true, 8: true});
      expect(c.exists(habitsProvider), isFalse,
          reason: 'read for the cadence, not kept alive by it');

      api.clearLog();
      c.read(dataSyncProvider).refresh([homeProvider]);
      await settle(api);
      expect(api.gets, ['/home'], reason: 'known now: not read again');
    });

    test('nothing is read when /home lists no habit done more than once a '
        'day', () async {
      final home = homeJson();
      home['today_habits'] = [
        for (final habit in home['today_habits'] as List<Map<String, dynamic>>)
          if (habit['target_count'] == 1) habit,
      ];
      final api = FakeApi()..on('GET /home', home);
      final c = containerFor(api);
      c.listen(homeProvider, (_, _) {});
      await settle(api);
      expect(api.gets, ['/home']);
    });

    test('an open Habits tab is not asked twice', () async {
      // The setUp's container shows Today and Habits.
      expect(container.read(habitCadenceProvider), {7: true, 8: true});
      final fresh = FakeApi();
      final c = containerFor(fresh);
      c.listen(homeProvider, (_, _) {});
      c.listen(habitsProvider, (_, _) {});
      await settle(fresh);
      expect(fresh.gets.where((p) => p == '/habits'), hasLength(1));
    });

    test('a habit added on the web is read for when /home first lists it',
        () async {
      final api = FakeApi();
      final c = containerFor(api);
      c.listen(homeProvider, (_, _) {});
      await settle(api);

      final home = homeJson();
      home['today_habits'] = [
        ...home['today_habits'] as List<Map<String, dynamic>>,
        {
          'id': 10,
          'name': 'Kitap',
          'color': '#6B8E5A',
          'target_count': 3,
          'completed_today': false,
          'today_count': 0,
          'current_streak': 0,
        },
      ];
      api.on('GET /home', home);
      api.on('GET /habits', {
        'habits': [
          habitJson(),
          habitJson(id: 8, name: 'Su', targetCount: 3, count: 1),
          {
            ...habitJson(id: 10, name: 'Kitap', targetCount: 3),
            'frequency': 'weekly',
          },
        ],
        'meta': habitsMeta(totalActive: 3),
      });
      api.clearLog();
      c.read(dataSyncProvider).refresh([homeProvider]);
      await settle(api);
      expect(api.gets, ['/home', '/habits']);
      expect(c.read(habitActionsProvider).isDaily(10), isFalse);
    });

    test('a failed read is tried again with the next /home', () async {
      final api = FakeApi()..fail('GET /habits', 500);
      final c = containerFor(api);
      c.listen(homeProvider, (_, _) {});
      await settle(api);
      expect(c.read(habitActionsProvider).isDaily(8), isNull);

      api.on('GET /habits', habitsJson());
      api.clearLog();
      c.read(dataSyncProvider).refresh([homeProvider]);
      await settle(api);
      expect(api.gets, ['/home', '/habits']);
      expect(c.read(habitActionsProvider).isDaily(8), isTrue);
    });
  });

  group('TodoActions.setDone', () {
    const toggle = 'PATCH /todos/39/toggle';

    test('checks the todo on Today at once and moves the badge counts, then '
        'sends done=true', () async {
      api.hold(toggle);
      final request =
          container.read(todoActionsProvider).setDone(39, done: true);
      final home = container.read(homeProvider).value!.data;
      expect(home.upcomingTodos.single.isDone, isTrue);
      expect(home.openTodos, 0);
      expect(home.overdueCount, 0);

      api.release(toggle);
      expect(await request, isTrue);
      expect(api.bodiesOf(toggle).single, {'done': true});
      await settle(api);
      expect(api.gets, ['/home']);
    });

    test('a stale screen cannot reopen a finished todo: done=true on a todo '
        'the server already has done leaves it done', () async {
      // Finished on the web meanwhile; Today still lists it open.
      expect(
          await container.read(todoActionsProvider).setDone(39, done: true),
          isTrue);
      expect(api.bodiesOf(toggle).single, {'done': true},
          reason: 'never a bare flip');
      expect(
        container.read(homeProvider).value!.data.upcomingTodos.single.isDone,
        isTrue,
      );
    });

    test('a checked row tapped again reopens it: done=false', () async {
      final actions = container.read(todoActionsProvider);
      api.hold(toggle);
      final done = actions.setDone(39, done: true);
      final reopen = actions.setDone(39, done: false);
      expect(
        container.read(homeProvider).value!.data.upcomingTodos.single.isDone,
        isFalse,
      );
      api.release(toggle);
      expect(await done, isTrue);
      expect(await reopen, isTrue);
      expect(api.bodiesOf(toggle), [
        {'done': true},
        {'done': false},
      ], reason: 'sent in order, each after the one before is answered');
      final home = container.read(homeProvider).value!.data;
      expect(home.upcomingTodos.single.isDone, isFalse);
      expect((home.openTodos, home.overdueCount), (1, 1));
    });

    test('undo after a refetch dropped the finished todo puts it back where '
        'it was, at once', () async {
      final todo = container.read(homeProvider).value!.data.upcomingTodos.single;
      await container.read(todoActionsProvider).setDone(39, done: true);
      // The refetch after the tick: /home lists open todos only.
      api.on('GET /home', {
        ...homeJson(todos: const []),
        'open_todos': 0,
        'overdue_count': 0,
      });
      await settle(api);
      expect(container.read(homeProvider).value!.data.upcomingTodos, isEmpty);

      api
        ..on('GET /home', homeJson())
        ..hold(toggle);
      final undo = container
          .read(todoActionsProvider)
          .setDone(39, done: false, restore: (todo: todo, index: 0));
      var home = container.read(homeProvider).value!.data;
      expect(home.upcomingTodos.single.id, 39);
      expect(home.upcomingTodos.single.isDone, isFalse);
      expect((home.openTodos, home.overdueCount), (1, 1));

      api.release(toggle);
      expect(await undo, isTrue);
      expect(api.bodiesOf(toggle).last, {'done': false});
      await settle(api);
      home = container.read(homeProvider).value!.data;
      expect(home.upcomingTodos.single.isDone, isFalse);
      expect(home.upcomingTodos, hasLength(1), reason: 'listed once');
    });

    test('a refetch replaces the optimistic tick (no stuck checked row)',
        () async {
      await container.read(todoActionsProvider).setDone(39, done: true);
      // Meanwhile the todo was reopened on the web: /home lists it as open.
      api.on('GET /home', homeJson(todos: [todoJson(status: 'pending')]));
      await settle(api);
      expect(
        container.read(homeProvider).value!.data.upcomingTodos.single.isDone,
        isFalse,
      );
      // And it can be ticked again.
      expect(
          await container.read(todoActionsProvider).setDone(39, done: true),
          isTrue);
    });

    test('a refresh that lands before the answer, after the server applied '
        'it, keeps it checked and the badge where it is', () async {
      api.hold(toggle);
      final request =
          container.read(todoActionsProvider).setDone(39, done: true);

      // The server has it done; its answer is still on the way.
      api.on('GET /home', {
        ...homeJson(todos: [todoJson(status: 'done')]),
        'open_todos': 0,
        'overdue_count': 0,
      });
      container.read(dataSyncProvider).refresh([homeProvider]);
      await settle(api);
      var home = container.read(homeProvider).value!.data;
      expect(home.upcomingTodos.single.isDone, isTrue);
      expect((home.openTodos, home.overdueCount), (0, 0));

      api.release(toggle);
      expect(await request, isTrue);
      home = container.read(homeProvider).value!.data;
      expect(home.upcomingTodos.single.isDone, isTrue);
      expect((home.openTodos, home.overdueCount), (0, 0));
    });

    test('the server\'s answer replaces the expected status until the '
        'refetch lands', () async {
      // An in-progress todo stays in progress when "not done" is asked for.
      api.on(toggle, {
        'id': 39,
        'status': 'in_progress',
        'completed_at': null,
        'todo': todoJson(status: 'in_progress'),
      });
      api.hold(toggle);
      final request =
          container.read(todoActionsProvider).setDone(39, done: false);

      api.hold('GET /home');
      api.release(toggle);
      expect(await request, isTrue);
      expect(
        container.read(homeProvider).value!.data.upcomingTodos.single.status,
        'in_progress',
      );
      api.release('GET /home');
      await settle(api);
    });

    test('rolls back when the server rejects it', () async {
      api.fail(toggle, 500);
      await expectLater(
        container.read(todoActionsProvider).setDone(39, done: true),
        throwsA(isA<ApiException>()),
      );
      final home = container.read(homeProvider).value!.data;
      expect(home.upcomingTodos.single.isDone, isFalse);
      expect(home.overdueCount, 1);
    });

    test('a tap behind one that failed is taken back unsent', () async {
      api
        ..failNetwork(toggle)
        ..hold(toggle);
      final actions = container.read(todoActionsProvider);
      final done = actions.setDone(39, done: true);
      final reopen = actions.setDone(39, done: false);
      api.release(toggle);
      await expectLater(done, throwsA(isA<ApiException>()));
      expect(await reopen, isFalse);
      expect(api.requests.where((r) => r == toggle), hasLength(1));
      expect(actions.isBusy(39), isFalse);
    });
  });
}
