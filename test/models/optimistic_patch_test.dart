import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/models/todo.dart';

import '../support/fake_api.dart';

Habit _weekly({int completedCount = 1}) => Habit.fromJson({
  ...habitJson(),
  'frequency': 'weekly',
  'target_count': 2,
  'period': {
    'range_start': '2026-09-28',
    'range_end': '2026-10-04',
    'completed_count': completedCount,
    'complete': completedCount >= 2,
  },
});

void main() {
  group('loggedDay mirrors what PUT /habits/:id/logs/:date stores', () {
    test('a daily habit counts within the day, done at its target', () {
      expect(loggedDay(count: 1, target: 1), (completed: true, count: 1));
      expect(loggedDay(count: 0, target: 1), (completed: false, count: 0));
      expect(loggedDay(count: 2, target: 3), (completed: false, count: 2));
      expect(loggedDay(count: 3, target: 3), (completed: true, count: 3));
    });

    test('a count outside 0..target is clamped, as on the server', () {
      expect(loggedDay(count: 9, target: 3), (completed: true, count: 3));
      expect(loggedDay(count: -1, target: 3), (completed: false, count: 0));
    });

    test('a weekly or monthly habit\'s day is done or not: any count stores '
        'the target', () {
      expect(loggedDay(count: 1, target: 3, daily: false), (
        completed: true,
        count: 3,
      ));
      expect(loggedDay(count: 0, target: 3, daily: false), (
        completed: false,
        count: 0,
      ));
    });
  });

  group('Habit', () {
    test(
      'only a daily habit with a target above one counts within the day',
      () {
        final bundle = HabitsBundle.fromJson(habitsJson());
        expect(
          bundle.habits.firstWhere((h) => h.id == 7).countsWithinDay,
          isFalse,
        );
        expect(
          bundle.habits.firstWhere((h) => h.id == 8).countsWithinDay,
          isTrue,
        );
        expect(_weekly().countsWithinDay, isFalse);
        expect(_weekly().isDaily, isFalse);
      },
    );

    test('checkCount: the target on an open day, 0 on a done one', () {
      final open = Habit.fromJson(habitJson(targetCount: 1));
      expect(open.checkCount, 1);
      final done = Habit.fromJson(habitJson(completed: true, count: 1));
      expect(done.checkCount, 0);
      expect(_weekly().checkCount, 2);
    });

    test('a weekly habit\'s period count follows the day', () {
      final weekly = _weekly();
      final done = weekly.withToday(weekly.logFor(1));
      expect(done.today.count, 2, reason: 'the server stores the target');
      expect(done.period!.completedCount, 2);
      expect(done.period!.complete, isTrue);
      final undone = done.withToday(done.logFor(0));
      expect(undone.period!.completedCount, 1);
      expect(undone.period!.complete, isFalse);
    });

    test('a weekly habit\'s period count moves once however often its log is '
        'set', () {
      final weekly = _weekly();
      final log = weekly.logFor(weekly.checkCount);
      final done = weekly.withToday(log).withToday(log);
      expect(done.period!.completedCount, 2);
    });
  });

  test('a tap\'s log is set, not toggled: applied again, or to a refetch '
      'that already has it, it changes nothing', () {
    final bundle = HabitsBundle.fromJson(habitsJson());
    final run = bundle.habits.firstWhere((h) => h.id == 7);
    final log = run.logFor(run.checkCount);
    final once = bundle.withHabitToday(7, log);
    expect(once.habits.firstWhere((h) => h.id == 7).today.completed, isTrue);
    expect(once.completedToday, 1);
    expect(once.withHabitToday(7, log), same(once));
    final fetched = HabitsBundle.fromJson(habitsJson(habit7Done: true));
    expect(
      fetched.withHabitToday(7, log),
      same(fetched),
      reason: 'the server\'s header is kept as it is',
    );
    expect(bundle.withHabitToday(999, log), same(bundle));

    // A counted habit set from 1/3 to 2/3 stays at 2/3 on a refetch at 2/3.
    final su = bundle.habits.firstWhere((h) => h.id == 8);
    final two = su.logFor(su.today.count + 1);
    expect(two, (completed: false, count: 2));
    expect(su.withToday(two).withToday(two).today.count, 2);
  });

  test('HabitsBundle.merge takes the server\'s habit and header', () {
    final bundle = HabitsBundle.fromJson(habitsJson());
    final result = HabitLogResult.fromJson(logJson());
    final merged = bundle.merge(result);
    expect(merged.habits.firstWhere((h) => h.id == 7), same(result.habit));
    expect(
      merged.habits.firstWhere((h) => h.id == 8),
      same(bundle.habits.firstWhere((h) => h.id == 8)),
    );
    expect(merged.completedToday, result.completedToday);
  });

  test('HabitsBundle.merge without the header recounts it and keeps the rest '
      '(other taps are still on their way)', () {
    // Su (8) was set to 3/3 too and waits for its answer; 7's answer
    // predates it.
    final bundle = HabitsBundle.fromJson(
      habitsJson(),
    ).withHabitToday(8, loggedDay(count: 3, target: 3));
    final result = HabitLogResult.fromJson(logJson());
    expect(result.completedToday, 1);
    final merged = bundle.merge(result, header: false);
    expect(merged.habits.firstWhere((h) => h.id == 7), same(result.habit));
    expect(merged.completedToday, 2);
    expect(merged.totalActive, bundle.totalActive);
    expect(merged.perfectDay, same(bundle.perfectDay));
  });

  test('HabitLogResult reads the day that was set', () {
    final result = HabitLogResult.fromJson(logAnswer(8, '2026-10-03', 2));
    expect(result.log!.date, DateTime(2026, 10, 3));
    expect(result.log!.count, 2);
    expect(result.log!.completed, isFalse);
    expect(result.habit.today.date, DateTime(2026, 10, 3));
    // An answer without `log` (toggle_today's shape) still parses.
    expect(
      HabitLogResult.fromJson({'habit': habitJson(), 'meta': habitsMeta()}).log,
      isNull,
    );
  });

  group('HomeSummary', () {
    test('carries the server\'s today', () {
      expect(HomeSummary.fromJson(homeJson()).today, DateTime(2026, 10, 4));
      expect(
        HomeSummary.fromJson({...homeJson(), 'today': null}).today,
        isNull,
      );
    });

    test(
      'merge sets the row as the server has it, and again changes nothing',
      () {
        final home = HomeSummary.fromJson(homeJson());
        final result = HabitLogResult.fromJson(logJson());
        final once = home.merge(result);
        final row = once.todayHabits.firstWhere((h) => h.id == 7);
        expect(row.completedToday, isTrue);
        expect(row.todayCount, 1);
        expect(row.currentStreak, 3);
        final twice = once
            .merge(result)
            .todayHabits
            .firstWhere((h) => h.id == 7);
        expect((twice.completedToday, twice.todayCount), (true, 1));
        // A habit that is not on Today leaves it as it is.
        final elsewhere = HabitLogResult.fromJson({
          'habit': habitJson(id: 999),
          'meta': habitsMeta(),
        });
        expect(home.merge(elsewhere), same(home));
      },
    );

    test('merge leaves an answer about another day out (a tap that '
        'straddled midnight)', () {
      final home = HomeSummary.fromJson(homeJson());
      final nextDay = HabitLogResult.fromJson(logAnswer(7, '2026-10-05', 1));
      expect(home.isDayOf(nextDay), isFalse);
      expect(home.merge(nextDay), same(home));
    });

    test('a row\'s log follows the frequency when it is known', () {
      final home = HomeSummary.fromJson(homeJson());
      final su = home.todayHabits.firstWhere((h) => h.id == 8);
      expect(su.logFor(2), (completed: false, count: 2));
      expect(su.logFor(1, daily: false), (completed: true, count: 3));
    });

    test('withTodoStatus checks the todo and moves the badge counts; set '
        'again it changes nothing', () {
      final home = HomeSummary.fromJson(homeJson());
      final done = home.withTodoStatus(39, 'done');
      expect(done.upcomingTodos.single.isDone, isTrue);
      expect(done.openTodos, home.openTodos - 1);
      expect(done.overdueCount, home.overdueCount - 1);
      expect(done.withTodoStatus(39, 'done'), same(done));

      // Reopened before the refetch: counts restored.
      final reopened = done.withTodoStatus(39, 'pending');
      expect(reopened.upcomingTodos.single.isDone, isFalse);
      expect(reopened.openTodos, home.openTodos);
      expect(reopened.overdueCount, home.overdueCount);
      expect(home.withTodoStatus(999, 'done'), same(home));

      final fetchedDone = HomeSummary.fromJson({
        ...homeJson(todos: [todoJson(status: 'done')]),
        'open_todos': 0,
        'overdue_count': 0,
      });
      expect(fetchedDone.withTodoStatus(39, 'done'), same(fetchedDone));
    });

    test('a todo list\'s filter counts (the Agenda chips, the tab badge) '
        'move with a tick, and back with a reopen', () {
      final bundle = TodosBundle.fromJson({
        'todos': [todoJson()],
        'meta': const {
          'open_count': 1,
          'overdue_count': 1,
          'counts': {
            'open': 1, 'today': 1, 'week': 1, 'upcoming': 0, 'overdue': 1,
            'undated': 0, 'done': 4, 'cancelled': 0, 'all': 5,
          },
        },
      });
      final today = DateTime(2026, 10, 4);
      final done = bundle.withTodoStatus(39, 'done', today: today);
      expect(done.counts, {
        'open': 0, 'today': 0, 'week': 0, 'upcoming': 0, 'overdue': 0,
        'undated': 0, 'done': 5, 'cancelled': 0, 'all': 5,
      });
      expect(done.withTodoStatus(39, 'pending', today: today).counts,
          bundle.counts);
      // Dropped by the refetch, then put back by an undo.
      final dropped = TodosBundle(
        todos: const [],
        openCount: 0,
        overdueCount: 0,
        counts: done.counts,
      );
      expect(
        dropped
            .withTodoReopened(Todo.fromJson(todoJson()), index: 0, today: today)
            .counts,
        bundle.counts,
      );
    });

    test('withTodoReopened puts back a todo a refetch dropped, at its place, '
        'and counts it again', () {
      final todo = Todo.fromJson(todoJson());
      final other = todoJson(id: 41);
      // The refetch after the tick: 39 is done, so /home no longer lists it.
      final dropped = HomeSummary.fromJson({
        ...homeJson(todos: [other]),
        'open_todos': 1,
        'overdue_count': 1,
      });
      final back = dropped.withTodoReopened(todo, index: 0);
      expect([for (final t in back.upcomingTodos) t.id], [39, 41]);
      expect(back.upcomingTodos.first.isDone, isFalse);
      expect((back.openTodos, back.overdueCount), (2, 2));

      // Listed open already (the refetch after the undo): nothing moves.
      expect(back.withTodoReopened(todo, index: 0), same(back));

      // Listed done (before the refetch): set open where it is.
      final shownDone = HomeSummary.fromJson(
        homeJson(),
      ).withTodoStatus(39, 'done');
      final reopened = shownDone.withTodoReopened(todo, index: 5);
      expect(reopened.upcomingTodos.single.isDone, isFalse);
      expect(reopened.upcomingTodos, hasLength(1));
    });

    test('a tap\'s habit log is set, not toggled: on a refetch that already '
        'has it nothing moves', () {
      final home = HomeSummary.fromJson(homeJson());
      final row = home.todayHabits.firstWhere((h) => h.id == 7);
      final log = row.logFor(row.targetCount);
      final ticked = home.withHabitToday(7, log);
      expect(
        ticked.todayHabits.firstWhere((h) => h.id == 7).completedToday,
        isTrue,
      );
      expect(ticked.withHabitToday(7, log), same(ticked));
      final fetchedTicked = HomeSummary.fromJson(homeJson(habit7Done: true));
      expect(fetchedTicked.withHabitToday(7, log), same(fetchedTicked));
    });
  });

  group('Todo', () {
    test(
      'reads the G3 due day and time, and a toggle answer of either shape',
      () {
        final todo = Todo.fromJson(todoJson());
        expect(todo.dueDate, DateTime(2026, 10, 4));
        expect(todo.dueTime, '18:00');
        expect(todo.dueDay, DateTime(2026, 10, 4));
        // The pre-G1 toggle answer: only id, status and completed_at.
        final bare = Todo.fromJson(const {'id': 39, 'status': 'done'});
        expect(bare.isDone, isTrue);
        expect(bare.dueDay, isNull);
      },
    );

    test('a todo without due_date takes its day from due_at, in the '
        'account\'s zone', () {
      final todo = Todo.fromJson({
        ...todoJson(),
        'due_date': null,
        'due_at': '2026-10-05T01:00:00.000+03:00',
      });
      expect(todo.dueDay, DateTime(2026, 10, 5));
    });
  });
}
