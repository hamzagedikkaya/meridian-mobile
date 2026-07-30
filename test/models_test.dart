import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/models/transaction.dart';

void main() {
  group('Transaction.fromJson', () {
    test('GAU-account row: subunit 1 passes through, amount_cents untouched',
        () {
      // Real row id 333 from api-samples (/transactions), GAU account, no category.
      final json = jsonDecode(r'''
      {
        "id": 333,
        "kind": "income",
        "amount_cents": 1,
        "date": "2026-05-15",
        "description": "1 gr altın alımı",
        "note": null,
        "account": {
          "id": 21,
          "name": "Altın",
          "color": "#B8860B",
          "currency": "GAU",
          "subunit_to_unit": 1
        },
        "category": null,
        "related_account": null
      }
      ''') as Map<String, dynamic>;

      final tx = Transaction.fromJson(json);
      expect(tx.id, 333);
      expect(tx.kind, 'income');
      expect(tx.amountCents, 1); // never divided
      expect(tx.account.currency, 'GAU');
      expect(tx.account.subunitToUnit, 1); // passes through
      expect(tx.category, isNull); // null-category row
      expect(tx.relatedAccount, isNull);
      expect(tx.note, isNull);
    });

    test('TRY row with a category parses the nested category', () {
      // Real row id 316 from api-samples.
      final json = jsonDecode(r'''
      {
        "id": 316,
        "kind": "expense",
        "amount_cents": 13874,
        "date": "2026-05-25",
        "description": "Restoran — Lokanta",
        "note": null,
        "account": {
          "id": 19,
          "name": "Kredi kartı",
          "color": "#B85450",
          "currency": "TRY",
          "subunit_to_unit": 100
        },
        "category": {
          "id": 35,
          "name": "Restoran",
          "kind": "expense",
          "color": "#B85450",
          "parent_id": null,
          "position": 0
        },
        "related_account": null
      }
      ''') as Map<String, dynamic>;

      final tx = Transaction.fromJson(json);
      expect(tx.amountCents, 13874);
      expect(tx.account.subunitToUnit, 100);
      expect(tx.category, isNotNull);
      expect(tx.category!.name, 'Restoran');
      expect(tx.category!.kind, 'expense');
      expect(tx.category!.parentId, isNull);
    });
  });

  group('Habit.fromJson', () {
    test('daily habit: today_pending chain, no period block', () {
      // Real habit id 50 from api-samples.
      final json = jsonDecode(r'''
      {
        "id": 50,
        "name": "5ee",
        "description": "ee",
        "frequency": "daily",
        "target_count": 5,
        "color": "#b8860b",
        "goal_id": null,
        "current_streak": 0,
        "longest_streak": 1,
        "completion_rate_30d": 0.0,
        "today": { "date": "2026-07-11", "completed": false, "count": 0 },
        "chain": [ { "date": "2026-07-11", "status": "today_pending" } ]
      }
      ''') as Map<String, dynamic>;

      final habit = Habit.fromJson(json);
      expect(habit.frequency, 'daily');
      expect(habit.targetCount, 5);
      expect(habit.goalId, isNull);
      expect(habit.period, isNull); // absent for daily
      expect(habit.chain.single.status, ChainStatus.todayPending);
      expect(habit.today.completed, isFalse);
    });

    test('weekly habit: period block present', () {
      // Real habit id 46 from api-samples.
      final json = jsonDecode(r'''
      {
        "id": 46,
        "name": "Drink 2L water",
        "description": "",
        "frequency": "weekly",
        "target_count": 3,
        "color": "#6b8e5a",
        "goal_id": null,
        "current_streak": 0,
        "longest_streak": 14,
        "completion_rate_30d": 0.0,
        "today": { "date": "2026-07-11", "completed": false, "count": 0 },
        "chain": [ { "date": "2026-07-11", "status": "today_pending" } ],
        "period": {
          "range_start": "2026-07-06",
          "range_end": "2026-07-12",
          "completed_count": 0,
          "complete": false
        }
      }
      ''') as Map<String, dynamic>;

      final habit = Habit.fromJson(json);
      expect(habit.frequency, 'weekly');
      expect(habit.period, isNotNull);
      expect(habit.period!.completedCount, 0);
      expect(habit.period!.complete, isFalse);
      expect(habit.period!.rangeStart, DateTime.parse('2026-07-06'));
    });

    test('ChainStatus.fromApi maps every documented status', () {
      expect(ChainStatus.fromApi('completed'), ChainStatus.completed);
      expect(ChainStatus.fromApi('partial'), ChainStatus.partial);
      expect(ChainStatus.fromApi('today_pending'), ChainStatus.todayPending);
      expect(ChainStatus.fromApi('missed'), ChainStatus.missed);
      expect(ChainStatus.fromApi('perfect'), ChainStatus.perfect);
      expect(ChainStatus.fromApi('no_habits'), ChainStatus.noHabits);
      expect(ChainStatus.fromApi('unknown'), ChainStatus.missed); // fallback
    });
  });

  group('Goal.fromJson', () {
    Map<String, dynamic> goal({
      required String badgeState,
      required int badgeDays,
      Object? related,
    }) =>
        {
          'id': 1,
          'name': 'G',
          'description': '',
          'target_type': 'custom',
          'status': 'active',
          'color': '#6B8E5A',
          'unit': 'days',
          'deadline': '2026-09-02',
          'days_remaining': badgeDays,
          'deadline_badge': {'state': badgeState, 'days': badgeDays},
          'target_value': 100.0,
          'current_value': 42.0,
          'progress_percent': 42.0,
          'related': related,
        };

    test('each deadline_badge state parses', () {
      for (final state in ['overdue', 'today', 'soon', 'far']) {
        final g = Goal.fromJson(goal(badgeState: state, badgeDays: 3));
        expect(g.deadlineBadge, isNotNull);
        expect(g.deadlineBadge!.state, state);
        expect(g.deadlineBadge!.days, 3);
      }
    });

    test('deadline parses as a date and progress values are doubles', () {
      final g = Goal.fromJson(goal(badgeState: 'far', badgeDays: 53));
      expect(g.deadline, DateTime.parse('2026-09-02'));
      expect(g.targetValue, 100.0);
      expect(g.currentValue, 42.0);
      expect(g.progressPercent, 42.0);
    });

    test('related: null', () {
      final g = Goal.fromJson(goal(badgeState: 'far', badgeDays: 3));
      expect(g.related, isNull);
    });

    test('related: Account (financial) carries balance + currency', () {
      final g = Goal.fromJson(goal(
        badgeState: 'far',
        badgeDays: 3,
        related: {
          'type': 'account',
          'id': 20,
          'name': 'Birikim',
          'balance_cents': 2500000,
          'currency': 'TRY',
          'subunit_to_unit': 100,
        },
      ));
      expect(g.related, isNotNull);
      expect(g.related!.type, 'account');
      expect(g.related!.balanceCents, 2500000);
      expect(g.related!.currency, 'TRY');
      expect(g.related!.currentStreak, isNull);
    });

    test('related: Habit carries streak + completed days', () {
      final g = Goal.fromJson(goal(
        badgeState: 'far',
        badgeDays: 3,
        related: {
          'type': 'habit',
          'id': 45,
          'name': 'Read 30 pages',
          'current_streak': 7,
          'completed_days': 42,
        },
      ));
      expect(g.related!.type, 'habit');
      expect(g.related!.currentStreak, 7);
      expect(g.related!.completedDays, 42);
      expect(g.related!.balanceCents, isNull);
    });
  });

  group('HomeSummary.fromJson', () {
    test('parses the real /home payload', () {
      final json = jsonDecode(_realHomeJson) as Map<String, dynamic>;
      final home = HomeSummary.fromJson(json);

      expect(home.currency, 'TRY');
      expect(home.subunitToUnit, 100);
      expect(home.monthNetCents, 0);
      expect(home.openTodos, 5);
      expect(home.overdueCount, 5);
      expect(home.habitCompletionPct, 0);

      expect(home.spending7d, hasLength(7));
      expect(home.spending7d.first.date, DateTime.parse('2026-07-05'));

      expect(home.todayHabits, hasLength(7));
      expect(home.todayHabits.first.id, 50);
      expect(home.todayHabits.first.targetCount, 5);

      expect(home.upcomingTodos, hasLength(5));
      expect(home.upcomingTodos.first.id, 35);
      expect(home.upcomingTodos.first.overdue, isTrue);
      expect(home.upcomingTodos.first.todoList!.name, 'Home');
      // Row id 38 has a null todo_list.
      final nullListTodo =
          home.upcomingTodos.firstWhere((t) => t.id == 38);
      expect(nullListTodo.todoList, isNull);

      expect(home.todayEvents, isEmpty);

      expect(home.activeGoals, hasLength(3));
      expect(home.activeGoals.first.progressPercent, 42.0);

      expect(home.perfectDay.currentStreak, 0);
      expect(home.perfectDay.chain.single.status, ChainStatus.missed);
    });
  });
}

