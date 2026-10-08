/// Edits send only what changed (the server applies every key it gets,
/// nulls included), and the new contract keys of habits, goals and journal
/// entries are read.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/journal.dart';

import '../support/fake_api.dart';

Habit _habit({
  String description = 'Kahvaltıdan önce',
  int? goalId = 3,
  String? startDate = '2026-09-20',
  bool archived = false,
}) => Habit.fromJson({
  ...habitJson(),
  'description': description,
  'goal_id': goalId,
  'color': '#4a90d9',
  'start_date': startDate,
  'archived': archived,
  'archived_at': archived ? '2026-09-28T18:00:00.000+03:00' : null,
  'logged_days_count': 12,
  'completed_days_count': 10,
  'tracked_by_goals': [
    {'id': 6667, 'name': 'Maraton', 'status': 'active'},
  ],
});

HabitInput _sameAs(Habit h) => HabitInput(
  name: h.name,
  frequency: h.frequency,
  targetCount: h.targetCount,
  color: h.color,
  description: h.description,
  goalId: h.goalId,
);

Goal _goal({Map<String, dynamic> extra = const {}}) =>
    Goal.fromJson({...goalJson(), ...extra});

GoalInput _goalInput(Goal g, {String? name, String? related, num? target}) =>
    GoalInput(
      name: name ?? g.name,
      description: g.description,
      targetType: g.targetType,
      color: g.color,
      unit: g.unit,
      deadline: g.deadline,
      targetValue: target ?? g.targetValue,
      related: related ?? g.relatedRef,
      currentValue: g.currentValue,
    );

/// A long entry, as the web wrote it: paragraphs, line breaks, a list.
final _longBody = [
  for (var i = 0; i < 20; i++) 'Paragraf $i: ${'kelime ' * 12}'.trim(),
].join('\n\n');

JournalEntry _entry({String? body, String format = 'plain'}) =>
    JournalEntry.fromJson({
      ...journalEntryJson(),
      'body_plain': body ?? _longBody,
      'body_text': body ?? _longBody,
      'body_format': format,
      'body_formatting': format == 'rich' ? ['bold', 'list'] : <String>[],
      'tags': ['aile', 'yürüyüş'],
      'gratitude': 'Kahve',
      'updated_at': '2026-10-04T12:30:00.000+03:00',
    });

JournalInput _journalInput(JournalEntry e, {String? title, String? body}) =>
    JournalInput(
      date: e.date,
      title: title ?? e.title,
      bodyText: body ?? e.editableBody,
      mood: e.mood,
      weather: e.weather,
      energyLevel: e.energyLevel,
      gratitude: e.gratitude,
      tags: e.tags,
    );

