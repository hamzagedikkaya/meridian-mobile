/// The repository's habit, goal and journal management writes against the
/// contract (G1 habit logs, G4): the requests they send, and what they
/// refresh.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/repository.dart';
import 'package:meridian_mobile/data/sync.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/journal.dart';

import '../support/fake_api.dart';
import '../support/read_models.dart';

Map<String, dynamic> _archivedKitap() => {
  ...habitJson(id: 11, name: 'Kitap'),
  'archived': true,
  'archived_at': '2026-09-28T18:00:00.000+03:00',
};

void main() {
  late FakeApi api;
  late ProviderContainer container;
  late MeridianRepository repo;

  setUp(() {
    api = FakeApi()
      ..onRequest('GET /habits', (request) {
        if (request.queryParameters['archived'] == true) {
          return {
            'habits': [_archivedKitap()],
            'meta': habitsMeta(),
          };
        }
        return habitsJson();
      });
    container = containerFor(api);
    repo = container.read(repositoryProvider);
  });

  tearDown(() => container.dispose());

  group('habits', () {
    test('the archive list asks for the archived habits only', () async {
      final archived = await repo.fetchArchivedHabits();
      expect(archived.single.name, 'Kitap');
      expect(archived.single.archived, isTrue);
    });

    test('the detail asks for a year of history, so any day of it can be '
        'logged', () async {
      api.onRequest('GET /habits/7', (request) {
        expect(request.queryParameters['days'], habitHistoryDays);
        return {'habit': habitJson()};
      });
      container.listen(habitDetailProvider(7), (_, _) {});
      await settle(api);
      expect(container.read(habitDetailProvider(7)).hasValue, isTrue);
    });

    test('an edit sends only what changed', () async {
      final before = Habit.fromJson({
        ...habitJson(),
        'description': 'Web\'de yazıldı',
        'goal_id': 3,
      });
      await repo.updateHabit(
        before,
        HabitInput(
          name: 'Sabah koşusu',
          frequency: before.frequency,
          targetCount: before.targetCount,
          color: before.color,
          description: before.description,
          goalId: before.goalId,
        ),
      );
      expect(api.bodiesOf('PATCH /habits/7').single, {'name': 'Sabah koşusu'});
    });

    test('archive, restore and delete hit their routes', () async {
      final archived = await repo.archiveHabit(7);
      expect(archived.id, 7);
      await repo.unarchiveHabit(7);
      await repo.deleteHabit(7);
      expect(api.requests, [
        'PATCH /habits/7/archive',
        'PATCH /habits/7/unarchive',
        'DELETE /habits/7',
      ]);
    });

    test(
      'archiving, restoring and deleting refresh the archive list too',
      () async {
        container.listen(archivedHabitsProvider, (_, _) {});
        await settle(api);
        for (final write in <Future<Object?> Function()>[
          () => repo.archiveHabit(7),
          () => repo.unarchiveHabit(7),
          () => repo.deleteHabit(7),
        ]) {
          var archivedReads = 0;
          api.onRequest('GET /habits', (request) {
            if (request.queryParameters['archived'] == true) archivedReads++;
            return {
              'habits': [_archivedKitap()],
              'meta': habitsMeta(),
            };
          });
          await write();
          await settle(api);
          expect(archivedReads, 1);
        }
      },
    );

    test(
      'a past day is set with its own date and the explicit count',
      () async {
        final result = await repo.setHabitLog(
          7,
          DateTime(2026, 10, 2),
          count: 1,
        );
        expect(api.bodiesOf('PUT /habits/7/logs/2026-10-02').single, {
          'count': 1,
        });
        expect(result.log!.date, DateTime(2026, 10, 2));
      },
    );

    test('the server\'s refusals of a day keep their codes', () async {
      for (final (code, extra) in [
        ('future_date', <String, Object>{}),
        ('before_habit_start', {'habit_start': '2026-09-20'}),
        ('habit_archived', <String, Object>{}),
      ]) {
        api.on('PUT /habits/7/logs/2026-10-02', {
          'errors': {
            'date': ['x'],
          },
          'code': code,
          ...extra,
        }, status: 422);
        await expectLater(
          repo.setHabitLog(7, DateTime(2026, 10, 2), count: 1),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
        );
      }
    });

    test('habit_archived refreshes the lists: the habit was archived '
        'elsewhere', () async {
      container.listen(habitsProvider, (_, _) {});
      await settle(api);
      api
        ..clearLog()
        ..on('PUT /habits/7/logs/2026-10-02', {
          'errors': {
            'base': ['x'],
          },
          'code': 'habit_archived',
        }, status: 422);
      await expectLater(
        repo.setHabitLog(7, DateTime(2026, 10, 2), count: 1),
        throwsA(isA<ApiException>()),
      );
      await settle(api);
      expect(api.gets, contains('/habits'));
    });
  });

  group('goals', () {
    final linked = Goal.fromJson({
      ...goalJson(),
      'target_type': 'financial',
      'progress_source': 'account',
      'related': {
        'type': 'Account',
        'id': 1,
        'name': 'Cüzdan',
        'balance_cents': 125000,
        'currency': 'TRY',
        'subunit_to_unit': 100,
      },
    });

    test('an edit keeps the link it did not change', () async {
      await repo.updateGoal(
        linked,
        GoalInput(
          name: 'Tatil',
          targetType: linked.targetType,
          color: linked.color,
          unit: linked.unit,
          targetValue: linked.targetValue,
          related: linked.relatedRef,
        ),
      );
      final body = api.bodiesOf('PATCH /goals/3').single as Map;
      expect(body, {'name': 'Tatil'});
      expect(body.containsKey('related'), isFalse);
    });

    test('linking, abandoning, reopening and marking achieved send the '
        'status rules\' bodies', () async {
      await repo.linkGoal(3, 'Habit-7');
      await repo.abandonGoal(3);
      await repo.reopenGoal(3);
      await repo.reopenGoal(3, targetValue: 150);
      await repo.markGoalAchieved(Goal.fromJson(goalJson()));
      expect(api.bodiesOf('PATCH /goals/3'), [
        {'related': 'Habit-7'},
        {'status': 'abandoned'},
        {'status': 'active'},
        {'status': 'active', 'target_value': 150},
        {'status': 'achieved', 'current_value': 100.0},
      ]);
    });

    test('target_reached and target_not_reached keep their codes, and are '
        'worded', () async {
      api.on('PATCH /goals/3', {
        'errors': {
          'status': ['x'],
        },
        'code': 'target_reached',
        'current_value': 120.0,
        'target_value': 100.0,
        'progress_source': 'manual',
      }, status: 422);
      await expectLater(
        repo.reopenGoal(3),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'target_reached'),
        ),
      );
    });

    test('a delete removes the goal and is not asked for again', () async {
      container.listen(goalDetailProvider(3), (_, _) {});
      container.listen(goalsProvider, (_, _) {});
      await settle(api);
      api.clearLog();
      await repo.deleteGoal(3);
      await settle(api);
      expect(api.requests.first, 'DELETE /goals/3');
      expect(api.gets, contains('/goals'));
      expect(api.gets, isNot(contains('/goals/3')));
    });
  });

  group('journal', () {
    final entry = JournalEntry.fromJson({
      ...journalEntryJson(),
      'body_text': 'Bir.\n\nİki.',
      'body_format': 'rich',
      'body_formatting': ['bold'],
    });

    test('an edit of the title alone leaves the body untouched', () async {
      await repo.updateJournalEntry(
        entry,
        JournalInput(
          date: entry.date,
          title: 'Yeni',
          bodyText: entry.editableBody,
          mood: entry.mood,
          energyLevel: entry.energyLevel,
        ),
      );
      expect(api.bodiesOf('PATCH /journal_entries/20').single, {
        'title': 'Yeni',
      });
    });

    test('a changed body over web formatting is sent with the go-ahead only '
        'when asked', () async {
      final input = JournalInput(
        date: entry.date,
        title: entry.title,
        bodyText: 'Bir.\n\nÜç.',
        mood: entry.mood,
        energyLevel: entry.energyLevel,
      );
      await repo.updateJournalEntry(entry, input);
      await repo.updateJournalEntry(entry, input, discardFormatting: true);
      expect(api.bodiesOf('PATCH /journal_entries/20'), [
        {'body_text': 'Bir.\n\nÜç.'},
        {'body_text': 'Bir.\n\nÜç.', 'discard_formatting': true},
      ]);
    });

    test(
      'body_has_formatting keeps its code and what the formatting is',
      () async {
        api.on('PATCH /journal_entries/20', {
          'errors': {
            'body_text': ['x'],
          },
          'code': 'body_has_formatting',
          'body_formatting': ['bold', 'list'],
        }, status: 422);
        await expectLater(
          repo.updateJournalEntry(
            entry,
            JournalInput(date: entry.date, bodyText: 'Başka'),
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', 'body_has_formatting')
                .having((e) => e.extra['body_formatting'], 'formatting', [
                  'bold',
                  'list',
                ]),
          ),
        );
      },
    );
  });

  test('a refresh of /home and the goals fetches each once, together — '
      '/home never waits for the goals', () async {
    container.listen(homeProvider, (_, _) {});
    container.listen(goalsProvider, (_, _) {});
    await settle(api);
    api
      ..clearLog()
      ..hold('GET /goals');
    container.read(dataSyncProvider).refresh([homeProvider, goalsProvider]);
    await settle(api);
    expect(container.read(homeProvider).isLoading, isFalse);
    api.release('GET /goals');
    await settle(api);
    expect(api.gets, unorderedEquals(['/home', '/goals']));
  });
}
