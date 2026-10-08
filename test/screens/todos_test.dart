/// The Todos screen, the todo sheet and the lists page (contract §8–§9):
/// filters and lists ask the server, a tick and a swipe send an explicit
/// state, a swipe to the left deletes with "Geri al", a tap edits and an
/// edit sends only what changed, and a list's delete says what becomes of
/// its todos.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/ui/screens/todos/todo_sheet.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/color_swatches.dart';
import 'package:meridian_mobile/ui/widgets/offline_banner.dart';

import '../support/app_harness.dart';
import '../support/fake_api.dart';
import '../support/semantics.dart';

const _toggle = 'PATCH /todos/39/toggle';

/// `GET /todos` that records each query and answers [todos] with counts.
List<Map<String, dynamic>> _recordTodos(
  FakeApi api, {
  List<Map<String, dynamic>>? todos,
}) {
  final queries = <Map<String, dynamic>>[];
  api.onRequest('GET /todos', (RequestOptions request) {
    queries.add(request.queryParameters);
    return {
      'todos': todos ?? [todoJson()],
      'meta': const {
        'open_count': 3,
        'overdue_count': 1,
        'total_count': 1,
        'counts': {
          'open': 3,
          'today': 1,
          'upcoming': 2,
          'overdue': 1,
          'undated': 1,
          'done': 4,
        },
      },
    };
  });
  return queries;
}

/// [api], except that the requests [gone] picks are answered 404
/// `not_found` — a record deleted elsewhere.
class _Gone implements HttpClientAdapter {
  final FakeApi api;
  final bool Function(RequestOptions request) gone;