void main() {
  group('Habit', () {
    test('reads the archive, start and detail keys', () {
      final h = _habit(archived: true);
      expect(h.archived, isTrue);
      expect(h.archivedAt, DateTime(2026, 9, 28, 18));
      expect(h.startDate, DateTime(2026, 9, 20));
      expect(h.loggedDaysCount, 12);
      expect(h.completedDaysCount, 10);
      expect(h.trackedByGoals!.single.name, 'Maraton');
      // A list item has no detail keys.
      expect(Habit.fromJson(habitJson()).trackedByGoals, isNull);
    });

    test('a day can be logged from its start through today, never on an '
        'archived habit', () {
      final h = _habit();
      expect(h.canLog(DateTime(2026, 10, 4)), isTrue);
      expect(h.canLog(DateTime(2026, 9, 20)), isTrue);
      expect(
        h.canLog(DateTime(2026, 9, 19)),
        isFalse,
        reason: 'before_habit_start',
      );
      expect(h.canLog(DateTime(2026, 10, 5)), isFalse, reason: 'future_date');
      expect(_habit(archived: true).canLog(DateTime(2026, 10, 3)), isFalse);
      expect(
        _habit(startDate: null).canLog(DateTime(2020)),
        isTrue,
        reason: 'an older server: the server decides',
      );
    });

    test(
      'a past day set to a count shows in the chain, today in its block',
      () {
        final su = Habit.fromJson(habitJson(id: 8, name: 'Su', targetCount: 3));
        expect(su.countOn(DateTime(2026, 10, 3)), 1, reason: 'partial 1/3');
        final done = su.withDayCount(DateTime(2026, 10, 3), 3);
        expect(done.chain.first.status, ChainStatus.completed);
        expect(done.countOn(DateTime(2026, 10, 3)), 3);
        final cleared = su.withDayCount(DateTime(2026, 10, 3), 0);
        expect(cleared.chain.first.status, ChainStatus.missed);
        final today = su.withDayCount(DateTime(2026, 10, 4), 2);
        expect(today.today.count, 2);
        expect(today.chain.last.status, ChainStatus.partial);
      },
    );

    test('an edit sends only what changed', () {
      final h = _habit();
      expect(_sameAs(h).changesFrom(h), isEmpty);
      expect(
        HabitInput(
          name: 'Sabah koşusu',
          frequency: h.frequency,
          targetCount: h.targetCount,
          // Colours compare whatever their case.
          color: '#4A90D9',
          description: h.description,
          goalId: h.goalId,
        ).changesFrom(h),
        {'name': 'Sabah koşusu'},
      );
    });

    test('a description written on the web and the goal it serves stay '
        'unless the form changed them; clearing them sends null', () {
      final h = _habit();
      final cleared = HabitInput(
        name: h.name,
        frequency: h.frequency,
        targetCount: 2,
        color: h.color,
        description: '  ',
        goalId: null,
      ).changesFrom(h);
      expect(cleared, {
        'target_count': 2,
        'description': null,
        'goal_id': null,
      });
    });

    test('a new habit sends every field', () {
      expect(
        const HabitInput(
          name: 'Su',
          frequency: 'daily',
          targetCount: 3,
          color: '#D4A853',
          description: '',
        ).toJson(),
        {
          'name': 'Su',
          'frequency': 'daily',
          'target_count': 3,
          'color': '#D4A853',
          'description': null,
          'goal_id': null,
        },
      );
    });
  });

  group('Goal', () {
    test('reads progress_source, a null days_remaining and its link', () {
      final g = _goal();
      expect(g.daysRemaining, isNull, reason: 'no deadline is not 0 days');
      expect(g.progressSource, 'manual');
      expect(g.isManual, isTrue);
      expect(g.relatedRef, 'none');
      final linked = _goal(
        extra: {
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
        },
      );
      expect(linked.relatedRef, 'Account-1');
      expect(linked.isManual, isFalse);
      // An older server without progress_source.
      final old = Goal.fromJson({
        ...goalJson(),
        'target_type': 'habit',
        'related': {'type': 'Habit', 'id': 7, 'name': 'Koşu'},
      });
      expect(old.progressSource, 'habit');
    });

    test('an edit never sends the link it did not change — so it never '
        'unlinks the goal', () {
      final linked = _goal(
        extra: {
          'target_type': 'habit',
          'progress_source': 'habit',
          'related': {'type': 'Habit', 'id': 7, 'name': 'Koşu'},
        },
      );
      expect(_goalInput(linked).changesFrom(linked), isEmpty);
      expect(_goalInput(linked, name: 'Maraton').changesFrom(linked), {
        'name': 'Maraton',
      });
      expect(_goalInput(linked, related: 'Habit-8').changesFrom(linked), {
        'related': 'Habit-8',
      });
      // Unlinked, it is logged by hand: the progress the form shows (and
      // may have changed) goes with it.
      expect(_goalInput(linked, related: 'none').changesFrom(linked), {
        'related': 'none',
        'current_value': linked.currentValue,
      });
    });

    test('a goal that becomes manual sends the progress typed for it', () {
      final linked = _goal(
        extra: {
          'target_type': 'habit',
          'progress_source': 'habit',
          'related': {'type': 'Habit', 'id': 7, 'name': 'Koşu'},
        },
      );
      final unlinked = GoalInput(
        name: linked.name,
        targetType: 'habit',
        color: linked.color,
        unit: linked.unit,
        targetValue: linked.targetValue,
        related: 'none',
        currentValue: 5,
      );
      expect(unlinked.changesFrom(linked), {
        'related': 'none',
        'current_value': 5,
      });
      final financial = _goal(
        extra: {'target_type': 'financial', 'progress_source': 'income'},
      );
      final custom = GoalInput(
        name: financial.name,
        targetType: 'custom',
        color: financial.color,
        unit: financial.unit,
        targetValue: financial.targetValue,
        currentValue: 3,
      );
      expect(custom.changesFrom(financial), {
        'target_type': 'custom',
        'current_value': 3,
      });
    });

    test('a computed goal never sends its progress back', () {
      final linked = _goal(
        extra: {'target_type': 'financial', 'progress_source': 'income'},
      );
      final input = GoalInput(
        name: linked.name,
        targetType: linked.targetType,
        color: linked.color,
        unit: linked.unit,
        targetValue: linked.targetValue,
        currentValue: 999,
      );
      expect(input.changesFrom(linked), isNot(contains('current_value')));
    });

    test('a deadline set or cleared; a new goal leaves an empty unit to the '
        'server', () {
      final g = _goal();
      final withDeadline = GoalInput(
        name: g.name,
        targetType: g.targetType,
        color: g.color,
        unit: g.unit,
        targetValue: g.targetValue,
        deadline: DateTime(2027, 6, 1),
      );
      expect(withDeadline.changesFrom(g), {'deadline': '2027-06-01'});
      final dated = _goal(extra: {'deadline': '2027-06-01'});
      expect(_goalInput(dated).changesFrom(dated), isEmpty);
      expect(
        GoalInput(
          name: g.name,
          targetType: g.targetType,
          color: g.color,
          unit: g.unit,
          targetValue: g.targetValue,
        ).changesFrom(dated),
        {'deadline': null},
      );
      final created = const GoalInput(
        name: 'Tatil',
        targetType: 'financial',
        color: '#D4A853',
        unit: '',
        targetValue: 20000,
        related: 'Account-1',
      ).toJson();
      expect(created.containsKey('unit'), isFalse);
      expect(created['related'], 'Account-1');
      // Any other goal without a unit has none — not the user's currency.
      for (final type in ['custom', 'habit']) {
        final json = GoalInput(
          name: '10 kitap',
          targetType: type,
          color: '#D4A853',
          unit: '  ',
          targetValue: 10,
        ).toJson();
        expect(json.containsKey('unit'), isTrue, reason: type);
        expect(json['unit'], isNull, reason: type);
      }
    });
  });

  group('JournalEntry and JournalInput', () {
    test('the full entry is edited from its whole body_text', () {
      final e = _entry();
      expect(e.isFull, isTrue);
      expect(e.editableBody, _longBody);
      expect(e.editableBody.length, greaterThan(1000));
      expect(e.updatedAt, DateTime(2026, 10, 4, 12, 30));
      final rich = _entry(format: 'rich');
      expect(rich.isRich, isTrue);
      expect(rich.bodyFormatting, ['bold', 'list']);
      // A list item is a preview, never edited.
      expect(
        JournalEntry.fromJson({
          'id': 1,
          'date': '2026-10-04',
          'body_plain': 'Kısa...',
          'tags': const [],
          'has_gratitude': false,
        }).isFull,
        isFalse,
      );
    });

    test('a new entry sends its body as plain text (body_text), never as '
        'HTML, byte for byte', () {
      final body = '${'Uzun bir gün <3 & '}${'x' * 2000}\n\nİkinci paragraf.';
      final json = JournalInput(
        date: DateTime(2026, 10, 4),
        bodyText: body,
      ).toJson();
      expect(json['body_text'], body);
      expect(json.containsKey('body'), isFalse);
    });

    test('an edit of the title, mood or tags leaves the body out, so web '
        'formatting stays', () {
      final e = _entry(format: 'rich');
      final changes = _journalInput(e, title: 'Yeni başlık').changesFrom(e);
      expect(changes, {'title': 'Yeni başlık'});
      expect(_journalInput(e).changesFrom(e), isEmpty);
    });

    test('the body counts as unchanged the way the server compares it', () {
      final e = _entry(body: 'Bir.\n\nİki.');
      // CRLF, spaces at line ends, blank space around the text, NBSP.
      expect(
        _journalInput(e, body: '  Bir. \r\n\r\nİki. \n').bodyChangedFrom(e),
        isFalse,
      );
      expect(_journalInput(e, body: 'Bir.\nİki.').bodyChangedFrom(e), isTrue);
    });

    test('a changed body is sent whole, with discard_formatting only when '
        'asked', () {
      final e = _entry(format: 'rich');
      final edited = '$_longBody\n\nYeni paragraf.';
      expect(_journalInput(e, body: edited).changesFrom(e), {
        'body_text': edited,
      });
      expect(
        _journalInput(e, body: edited).changesFrom(e, discardFormatting: true),
        {'body_text': edited, 'discard_formatting': true},
      );
    });
  });
}
