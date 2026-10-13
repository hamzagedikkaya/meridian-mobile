/// The Agenda's todos, the todo sheet and the lists page (contract §8–§9,
/// design-analysis §7.4): views and lists ask the server, a tick and a
/// swipe send an explicit state, a swipe to the left moves to tomorrow
/// with "Geri al", a delete waits for "Geri al", a tap edits and an edit
/// sends only what changed, and a list's delete says what becomes of its
/// todos (keeping them by default).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/ui/screens/agenda/todo_sheet.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/color_swatches.dart';
import 'package:meridian_mobile/ui/widgets/nok_chip.dart';
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

  group('the Agenda\'s todos', () {
    testWidgets('the days ahead under their headings, the inbox and its '
        'count, a list and the finished ones — each asks the server',
        (tester) async {
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
      expect(find.text('Gecikmiş'), findsOneWidget, reason: 'its heading');
      expect(find.text('Gecikmiş · 1'), findsOneWidget, reason: 'its chip');
      expect(find.text('Bugün · 4 Ekim'), findsOneWidget,
          reason: 'today is always there');
      expect(find.text('Faturayı öde'), findsOneWidget);
      expect(find.text('Bugün · 18:00'), findsOneWidget,
          reason: 'the due day and its time');
      expect(find.text('Süt al'), findsNothing,
          reason: 'no date: in the inbox, not in the days ahead');
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Gelen kutusu · 1'));
      await settleFrames(tester);
      expect(queries.last, {'filter': 'undated', 'sort': 'created'});
      expect(find.text('Süt al'), findsOneWidget);

      // The list chip opens a picker of the lists from GET /todo_lists.
      await tester.ensureVisible(find.text('Liste: Tümü'));
      await tester.tap(find.text('Liste: Tümü'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ev').last);
      await settleFrames(tester);
      expect(queries.last,
          {'filter': 'undated', 'list_id': 5, 'sort': 'created'});
      expect(find.text('Liste: Ev'), findsOneWidget);

      await tester.ensureVisible(find.text('Liste: Ev'));
      await tester.tap(find.text('Liste: Ev'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listesiz'));
      await settleFrames(tester);
      expect(queries.last['list_id'], 'none');

      await tester.ensureVisible(find.text('Tamamlanan'));
      await tester.tap(find.text('Tamamlanan'));
      await settleFrames(tester);
      expect(queries.last, {
        'filter': 'done',
        'list_id': 'none',
        'sort': 'completed',
        'page': 1,
        'per_page': 100,
      });
      await tester.pumpAndSettle();
    });

    testWidgets('a view with nothing in it has no chip — never a 0',
        (tester) async {
      final api = FakeApi();
      api.onRequest('GET /todos', (_) => {
            'todos': <Object>[],
            'meta': const {
              'counts': {'open': 0, 'undated': 0, 'overdue': 0, 'done': 2},
            },
          });
      await pumpWithRoutes(tester, api, initialLocation: '/agenda');
      expect(find.textContaining('Gelen kutusu'), findsNothing);
      expect(find.textContaining('Gecikmiş'), findsNothing);
      expect(find.text('Yaklaşan'), findsOneWidget);
      expect(find.text('Önümüzdeki günler sakin'), findsOneWidget);
      expect(find.textContaining('0'), findsNothing);
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

    testWidgets('a swipe to the right ticks it off; to the left moves it to '
        'tomorrow, keeping its time, with "Geri al"', (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      await tester.drag(_row(39), const Offset(600, 0));
      await settleFrames(tester);
      expect(api.bodiesOf(_toggle).single, {'done': true});
      expect(_row(39), findsOneWidget, reason: 'it lingers, ticked off');
      await tester.pumpAndSettle();

      api.hold('PATCH /todos/39');
      await tester.drag(_row(39), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Yarın · 5 Ekim'), findsOneWidget,
          reason: 'on tomorrow at once, before the server answers');
      api.release('PATCH /todos/39');
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').single,
          {'due_date': '2026-10-05'});
      expect(find.text('“Faturayı öde” yarına ertelendi'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').last,
          {'due_date': '2026-10-04', 'due_time': '18:00'});
      await tester.pumpAndSettle();
    });

    testWidgets('a delete from the menu waits for "Geri al": undone, nothing '
        'is sent', (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      await tester.longPress(find.text('Faturayı öde'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(_row(39), findsNothing, reason: 'gone at once');
      expect(find.text('“Faturayı öde” silindi'), findsOneWidget);
      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(_row(39), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /todos/39')));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Faturayı öde'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(_row(39), findsNothing);
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /todos/39'));
    });

    testWidgets('screen readers get the swipes and the menu as the row\'s '
        'actions', (tester) async {
      final handle = tester.ensureSemantics();
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      final row = tester.getSemantics(_row(39));
      expect(row.getSemanticsData().label,
          'Faturayı öde, Bugün · 18:00, gecikmiş, yüksek öncelik');
      expect(customActionLabels(row), containsAll(['Tamamla', 'Yarın', 'Sil']));
      performCustomAction(row, 'Yarın');
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').single,
          {'due_date': '2026-10-05'});
      await tester.pumpAndSettle();
      handle.dispose();
    });

    testWidgets('the menu moves it to tomorrow, keeping its time, and sets '
        'its priority in place', (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      await tester.longPress(find.text('Faturayı öde'));
      await tester.pumpAndSettle();
      expect(find.text('Tarih seç'), findsOneWidget);
      await tester.tap(find.text('Yarına ertele'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').single,
          {'due_date': '2026-10-05'});
      expect(find.text('“Faturayı öde” yarına ertelendi'), findsOneWidget);
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Faturayı öde'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Öncelik'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'a step of the same sheet, not a sheet over it');
      await tester.tap(find.text('Acil'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').last, {'priority': 'urgent'});
      await tester.pumpAndSettle();
    });

    testWidgets('"Hepsini bugüne al" moves every overdue todo to today in '
        'one go; one "Geri al" puts them all back', (tester) async {
      final api = FakeApi();
      _recordTodos(api, todos: [
        {
          ...todoJson(id: 39),
          'due_at': '2026-10-03T09:00:00.000+03:00',
          'due_date': '2026-10-03',
          'due_time': '09:00',
        },
        {
          ...todoJson(id: 42),
          'title': 'Kira',
          'due_at': '2026-10-02T23:59:59.000+03:00',
          'due_date': '2026-10-02',
          'due_time': null,
        },
      ]);
      api.on('PATCH /todos/42', {'todo': todoJson(id: 42)});
      await pumpWithRoutes(tester, api, initialLocation: '/todos');

      await tester.tap(find.text('Hepsini bugüne al'));
      await settleFrames(tester);
      // 09:00 is already past today: the todo is due on the day alone.
      expect(api.bodiesOf('PATCH /todos/39').single,
          {'due_date': '2026-10-04', 'due_time': null});
      expect(api.bodiesOf('PATCH /todos/42').single,
          {'due_date': '2026-10-04'});
      expect(find.text('2 görev bugüne alındı'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').last,
          {'due_date': '2026-10-03', 'due_time': '09:00'});
      expect(api.bodiesOf('PATCH /todos/42').last,
          {'due_date': '2026-10-02', 'due_time': null});
      await tester.pumpAndSettle();
    });

    testWidgets('an inbox todo\'s "Bugün" gives it today', (tester) async {
      final api = FakeApi();
      _recordTodos(api, todos: [
        {
          ...todoJson(id: 41),
          'title': 'Süt al',
          'due_at': null,
          'due_date': null,
          'due_time': null,
          'overdue': false,
        },
      ]);
      api.on('PATCH /todos/41', {'todo': todoJson(id: 41)});
      await pumpWithRoutes(tester, api, initialLocation: '/agenda?view=inbox');
      expect(find.text('Süt al'), findsOneWidget);
      await tester.tap(find.widgetWithText(NokChip, 'Bugün'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/41').single,
          {'due_date': '2026-10-04'});
      expect(find.text('“Süt al” bugüne alındı'), findsOneWidget);
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
      // The test font's wide glyphs make the pill scroll.
      await tester.ensureVisible(find.text('Acil'));
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

    testWidgets('a todo added for today is due today; a missing title is '
        'said in place and nothing is sent', (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(
        tester,
        api,
        home: opener((context) => openTodoSheet(context, due: fixtureNow)),
      );

      await tester.tap(find.text('open'));
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
      await pumpWithRoutes(
        tester,
        api,
        home: opener((context) => openTodoSheet(
              context,
              due: DateTime(2026, 10, 5),
              listId: 5,
            )),
      );

      await tester.tap(find.text('open'));
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

    testWidgets('the list is picked — and a new one made — inside the sheet, '
        'never in a sheet over it', (tester) async {
      final api = FakeApi();
      _recordTodos(api);
      await pumpWithRoutes(
        tester,
        api,
        home: opener((context) => openTodoSheet(context)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Süt al');

      await tester.tap(find.text('Liste'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.text('Yeni liste'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'İş');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      await tester.pumpAndSettle();
      expect(api.bodiesOf('POST /todo_lists').single, containsPair('name', 'İş'));

      // Back on the todo, in the new list.
      expect(find.text('Yeni görev'), findsOneWidget);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /todos').single,
          containsPair('todo_list_id', 6));
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
      await tester.pumpAndSettle();
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

      await tester.tap(find.byTooltip('Diğer seçenekler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listeleri yönet'));
      await tester.pumpAndSettle();
      api.on('GET /todo_lists', {
        'todo_lists': <Object>[],
        'meta': const {'unlisted_open_count': 1},
      });
      deleted = true;
      await tester.tap(find.text('Ev'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Görevleri listesiz bırak'));
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
      expect(find.text('Gecikmiş'), findsOneWidget);
      api.hold(_toggle);
      await tester.tap(_checkbox(39));
      await tester.pump();
      expect(find.text('Gecikmiş'), findsOneWidget);
      expect(
        tester.getTopLeft(_row(39)).dy,
        lessThan(tester.getTopLeft(find.text('Bugün · 4 Ekim')).dy),
        reason: 'still above today, under its overdue heading',
      );
      api.release(_toggle);
      await tester.pumpAndSettle();
    });

    testWidgets('the view chips carry their tap for screen readers and '
        'switch access', (tester) async {
      final handle = tester.ensureSemantics();
      final api = FakeApi();
      final queries = _recordTodos(api);
      await pumpWithRoutes(tester, api, initialLocation: '/todos');
      final node = tester.getSemantics(find.bySemanticsLabel(
        RegExp(r'^Tamamlanan$'),
      ));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await settleFrames(tester);
      expect(queries.last['filter'], 'done');
      handle.dispose();
    });
  });

  group('large text and English', () {
    for (final locale in const [Locale('tr'), Locale('en')]) {
      testWidgets('the Agenda and the sheet lay out at 200% ($locale)', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final api = FakeApi();
        _recordTodos(api);
        await pumpWithRoutes(tester, api,
            initialLocation: '/todos', locale: locale);
        expect(tester.takeException(), isNull);
        expect(find.text(locale.languageCode == 'tr' ? 'Ajanda' : 'Agenda'),
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
        'becomes of the todos in it — kept, by default', (tester) async {
      final api = FakeApi();
      await pumpWithRoutes(tester, api, initialLocation: '/todos/lists');
      expect(find.text('Ev'), findsOneWidget);
      expect(find.text('1 açık · 2 görev'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing,
          reason: '"Yeni liste" is in the app bar');

      await tester.tap(find.text('Yeni liste'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'İş');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /todo_lists').single,
          {'name': 'İş', 'color': rotatingSwatch(1)});
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ev'));
      await tester.pumpAndSettle();
      expect(find.text('Listeyi düzenle'), findsOneWidget);
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
      await tester.tap(find.text('Ev'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('“Ev” listesi silinsin mi?'), findsOneWidget);
      expect(find.textContaining('Bu listede 2 görev var'), findsOneWidget);
      // The filled, default answer keeps the todos.
      expect(
        find.widgetWithText(FilledButton, 'Görevleri listesiz bırak'),
        findsOneWidget,
      );
      expect(find.text('Görevlerle birlikte sil'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
      await tester.tap(find.text('Görevleri listesiz bırak'));
      await settleFrames(tester);
      expect(deletes, [
        {'todos': 'keep'},
      ]);
      expect(find.text('“Ev” listesi silindi'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('archived lists wait under "Arşivlenmiş"; one comes back '
        'from its sheet', (tester) async {
      final api = FakeApi()
        ..on('GET /todo_lists', {
          'todo_lists': [
            todoListJson(),
            {...todoListJson(id: 8, name: 'Eski'), 'archived': true},
          ],
          'meta': const {'unlisted_open_count': 1},
        })
        ..on('PATCH /todo_lists/8', {'todo_list': todoListJson(id: 8)});
      await pumpWithRoutes(tester, api, initialLocation: '/todos/lists');
      expect(find.text('Eski'), findsNothing, reason: 'folded away');
      await tester.tap(find.text('Arşivlenmiş · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eski'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Geri yükle'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todo_lists/8').single, {'archived': false});
      expect(find.text('“Eski” listesi geri yüklendi'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