// Verbatim GET /home payload from scratchpad/api-samples.json.
const String _realHomeJson = r'''
{
    "currency": "TRY",
    "subunit_to_unit": 100,
    "month_net_cents": 0,
    "active_streaks": 0,
    "open_todos": 5,
    "overdue_count": 5,
    "today_events_count": 0,
    "habit_completion_pct": 0,
    "spending_7d": [
        { "date": "2026-07-05", "cents": 0 },
        { "date": "2026-07-06", "cents": 0 },
        { "date": "2026-07-07", "cents": 0 },
        { "date": "2026-07-08", "cents": 0 },
        { "date": "2026-07-09", "cents": 0 },
        { "date": "2026-07-10", "cents": 0 },
        { "date": "2026-07-11", "cents": 0 }
    ],
    "today_habits": [
        { "id": 50, "name": "5ee", "color": "#b8860b", "target_count": 5, "completed_today": false, "today_count": 0, "current_streak": 0 },
        { "id": 46, "name": "Drink 2L water", "color": "#6b8e5a", "target_count": 3, "completed_today": false, "today_count": 0, "current_streak": 0 },
        { "id": 49, "name": "Gym session", "color": "#B85450", "target_count": 1, "completed_today": false, "today_count": 0, "current_streak": 0 },
        { "id": 48, "name": "Meditate 10 min", "color": "#8B5A00", "target_count": 1, "completed_today": false, "today_count": 0, "current_streak": 0 },
        { "id": 44, "name": "Morning workout", "color": "#D4A574", "target_count": 1, "completed_today": false, "today_count": 0, "current_streak": 0 },
        { "id": 45, "name": "Read 30 pages", "color": "#6B8FA0", "target_count": 1, "completed_today": false, "today_count": 0, "current_streak": 0 },
        { "id": 47, "name": "Write in journal", "color": "#B8860B", "target_count": 1, "completed_today": false, "today_count": 0, "current_streak": 0 }
    ],
    "upcoming_todos": [
        { "id": 35, "title": "Call electrician", "body": "About the kitchen socket.", "status": "pending", "priority": "high", "due_at": "2026-05-25T00:00:00.000Z", "overdue": true, "position": 3, "todo_list": { "id": 11, "name": "Home", "color": "#6B8E5A" }, "subtask_count": 0 },
        { "id": 39, "title": "Deploy v1.2", "body": null, "status": "pending", "priority": "urgent", "due_at": "2026-05-25T17:10:58.466Z", "overdue": true, "position": 7, "todo_list": { "id": 10, "name": "Work", "color": "#6B8FA0" }, "subtask_count": 0 },
        { "id": 36, "title": "Buy milk, bread, eggs", "body": null, "status": "pending", "priority": "low", "due_at": "2026-05-26T19:10:58.466Z", "overdue": true, "position": 4, "todo_list": { "id": 12, "name": "Shopping", "color": "#D4A574" }, "subtask_count": 0 },
        { "id": 37, "title": "Order birthday gift", "body": "Mum's birthday next week.", "status": "pending", "priority": "medium", "due_at": "2026-05-29T19:10:58.466Z", "overdue": true, "position": 5, "todo_list": { "id": 12, "name": "Shopping", "color": "#D4A574" }, "subtask_count": 0 },
        { "id": 38, "title": "Read 'The Pragmatic Engineer'", "body": "Chapter 4-6.", "status": "pending", "priority": "low", "due_at": "2026-06-01T19:10:58.466Z", "overdue": true, "position": 6, "todo_list": null, "subtask_count": 0 }
    ],
    "today_events": [],
    "active_goals": [
        { "id": 18, "name": "Read for 100 days", "color": "#6B8E5A", "progress_percent": 42.0 },
        { "id": 19, "name": "Lose 10 kg", "color": "#B85450", "progress_percent": 10.0 },
        { "id": 20, "name": "Learn German - A2", "color": "#6B8FA0", "progress_percent": 0.0 }
    ],
    "perfect_day": {
        "chain": [ { "date": "2026-07-11", "status": "missed" } ],
        "current_streak": 0
    }
}
''';
