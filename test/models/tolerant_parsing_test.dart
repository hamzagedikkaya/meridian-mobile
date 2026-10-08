import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/models/json_read.dart';
import 'package:meridian_mobile/models/todo.dart';

import '../support/fake_api.dart';

void main() {
  group('ChainDay.fromJson', () {
    test('a partial day of a multi-count habit: integer counts', () {
      // meridian Habit#chain_entry_for: entry[:completed] = count,
      // entry[:possible] = target_count (spec: "completed" => 2, "possible" => 3).
      final day = ChainDay.fromJson(const {
        'date': '2026-10-03',
        'status': 'partial',
        'completed': 2,
        'possible': 3,
      });
      expect(day.status, ChainStatus.partial);
      expect(day.completed, 2);
      expect(day.possible, 3);
    });

    test('boolean flags still parse (as 1/0) instead of failing the list', () {
      final day = ChainDay.fromJson(const {
        'date': '2026-10-03',
        'status': 'completed',
        'completed': true,
        'possible': false,
      });
      expect(day.completed, 1);
      expect(day.possible, 0);
    });

    test('absent, null or numeric-string counts', () {
      expect(
        ChainDay.fromJson(const {'date': '2026-10-04', 'status': 'missed'})
            .completed,
        isNull,
      );
      final day = ChainDay.fromJson(const {
        'date': '2026-10-04',
        'status': 'partial',
        'completed': null,
        'possible': '3',
      });
      expect(day.completed, isNull);
      expect(day.possible, 3);
    });

    test('a doubled count (1.0) parses as an integer', () {
      final day = ChainDay.fromJson(const {
        'date': '2026-10-04',
        'status': 'partial',
        'completed': 1.0,
        'possible': 3.0,
      });
      expect(day.completed, 1);
      expect(day.possible, 3);
    });
  });

  test('a whole /habits payload with a partial day parses (it used to throw)',
      () {
    final bundle = HabitsBundle.fromJson(
      jsonDecode(jsonEncode(habitsJson())) as Map<String, dynamic>,
    );
    final partial = bundle.habits.first.chain.first;
    expect(partial.status, ChainStatus.partial);
    expect(partial.completed, 1);
    expect(partial.possible, 3);
  });

  test('a habit log answer with a partial day parses', () {
    final result = HabitLogResult.fromJson(
      jsonDecode(jsonEncode(logJson())) as Map<String, dynamic>,
    );
    expect(result.habit.today.completed, isTrue);
    expect(result.habit.chain.first.completed, 1);
  });

  group('json_read', () {
    test('readInt', () {
      expect(readInt(3), 3);
      expect(readInt(3.0), 3);
      expect(readInt('12'), 12);
      expect(readInt(' 7.0 '), 7);
      expect(readInt(true), 1);
      expect(readInt(null), 0);
      expect(readInt('x', fallback: 5), 5);
      expect(readInt(double.nan, fallback: 4), 4);
      expect(readInt(double.infinity), 0);
    });

    test('readBool', () {
      expect(readBool(true), isTrue);
      expect(readBool(0), isFalse);
      expect(readBool(2), isTrue);
      expect(readBool('true'), isTrue);
      expect(readBool('0'), isFalse);
      expect(readBool(null), isFalse);
      expect(readBool('maybe', fallback: true), isTrue);
    });

    test('readDouble', () {
      expect(readDouble(42), 42.0);
      expect(readDouble('42.5'), 42.5);
      expect(readDouble(null), 0);
    });

    test('readId tolerates 12.0 and "12" but not a missing id', () {
      expect(readId(12), 12);
      expect(readId(12.0), 12);
      expect(readId('12'), 12);
      expect(() => readId(null), throwsFormatException);
      expect(() => readId('abc'), throwsFormatException);
    });
  });

  test('flags sent as 0/1 and counts sent as doubles parse across models', () {
    final home = HomeSummary.fromJson({
      ...homeJson(),
      'open_todos': 2.0,
      'today_habits': [
        {
          'id': 7.0,
          'name': 'Koşu',
          'target_count': '1',
          'completed_today': 1,
          'today_count': 1.0,
          'current_streak': 2,
        },
      ],
    });
    expect(home.openTodos, 2);
    expect(home.todayHabits.single.id, 7);
    expect(home.todayHabits.single.completedToday, isTrue);

    final todo = Todo.fromJson({...todoJson(), 'overdue': 0});
    expect(todo.overdue, isFalse);

    final account = Account.fromJson(const {
      'id': 1,
      'name': 'Cüzdan',
      'balance_cents': 1500.0,
      'archived': 'false',
    });
    expect(account.balanceCents, 1500);
    expect(account.archived, isFalse);
  });
}
