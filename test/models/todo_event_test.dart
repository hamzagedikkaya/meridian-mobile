/// The todo, todo-list and event models against the G3 contract (§8–§10):
/// what a create sends, what an edit sends (only what changed), date-only
/// dues, recurrence rules, and where an occurrence falls.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/todo.dart';

import '../support/fake_api.dart';

void main() {
  group('Todo', () {
    test('reads goal_id and tells a date-only due from a timed one', () {
      final timed = Todo.fromJson({...todoJson(), 'goal_id': 6});
      expect(timed.goalId, 6);
      expect(timed.isDateOnly, isFalse);
      expect(timed.dueTime, '18:00');

      final dateOnly = Todo.fromJson({
        ...todoJson(),
        'due_at': '2026-10-04T23:59:59.000+03:00',
        'due_time': null,
      });
      expect(dateOnly.isDateOnly, isTrue);
      expect(dateOnly.dueDay, DateTime(2026, 10, 4));
      expect(Todo.fromJson({...todoJson(), 'due_at': null, 'due_date': null})
          .isDateOnly, isFalse);
    });

    test('is open while pending or in progress', () {
      expect(Todo.fromJson(todoJson()).isOpen, isTrue);
      expect(Todo.fromJson({...todoJson(), 'status': 'in_progress'}).isOpen,
          isTrue);
      expect(Todo.fromJson(todoJson(status: 'done')).isOpen, isFalse);
      expect(Todo.fromJson({...todoJson(), 'status': 'cancelled'}).isOpen,
          isFalse);
    });
  });

  group('TodoInput', () {
    test('a new todo sends its day and time as due_date / due_time, never '
        'an instant, and leaves out what is not set', () {
      expect(
        TodoInput(
          title: '  Faturayı öde ',
          body: '  ',
          dueDate: DateTime(2026, 10, 4, 15, 30),
        ).toJson(),
        {'title': 'Faturayı öde', 'priority': 'medium', 'due_date': '2026-10-04'},
        reason: 'a day without a time is a date-only due',
      );
      expect(
        TodoInput(
          title: 'Dişçi',
          body: 'Randevu',
          priority: 'high',
          dueDate: DateTime(2026, 10, 5),
          dueTime: '09:30',
          listId: 5,
          goalId: 3,
        ).toJson(),
        {
          'title': 'Dişçi',
          'body': 'Randevu',
          'priority': 'high',
          'due_date': '2026-10-05',
          'due_time': '09:30',
          'todo_list_id': 5,
          'goal_id': 3,
        },
      );
      expect(
        const TodoInput(title: 'x', dueTime: '09:30').toJson(),
        {'title': 'x', 'priority': 'medium'},
        reason: 'a time without a day is not sent',
      );
    });

    final before = Todo.fromJson({
      ...todoJson(),
      'body': 'Elektrik',
      'goal_id': 3,
      'todo_list': {'id': 5, 'name': 'Ev', 'color': '#6B8E5A'},
    });
    TodoInput same({
      String title = 'Faturayı öde',
      String? body = 'Elektrik',
      String priority = 'high',
      DateTime? dueDate,
      String? dueTime = '18:00',
      int? listId = 5,
      int? goalId = 3,
      bool noDue = false,
    }) =>
        TodoInput(
          title: title,
          body: body,
          priority: priority,
          dueDate: noDue ? null : (dueDate ?? DateTime(2026, 10, 4)),
          dueTime: dueTime,
          listId: listId,
          goalId: goalId,
        );

    test('an edit sends only what changed', () {
      expect(same().changesFrom(before), isEmpty);
      expect(same(title: 'Faturaları öde').changesFrom(before),
          {'title': 'Faturaları öde'});
      expect(same(body: '').changesFrom(before), {'body': null},
          reason: 'cleared notes are cleared');
      expect(same(priority: 'urgent').changesFrom(before),
          {'priority': 'urgent'});
      expect(same(listId: null).changesFrom(before), {'todo_list_id': null},
          reason: 'out of its list, nothing else touched');
      expect(same(goalId: null).changesFrom(before), {'goal_id': null});
    });

    test('a new day goes with its time (null for none); a new time on the '
        'same day alone; no day clears the due', () {
      expect(same(dueDate: DateTime(2026, 10, 9)).changesFrom(before),
          {'due_date': '2026-10-09', 'due_time': '18:00'});
      expect(
        same(dueDate: DateTime(2026, 10, 9), dueTime: null).changesFrom(before),
        {'due_date': '2026-10-09', 'due_time': null},
      );
      expect(same(dueTime: '08:00').changesFrom(before), {'due_time': '08:00'});
      expect(same(dueTime: null).changesFrom(before), {'due_time': null},
          reason: 'same day, date-only');
      expect(same(noDue: true).changesFrom(before), {'due_date': null});
    });
  });

  test('due times are HH:MM both ways', () {
    expect(dueTimeOf(9, 5), '09:05');
    expect(parseDueTime('18:30'), (hour: 18, minute: 30));
    expect(parseDueTime('24:00'), isNull);
    expect(parseDueTime(null), isNull);
  });

  group('TodosBundle', () {
    test('reads meta counts and the total', () {
      final bundle = TodosBundle.fromJson({
        'todos': [todoJson()],
        'meta': {
          'open_count': 4,
          'overdue_count': 1,
          'total_count': 7,
          'counts': {'open': 4, 'today': 1, 'upcoming': '2'},
        },
      });
      expect(bundle.totalCount, 7);
      expect(bundle.counts, {'open': 4, 'today': 1, 'upcoming': 2});
    });

    test('a tick sets the status and moves the counts; setting it again '
        'changes nothing', () {
      final bundle = TodosBundle.fromJson({
        'todos': [todoJson()],
        'meta': {'open_count': 2, 'overdue_count': 1},
      });
      final done = bundle.withTodoStatus(39, 'done');
      expect(done.todos.single.isDone, isTrue);
      expect(done.openCount, 1);
      expect(done.overdueCount, 0);
      expect(identical(done.withTodoStatus(39, 'done'), done), isTrue);
      expect(identical(bundle.withTodoStatus(99, 'done'), bundle), isTrue);
    });

    test('a reopen puts a dropped todo back where it was', () {
      final bundle = TodosBundle.fromJson({
        'todos': [todoJson(id: 1), todoJson(id: 2)],
        'meta': {'open_count': 2, 'overdue_count': 2},
      });
      final todo = Todo.fromJson(todoJson(status: 'done'));
      final back = bundle.withTodoReopened(todo, index: 1);
      expect(back.todos.map((t) => t.id), [1, 39, 2]);
      expect(back.todos[1].isOpen, isTrue);
      expect(back.openCount, 3);
      expect(back.withTodoReopened(todo, index: 0).todos.map((t) => t.id),
          [1, 39, 2], reason: 'listed already: left in place');
    });
  });

  group('todo lists', () {
    test('reads the list and its counts, and the todos in no list', () {
      final bundle = TodoListsBundle.fromJson({
        'todo_lists': [todoListJson()],
        'meta': {'unlisted_open_count': 2},
      });
      final list = bundle.lists.single;
      expect(list.name, 'Ev');
      expect(list.openCount, 1);
      expect(list.todosCount, 2);
      expect(bundle.unlistedOpenCount, 2);
    });

    test('an edit sends only what changed', () {
      final list = TodoList.fromJson(todoListJson());
      expect(
        const TodoListInput(name: 'Ev', color: '#6b8e5a').changesFrom(list),
        isEmpty,
      );
      expect(
        const TodoListInput(name: ' Ev işleri ', color: '#6B8E5A')
            .changesFrom(list),
        {'name': 'Ev işleri'},
      );
      expect(
        const TodoListInput(name: 'Ev', color: '#D4A574').changesFrom(list),
        {'color': '#D4A574'},
      );
    });
  });

  group('TodoQuery', () {
    final today = DateTime(2026, 10, 4); // a Sunday
    Todo due(DateTime? day, {bool overdue = false, int? list}) => Todo.fromJson({
          ...todoJson(),
          'due_at': null,
          'due_date': day == null
              ? null
              : '${day.year}-${day.month.toString().padLeft(2, '0')}-'
                  '${day.day.toString().padLeft(2, '0')}',
          'overdue': overdue,
          'todo_list': list == null
              ? null
              : {'id': list, 'name': 'Ev', 'color': '#6B8E5A'},
        });

    test('reads in the order its filter calls for', () {
      expect(const TodoQuery(filter: 'done').sort, 'completed');
      expect(const TodoQuery(filter: 'undated').sort, 'position');
      expect(const TodoQuery(filter: 'today').sort, 'due');
      expect(const TodoQuery(filter: 'done').perPage, 100);
      expect(const TodoQuery().perPage, isNull);
    });

    test('takes back an undone tick by the server\'s rules', () {
      expect(const TodoQuery(filter: 'today').admitsOpen(due(today), today),
          isTrue);
      expect(
          const TodoQuery(filter: 'today')
              .admitsOpen(due(DateTime(2026, 10, 5)), today),
          isFalse);
      expect(
          const TodoQuery(filter: 'upcoming')
              .admitsOpen(due(DateTime(2026, 10, 11)), today),
          isTrue);
      expect(
          const TodoQuery(filter: 'upcoming')
              .admitsOpen(due(DateTime(2026, 10, 12)), today),
          isFalse);
      expect(const TodoQuery(filter: 'undated').admitsOpen(due(null), today),
          isTrue);
      expect(
          const TodoQuery(filter: 'overdue')
              .admitsOpen(due(DateTime(2026, 10, 1), overdue: true), today),
          isTrue);
      expect(
          const TodoQuery(filter: 'week')
              .admitsOpen(due(DateTime(2026, 9, 28)), today),
          isTrue,
          reason: 'Monday of this week');
      expect(const TodoQuery(filter: 'done').admitsOpen(due(today), today),
          isFalse);
      expect(const TodoQuery(listId: 5).admitsOpen(due(null, list: 6), today),
          isFalse);
      expect(const TodoQuery(unlisted: true).admitsOpen(due(null), today),
          isTrue);
    });
  });

  group('EventWindow', () {
    test("this week runs from today to Sunday, and at least to tomorrow", () {
      final thursday = EventWindow.thisWeek(DateTime(2026, 10, 1, 15));
      expect(thursday.from, DateTime(2026, 10, 1));
      expect(thursday.to, DateTime(2026, 10, 4));
      final sunday = EventWindow.thisWeek(DateTime(2026, 10, 4));
      expect(sunday.to, DateTime(2026, 10, 5));
      expect(EventWindow.days(DateTime(2026, 10, 4), 30).to,
          DateTime(2026, 11, 2));
      expect(thursday, EventWindow(DateTime(2026, 10, 1), DateTime(2026, 10, 4)));
      // Calendar days, never 24-hour steps (a daylight-saving change).
      expect(
        EventWindow.thisWeek(DateTime(2026, 10, 25)),
        EventWindow(DateTime(2026, 10, 25), DateTime(2026, 10, 26)),
      );
      expect(EventWindow.thisWeek(DateTime(2026, 3, 23)).to,
          DateTime(2026, 3, 29));
    });
  });

  group('Event', () {
    test('reads the full event and its occurrences', () {
      final event = Event.fromJson(eventJson(
        recurring: true,
        full: true,
        occurrences: ['2026-10-04', '2026-10-11'],
      ));
      expect(event.recurring, isTrue);
      expect(event.description, 'Mat getir');
      expect(event.recurrenceRule, 'FREQ=WEEKLY;UNTIL=20261231T205959Z');
      expect(event.occurrences, [DateTime(2026, 10, 4), DateTime(2026, 10, 11)]);
    });

    test('an occurrence starts at the series\' time of day on its own day',
        () {
      final series = Event.fromJson(eventJson(recurring: true));
      final day = DateTime(2026, 10, 11);
      expect(series.occurrenceStart(day), DateTime(2026, 10, 11, 18));
      expect(series.occurrenceEnd(day), DateTime(2026, 10, 11, 19));
      expect(series.minuteOfDay, 18 * 60);
      final allDay = Event.fromJson(eventJson(
        allDay: true,
        start: '2026-10-28T00:00:00.000+03:00',
        end: '2026-10-30T23:59:59.000+03:00',
      ));
      expect(allDay.occurrenceEnd(DateTime(2026, 10, 28)), isNull);
      expect(allDay.minuteOfDay, -1, reason: 'all-day events sort first');
    });
  });

  group('EventInput', () {
    test('a timed event sends the wall clock without an offset', () {
      expect(
        EventInput(
          title: ' Yoga ',
          start: DateTime(2026, 10, 6, 18),
          end: DateTime(2026, 10, 6, 19, 30),
          location: 'Stüdyo',
          description: ' ',
          color: '#6B8E5A',
          eventType: 'health',
          recurrenceRule: 'FREQ=WEEKLY',
        ).toJson(),
        {
          'title': 'Yoga',
          'start_at': '2026-10-06T18:00',
          'end_at': '2026-10-06T19:30',
          'all_day': false,
          'location': 'Stüdyo',
          'color': '#6B8E5A',
          'event_type': 'health',
          'recurrence_rule': 'FREQ=WEEKLY',
        },
      );
    });

    test('an all-day event sends bare dates; a one-day one no end', () {
      expect(
        EventInput(
          title: 'Tatil',
          allDay: true,
          start: DateTime(2026, 10, 28, 9),
          end: DateTime(2026, 10, 30),
        ).toJson(),
        containsPair('end_at', '2026-10-30'),
      );
      final oneDay = EventInput(
        title: 'Doğum günü',
        allDay: true,
        start: DateTime(2026, 10, 28),
        end: DateTime(2026, 10, 28),
      ).toJson();
      expect(oneDay['start_at'], '2026-10-28');
      expect(oneDay.containsKey('end_at'), isFalse);
    });

    final before = Event.fromJson(eventJson(recurring: true, full: true));
    EventInput same({
      String title = 'Yoga',
      DateTime? start,
      DateTime? end,
      bool allDay = false,
      String? rule = 'FREQ=WEEKLY;UNTIL=20261231T205959Z',
      String? description = 'Mat getir',
    }) =>
        EventInput(
          title: title,
          start: start ?? DateTime(2026, 10, 4, 18),
          end: end ?? DateTime(2026, 10, 4, 19),
          allDay: allDay,
          location: 'Stüdyo',
          description: description,
          color: '#6b8e5a',
          eventType: 'health',
          recurrenceRule: rule,
        );

    test('an edit sends only what changed', () {
      expect(same().changesFrom(before), isEmpty);
      expect(same(title: 'Pilates').changesFrom(before), {'title': 'Pilates'});
      expect(same(description: '').changesFrom(before), {'description': null});
      expect(same(rule: null).changesFrom(before), {'recurrence_rule': null},
          reason: 'stopping the repetition');
    });

    test('moving it sends the start and the end together', () {
      expect(
        same(start: DateTime(2026, 10, 4, 19)).changesFrom(before),
        {'start_at': '2026-10-04T19:00', 'end_at': '2026-10-04T19:00'},
      );
      expect(
        same(
          allDay: true,
          start: DateTime(2026, 10, 4),
          end: DateTime(2026, 10, 4),
        ).changesFrom(before),
        {'all_day': true, 'start_at': '2026-10-04', 'end_at': null},
      );
    });
  });

  group('Recurrence', () {
    final tuesday = DateTime(2026, 10, 6, 18);

    test('reads the presets the form offers', () {
      expect(Recurrence.parse(null).preset, RecurrencePreset.none);
      expect(Recurrence.parse('FREQ=DAILY').preset, RecurrencePreset.daily);
      expect(Recurrence.parse('FREQ=WEEKLY;BYDAY=FR,MO,TU,WE,TH').preset,
          RecurrencePreset.weekdays);
      expect(Recurrence.parse('FREQ=WEEKLY', anchor: tuesday).preset,
          RecurrencePreset.weekly);
      expect(Recurrence.parse('FREQ=WEEKLY;BYDAY=TU', anchor: tuesday).preset,
          RecurrencePreset.weekly);
      expect(
          Recurrence.parse('FREQ=WEEKLY;BYDAY=TU,TH', anchor: tuesday).preset,
          RecurrencePreset.custom);
      expect(Recurrence.parse('FREQ=MONTHLY;BYMONTHDAY=6', anchor: tuesday)
          .preset, RecurrencePreset.monthly);
      expect(Recurrence.parse('FREQ=YEARLY').preset, RecurrencePreset.yearly);
      expect(Recurrence.parse('FREQ=DAILY;INTERVAL=2').preset,
          RecurrencePreset.custom);
      expect(Recurrence.parse('rrule:freq=daily;interval=1').preset,
          RecurrencePreset.daily);
    });

    test('reads UNTIL as the account\'s last day, COUNT as a count', () {
      expect(
        Recurrence.parse('FREQ=WEEKLY;UNTIL=20261231T205959Z',
                utcOffset: const Duration(hours: 3))
            .until,
        DateTime(2026, 12, 31),
        reason: 'stored as a UTC instant: 23:59:59 in Istanbul',
      );
      expect(Recurrence.parse('FREQ=DAILY;UNTIL=20261231').until,
          DateTime(2026, 12, 31));
      final counted = Recurrence.parse('FREQ=DAILY;COUNT=10');
      expect(counted.count, 10);
      expect(counted.preset, RecurrencePreset.daily);
    });

    test('builds a rule for a preset, ending on a day', () {
      expect(Recurrence.ruleFor(RecurrencePreset.none), isNull);
      expect(Recurrence.ruleFor(RecurrencePreset.weekly), 'FREQ=WEEKLY');
      expect(
        Recurrence.ruleFor(RecurrencePreset.weekdays,
            until: DateTime(2026, 12, 31)),
        'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;UNTIL=20261231',
      );
    });

    test('builds a rule that ends after a number of times; a day wins', () {
      expect(Recurrence.ruleFor(RecurrencePreset.weekly, count: 10),
          'FREQ=WEEKLY;COUNT=10');
      expect(
        Recurrence.ruleFor(RecurrencePreset.daily,
            until: DateTime(2026, 12, 31), count: 10),
        'FREQ=DAILY;UNTIL=20261231',
      );
    });

    test('the first day a series occurs on: its start, or the next day its '
        'BYDAY names', () {
      final sunday = DateTime(2026, 10, 4);
      expect(Recurrence.firstDay('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', sunday),
          DateTime(2026, 10, 5));
      expect(Recurrence.firstDay('FREQ=DAILY;BYDAY=SA', sunday),
          DateTime(2026, 10, 10));
      expect(Recurrence.firstDay('FREQ=WEEKLY;BYDAY=SU,MO', sunday), sunday);
      expect(Recurrence.firstDay('FREQ=WEEKLY', sunday), sunday);
      expect(Recurrence.firstDay('FREQ=MONTHLY;BYDAY=1MO', sunday), sunday);
      expect(Recurrence.firstDay(null, sunday), sunday);
    });

    test('"this and following" replaces UNTIL or COUNT with the day before',
        () {
      expect(
        Recurrence.endingOn(
            'FREQ=WEEKLY;BYDAY=TU,TH;UNTIL=20261231T205959Z',
            DateTime(2026, 10, 19)),
        'FREQ=WEEKLY;BYDAY=TU,TH;UNTIL=20261019',
      );
      expect(
        Recurrence.endingOn('FREQ=DAILY;COUNT=30', DateTime(2026, 10, 19)),
        'FREQ=DAILY;UNTIL=20261019',
      );
    });
  });
}
