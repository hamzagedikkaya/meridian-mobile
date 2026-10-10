/// The todo, todo-list and event endpoints of contract G3 (§8–§10) through
/// the real repository: what each read asks for, what each write sends (an
/// edit only the keys it changes), and how the answers parse; then the todo
/// tick across every list on screen. (What each write refreshes is in
/// sync_test.dart.)
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/data/actions.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/repository.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/todo.dart';

import '../support/fake_api.dart';
import '../support/read_models.dart';

void main() {
  late FakeApi api;
  late ProviderContainer container;
  late MeridianRepository repo;

  /// The query of every request to [key] so far.
  final queries = <String, List<Map<String, dynamic>>>{};
  void recordQueries(String key, Object? Function(RequestOptions) answer) {
    api.onRequest(key, (request) {
      queries.putIfAbsent(key, () => []).add(request.queryParameters);
      return answer(request);
    });
  }

  setUp(() {
    api = FakeApi();
    container = containerFor(api);
    repo = container.read(repositoryProvider);
    queries.clear();
  });

  group('todos', () {
    test('a filter asks with its list (or none), order and page', () async {
      recordQueries('GET /todos', (_) => {
            'todos': [todoJson()],
            'meta': {
              'open_count': 1,
              'overdue_count': 1,
              'total_count': 1,
              'counts': {'open': 1, 'today': 1},
            },
          });
      final bundle = await repo.fetchTodos(
        filter: 'upcoming',
        listId: 5,
        sort: 'due',
      );
      expect(queries['GET /todos']!.last,
          {'filter': 'upcoming', 'list_id': 5, 'sort': 'due'});
      expect(bundle.counts['today'], 1);

      await repo.fetchTodos(filter: 'open', unlisted: true, listId: 5);
      expect(queries['GET /todos']!.last['list_id'], 'none',
          reason: 'no list wins over a list');

      await repo.fetchTodos(filter: 'done', sort: 'completed', perPage: 100);
      expect(queries['GET /todos']!.last,
          {'filter': 'done', 'sort': 'completed', 'page': 1, 'per_page': 100});
    });

    test('the read model asks as its query says', () async {
      recordQueries('GET /todos', (_) => {
            'todos': const [],
            'meta': const {'open_count': 0, 'overdue_count': 0},
          });
      await container.read(
          todosProvider(const TodoQuery(filter: 'undated', listId: 5)).future);
      expect(queries['GET /todos']!.single,
          {'filter': 'undated', 'list_id': 5, 'sort': 'created'});
    });

    test('a create sends the day as due_date: a date-only due', () async {
      final saved = await repo.createTodo(TodoInput(
        title: 'Faturayı öde',
        dueDate: DateTime(2026, 10, 4),
        listId: 5,
      ));
      expect(api.bodiesOf('POST /todos').single, {
        'title': 'Faturayı öde',
        'priority': 'medium',
        'due_date': '2026-10-04',
        'todo_list_id': 5,
      });
      expect(saved.id, 40);
    });

    test('an edit sends only what changed', () async {
      final before = Todo.fromJson(todoJson());
      await repo.updateTodo(
        before,
        TodoInput(
          title: 'Faturayı öde',
          priority: 'high',
          dueDate: DateTime(2026, 10, 4),
          dueTime: '18:00',
          body: 'Elektrik',
        ),
      );
      expect(api.bodiesOf('PATCH /todos/39').single, {'body': 'Elektrik'});
    });

    test('postponing sends the new day alone, so the time stays', () async {
      await repo.postponeTodo(39, DateTime(2026, 10, 5));
      expect(api.bodiesOf('PATCH /todos/39').single, {'due_date': '2026-10-05'});
    });

    test('a delete answers 204', () async {
      await repo.deleteTodo(39);
      expect(api.requests, contains('DELETE /todos/39'));
    });

    test('a refusal names the field it is about', () async {
      api.on('POST /todos', {
        'errors': {
          'due_time': ['due_time için geçersiz değer.'],
        },
        'code': 'invalid_parameter',
        'param': 'due_time',
      }, status: 422);
      await expectLater(
        repo.createTodo(const TodoInput(title: 'x')),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'invalid_parameter')
            .having((e) => e.param, 'param', 'due_time')),
      );
    });
  });

  group('todo lists', () {
    test('the lists and the todos in no list', () async {
      final bundle = await repo.fetchTodoLists();
      expect(bundle.lists.single.name, 'Ev');
      expect(bundle.unlistedOpenCount, 1);
    });

    test('a create sends the name and colour; an edit only what changed',
        () async {
      final made = await repo
          .createTodoList(const TodoListInput(name: ' İş ', color: '#6B8FA0'));
      expect(api.bodiesOf('POST /todo_lists').single,
          {'name': 'İş', 'color': '#6B8FA0'});
      expect(made.id, 6);

      await repo.updateTodoList(
        TodoList.fromJson(todoListJson()),
        const TodoListInput(name: 'Ev', color: '#D4A574'),
      );
      expect(api.bodiesOf('PATCH /todo_lists/5').single, {'color': '#D4A574'});
    });

    test('a delete says what becomes of its todos', () async {
      final keys = <Map<String, dynamic>>[];
      api.onRequest('DELETE /todo_lists/5', (request) {
        keys.add(request.uri.queryParameters);
        return null;
      });
      await repo.deleteTodoList(5, keepTodos: true);
      await repo.deleteTodoList(5, keepTodos: false);
      expect(keys, [
        {'todos': 'keep'},
        {'todos': 'delete'},
      ]);
    });
  });

  group('events', () {
    test('a window asks for its days, both included', () async {
      recordQueries('GET /events', (_) => {
            'events': [
              eventJson(recurring: true, occurrences: ['2026-10-04', '2026-10-11']),
            ],
          });
      final window = EventWindow(DateTime(2026, 10, 4), DateTime(2026, 10, 11));
      final events = (await container.read(eventsProvider(window).future)).data;
      expect(queries['GET /events']!.single,
          {'from': '2026-10-04', 'to': '2026-10-11'});
      expect(events.single.occurrences, hasLength(2));
    });

    test('the detail is the full event', () async {
      final event = await repo.fetchEvent(12);
      expect(event.description, 'Mat getir');
      expect(event.recurrenceRule, isNull);
    });

    test('a create sends the wall clock; an edit only what changed', () async {
      await repo.createEvent(EventInput(
        title: 'Dişçi',
        start: DateTime(2026, 10, 5, 15),
        end: DateTime(2026, 10, 5, 16),
      ));
      expect(api.bodiesOf('POST /events').single, {
        'title': 'Dişçi',
        'start_at': '2026-10-05T15:00',
        'end_at': '2026-10-05T16:00',
        'all_day': false,
        'color': '#B8860B',
        'event_type': 'personal',
      });

      final before = Event.fromJson(eventJson(full: true));
      await repo.updateEvent(
        before,
        EventInput(
          title: 'Yoga',
          start: DateTime(2026, 10, 4, 18),
          end: DateTime(2026, 10, 4, 19),
          location: 'Park',
          description: 'Mat getir',
          color: '#6B8E5A',
          eventType: 'health',
        ),
      );
      expect(api.bodiesOf('PATCH /events/12').single, {'location': 'Park'});
    });

    test('"this and following" ends the series the day before', () async {
      final series = Event.fromJson(eventJson(recurring: true, full: true));
      await repo.endSeries(series, DateTime(2026, 10, 10));
      expect(api.bodiesOf('PATCH /events/12').single,
          {'recurrence_rule': 'FREQ=WEEKLY;UNTIL=20261010'});
    });

    test('a refusal of the end says so on the end', () async {
      api.on('POST /events', {
        'errors': {
          'end_at': ['Bitiş başlangıçtan sonra olmalı'],
        },
        'code': 'validation_failed',
        'details': {
          'end_at': [
            {'error': 'must_be_after_start'},
          ],
        },
      }, status: 422);
      try {
        await repo.createEvent(EventInput(title: 'x', start: DateTime(2026)));
        fail('refused');
      } on ApiException catch (e) {
        expect(e.details['end_at']!.single.error, 'must_be_after_start');
      }
    });
  });

  group('a todo ticked off shows on every list at once', () {
    test('Today and each list that shows it; undone, it goes back into the '
        'lists that take it', () async {
      const today = TodoQuery(filter: 'today');
      const done = TodoQuery(filter: 'done');
      await showEverything(container, api);
      container.listen(todosProvider(done), (_, _) {});
      await settle(api);
      api.hold('PATCH /todos/39/toggle');

      final actions = container.read(todoActionsProvider);
      final tick = actions.setDone(39, done: true);
      expect(
        container.read(todosProvider(today)).value!.data.todos.single.isDone,
        isTrue,
        reason: 'before the server answers',
      );
      expect(container.read(homeProvider).value!.data.upcomingTodos.single.isDone,
          isTrue);
      api.release('PATCH /todos/39/toggle');
      await tick;

      // The refetch dropped it from the open lists.
      api.on('GET /todos', {
        'todos': const [],
        'meta': const {'open_count': 0, 'overdue_count': 0},
      });
      await settle(api);
      expect(container.read(todosProvider(today)).value!.data.todos, isEmpty);

      api.hold('PATCH /todos/39/toggle');
      final todo = Todo.fromJson(todoJson(status: 'done'));
      final undo = actions.setDone(39, done: false, restore: (todo: todo, index: 0));
      expect(
        container.read(todosProvider(today)).value!.data.todos.single.isOpen,
        isTrue,
        reason: 'back in today\'s list at once',
      );
      expect(container.read(todosProvider(done)).value!.data.todos, isEmpty,
          reason: 'the finished list takes no open todo');
      api.release('PATCH /todos/39/toggle');
      await undo;
    });

    test('undone, a todo Today would not list is not put on Today',
        () async {
      await showEverything(container, api);
      final undated = Todo.fromJson({
        ...todoJson(id: 41, status: 'done'),
        'due_at': null,
        'due_date': null,
        'due_time': null,
      });
      api.hold('PATCH /todos/41/toggle');
      final undo = container
          .read(todoActionsProvider)
          .setDone(41, done: false, restore: (todo: undated, index: 0));
      expect(
        container
            .read(homeProvider)
            .value!
            .data
            .upcomingTodos
            .map((t) => t.id),
        [39],
      );
      api.release('PATCH /todos/41/toggle');
      await undo;
    });

    test('a refused tick is taken back everywhere', () async {
      const today = TodoQuery(filter: 'today');
      await showEverything(container, api);
      api.fail('PATCH /todos/39/toggle', 422);
      await expectLater(
        container.read(todoActionsProvider).setDone(39, done: true),
        throwsA(isA<ApiException>()),
      );
      expect(
        container.read(todosProvider(today)).value!.data.todos.single.isDone,
        isFalse,
      );
    });
  });
}