  _Gone(this.api, this.gone);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!gone(options)) {
      return api.fetch(options, requestStream, cancelFuture);
    }
    api.requests.add('${options.method} ${options.uri.path}');
    return ResponseBody.fromString(
      jsonEncode({'error': 'Bulunamadı', 'code': 'not_found'}),
      404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Finder _row(int id) => find.byKey(ValueKey('todo-$id'));

Finder _checkbox(int id) =>
    find.descendant(of: _row(id), matching: find.byType(CheckPop));

void main() {
  setUpAll(initializeDateFormatting);

  group('the Todos screen', () {
    testWidgets('lists under day headings, with each filter\'s count; a '
        'filter and a list ask the server', (tester) async {
      final api = FakeApi();
      final queries = _recordTodos(api, todos: [
        todoJson(),
        {
          ...todoJson(id: 41),
          'title': 'Süt al',
          'due_at': null,
          'due_date': null,
          'due_time': null,
          'overdue': false,
          'todo_list': {'id': 5, 'name': 'Ev', 'color': '#6B8E5A'},
        },
      ]);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      expect(queries.single, {'filter': 'open', 'sort': 'due'});
      expect(find.text('Gecikmiş'), findsWidgets, reason: 'the overdue group');
      expect(find.text('Tarihsiz'), findsWidgets, reason: 'the undated group');
      expect(find.text('Faturayı öde'), findsOneWidget);
      expect(find.text('Bugün · 18:00'), findsOneWidget,
          reason: 'the due day and its time');
      expect(find.text('Süt al'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Yaklaşan'));
      await settleFrames(tester);
      expect(queries.last, {'filter': 'upcoming', 'sort': 'due'});

      // The list chips come from GET /todo_lists.
      await tester.tap(find.text('Ev').first);
      await settleFrames(tester);
      expect(queries.last,
          {'filter': 'upcoming', 'list_id': 5, 'sort': 'due'});

      await tester.tap(find.text('Listesiz'));
      await settleFrames(tester);
      expect(queries.last['list_id'], 'none');

      await tester.ensureVisible(find.text('Tamamlanan'));
      await settleFrames(tester);
      await tester.tap(find.text('Tamamlanan'));
      await settleFrames(tester);
      expect(queries.last, {
        'filter': 'done',
        'list_id': 'none',
        'sort': 'completed',
        'page': 1,
        'per_page': 100,
      });
    });

    testWidgets('the checkbox ticks it off with done=true; "Geri al" sends '
        'done=false', (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      await tester.tap(_checkbox(39));
      await tester.pump();
      expect(find.text('“Faturayı öde” tamamlandı'), findsOneWidget);
      await settleFrames(tester);
      expect(api.bodiesOf(_toggle).single, {'done': true});

      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(api.bodiesOf(_toggle).last, {'done': false});
      await tester.pumpAndSettle();
    });

    testWidgets('a swipe to the right ticks it off; to the left deletes it, '
        'with "Geri al" — undone, nothing is sent', (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      await tester.drag(_row(39), const Offset(600, 0));
      await settleFrames(tester);
      expect(api.bodiesOf(_toggle).single, {'done': true});
      expect(_row(39), findsOneWidget, reason: 'it stays until the refetch');
      await tester.pumpAndSettle();

      await tester.drag(_row(39), const Offset(-600, 0));
      await settleFrames(tester);
      expect(_row(39), findsNothing, reason: 'gone at once');
      // ignore: avoid_print
      // The tick's snackbar makes way for this one.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('“Faturayı öde” silindi'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(_row(39), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /todos/39')));

      await tester.pumpAndSettle();
      await tester.drag(_row(39), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(_row(39), findsNothing);
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /todos/39'));
    });

    testWidgets('screen readers get the swipes and the long press as the '
        'row\'s actions', (tester) async {
      final handle = tester.ensureSemantics();
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      final row = tester.getSemantics(_row(39));
      expect(row.label, 'Faturayı öde, Bugün · 18:00, gecikmiş');
      expect(customActionLabels(row),
          containsAll(['Tamamla', 'Yarına ertele', 'Sil']));
      performCustomAction(row, 'Yarına ertele');
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').single,
          {'due_date': '2026-10-05'});
      await tester.pumpAndSettle();
      handle.dispose();
    });

    testWidgets('a long press moves it to tomorrow, keeping its time',
        (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      await tester.longPress(find.text('Faturayı öde'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yarına ertele'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').single,
          {'due_date': '2026-10-05'});
      expect(find.text('“Faturayı öde” yarına ertelendi'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('a tap edits it, and the edit sends only what changed',
        (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      await tester.tap(find.text('Faturayı öde'));
      await tester.pumpAndSettle();
      expect(find.text('Görevi düzenle'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Faturayı öde'), 'Faturaları öde');
      await tester.tap(find.text('Yarın'));
      await tester.tap(find.text('Acil'));
      await tester.pump();
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').single, {
        'title': 'Faturaları öde',
        'priority': 'urgent',
        'due_date': '2026-10-05',
        'due_time': '18:00',
      });
      expect(find.text('Görevi düzenle'), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('a todo added under "Bugün" is due today; a missing title is '
        'said in place and nothing is sent', (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos?filter=today');

      await tester.tap(find.text('Görev'));
      await tester.pumpAndSettle();
      expect(find.text('Yeni görev'), findsOneWidget);
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      expect(find.text('Bir başlık yaz'), findsOneWidget);
      expect(api.bodiesOf('POST /todos'), isEmpty);

      await tester.enterText(find.byType(TextField).first, 'Süt al');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /todos').single, {
        'title': 'Süt al',
        'priority': 'medium',
        'due_date': '2026-10-04',
      });
      await tester.pumpAndSettle();
    });

    testWidgets('"Kaydet ve yeni" saves and clears the sheet for the next one, '
        'keeping its day and list', (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api,
          initialLocation: '/todos?filter=upcoming&list=5');

      await tester.tap(find.text('Görev'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Süt al');
      await tester.tap(find.text('Kaydet ve yeni'));
      await settleFrames(tester);
      await tester.enterText(find.byType(TextField).first, 'Ekmek al');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /todos'), [
        {
          'title': 'Süt al',
          'priority': 'medium',
          'due_date': '2026-10-05',
          'todo_list_id': 5,
        },
        {
          'title': 'Ekmek al',
          'priority': 'medium',
          'due_date': '2026-10-05',
          'todo_list_id': 5,
        },
      ]);
      await tester.pumpAndSettle();
    });

    testWidgets('a time can be added to the day, and taken off again', (
      tester,
    ) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(
        tester,
        api,
        home: opener((context) => openTodoSheet(context, due: fixtureNow)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Dişçi');
      await tester.tap(find.text('Saat ekle'));
      await tester.pumpAndSettle();
      // Typed rather than dialled.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.descendant(
          of: find.byType(Dialog), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), '09');
      await tester.enterText(fields.at(1), '30');
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(find.text('09:30'), findsOneWidget);

      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /todos').single, {
        'title': 'Dişçi',
        'priority': 'medium',
        'due_date': '2026-10-04',
        'due_time': '09:30',
      });
      await tester.pumpAndSettle();
    });

    testWidgets('closing a sheet with changes asks first', (tester) async {
      final api = FakeApi();
      await pumpWithRoutes(
        tester,
        api,
        home: opener((context) => openTodoSheet(context)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Yarım kalan');
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      expect(find.text('Değişiklikleri at'), findsOneWidget);
      await tester.tap(find.text('Değişiklikleri at'));
      await tester.pumpAndSettle();
      expect(find.text('Yeni görev'), findsNothing);
      expect(api.bodiesOf('POST /todos'), isEmpty);
    });

    testWidgets('a server refusal of the time is said under the day', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('POST /todos', {
          'errors': {
            'due_time': ['due_time için geçersiz değer.'],
          },
          'code': 'invalid_parameter',
          'param': 'due_time',
        }, status: 422);
      await pumpWithRoutes(
        tester,
        api,
        home: opener((context) => openTodoSheet(context, due: fixtureNow)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'x');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(find.text('Sunucu bir değeri kabul etmedi (Son tarih)'),
          findsOneWidget);
      expect(find.text('Yeni görev'), findsOneWidget, reason: 'still open');
    });
    testWidgets('a list deleted on the lists page is no filter any more: '
        'back to every list, with no offline banner', (tester) async {
      final api = FakeApi();
      final queries = _recordTodos(api);
      var deleted = false;
      api.dio.httpClientAdapter = _Gone(
        api,
        (request) =>
            deleted &&
            request.uri.path.endsWith('/todos') &&
            request.uri.queryParameters['list_id'] == '5',
      );
      final router =
          await pumpWithRoutes(tester, api, initialLocation: '/todos?list=5');
      expect(queries.last['list_id'], 5);

      await tester.tap(find.byTooltip('Listeleri yönet'));
      await tester.pumpAndSettle();
      api.on('GET /todo_lists', {
        'todo_lists': <Object>[],
        'meta': const {'unlisted_open_count': 1},
      });
      deleted = true;
      await tester.tap(find.byTooltip('Listeyi düzenle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Görevler listesiz kalsın'));
      await settleFrames(tester);
      router.pop();
      await settleFrames(tester);

      expect(queries.last.containsKey('list_id'), isFalse,
          reason: 'every list again');
      expect(find.byType(OfflineBanner), findsNothing);
      expect(find.textContaining('Çevrimdışı'), findsNothing);
      expect(find.text('Faturayı öde'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('a list the server no longer has (404) drops the filter, '
        'with no offline banner', (tester) async {
      final api = FakeApi()
        // The lists as last read still have it: only the 404 tells.
        ..on('GET /todo_lists', {
          'todo_lists': [todoListJson(), todoListJson(id: 8, name: 'İş')],
          'meta': const {'unlisted_open_count': 1},
        });
      final queries = _recordTodos(api);
      api.dio.httpClientAdapter = _Gone(
        api,
        (request) =>
            request.uri.path.endsWith('/todos') &&
            request.uri.queryParameters['list_id'] == '8',
      );
      await pumpWithRoutes(tester, api, initialLocation: '/todos?list=8');
      await settleFrames(tester);
      expect(api.requests.where((r) => r == 'GET /api/v1/todos'), isNotEmpty,
          reason: 'list 8 was asked for, and answered 404');
      expect(queries.last.containsKey('list_id'), isFalse);
      expect(find.byType(OfflineBanner), findsNothing);
      expect(find.text('Faturayı öde'), findsOneWidget);
    });

    testWidgets('a ticked overdue row stays under "Gecikmiş" until the '
        'refetch', (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');
      expect(find.text('Gecikmiş'), findsWidgets);
      api.hold(_toggle);
      await tester.tap(_checkbox(39));
      await tester.pump();
      expect(find.text('Gecikmiş'), findsWidgets);
      expect(find.text('Bugün · 4 Ekim'), findsNothing,
          reason: 'no heading of its due day');
      api.release(_toggle);
      await tester.pumpAndSettle();
    });

    testWidgets('the filter chips carry their tap for screen readers and '
        'switch access', (tester) async {
      final handle = tester.ensureSemantics();
      final api = FakeApi();
      final queries = _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');
      final node = tester.getSemantics(find.bySemanticsLabel(
        RegExp(r'^Yaklaşan'),
      ));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await settleFrames(tester);
      expect(queries.last['filter'], 'upcoming');
      handle.dispose();
    });
  });

  group('large text and English', () {
    for (final locale in const [Locale('tr'), Locale('en')]) {
      testWidgets('the screen and the sheet lay out at 200% ($locale)', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final api = FakeApi();
        _recordTodos(api);
        await pumpWithRoutes(tester, api,
            initialLocation: '/todos', locale: locale);
        expect(tester.takeException(), isNull);
        expect(find.text(locale.languageCode == 'tr' ? 'Görevler' : 'Tasks'),
            findsOneWidget);

        await tester.tap(find.text('Faturayı öde'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text(locale.languageCode == 'tr'
              ? 'Görevi düzenle'
              : 'Edit task'),
          findsOneWidget,
        );
      });
    }
  });

  group('the lists page', () {
    testWidgets('a new list, a renamed one, and a delete that says what '
        'becomes of the todos in it', (tester) async {
      final api = FakeApi();
      await pumpWithRoutes(tester, api, initialLocation: '/todos/lists');
      expect(find.text('Ev'), findsOneWidget);
      expect(find.text('1 açık · 2 görev'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'İş');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /todo_lists').single,
          {'name': 'İş', 'color': rotatingSwatch(1)});
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Listeyi düzenle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ev işleri');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todo_lists/5').single, {'name': 'Ev işleri'});
      await tester.pumpAndSettle();

      final deletes = <Map<String, String>>[];
      api.onRequest('DELETE /todo_lists/5', (request) {
        deletes.add(request.uri.queryParameters);
        return null;
      });
      await tester.tap(find.byTooltip('Listeyi düzenle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('“Ev” listesi silinsin mi?'), findsOneWidget);
      expect(find.textContaining('Bu listede 2 görev var'), findsOneWidget);
      await tester.tap(find.text('Görevler listesiz kalsın'));
      await settleFrames(tester);
      expect(deletes, [
        {'todos': 'keep'},
      ]);
      expect(find.text('“Ev” listesi silindi'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('a list\'s row opens its todos', (tester) async {
      final api = FakeApi();
      final queries = _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos/lists');
      await tester.tap(find.text('Ev'));
      await settleFrames(tester);
      expect(queries.last['list_id'], 5);
    });
  });
}
