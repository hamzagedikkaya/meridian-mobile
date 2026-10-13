/// The Agenda and its forms, as reviewed (WP-17 review, group g2): moves
/// and new events on the account's clock, an all-day event begun after
/// 22:00, date pickers on long-ago days, "n tamamlandı" per view, save
/// confirmations above the capture bar, the lists page's first load, and
/// the year on days of another year.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/todo.dart';
import 'package:meridian_mobile/ui/screens/agenda/agenda_days.dart';
import 'package:meridian_mobile/ui/screens/agenda/event_form.dart';
import 'package:meridian_mobile/ui/screens/agenda/todo_flows.dart';
import 'package:meridian_mobile/ui/screens/agenda/todo_sheet.dart';
import 'package:meridian_mobile/ui/widgets/capture_bar.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/skeletons.dart';

import '../support/app_harness.dart';
import '../support/fake_api.dart';

/// The account's zone, [ahead] of this device's: the account's wall clock
/// reads [fixtureNow] plus [ahead].
Duration _accountAhead(Duration ahead) => fixtureNow.timeZoneOffset + ahead;

/// A button at `/` that runs [run] with a ref.
Widget _consumerOpener(void Function(BuildContext, WidgetRef) run) => Scaffold(
  body: Consumer(
    builder: (context, ref, _) => Center(
      child: TextButton(
        onPressed: () => run(context, ref),
        child: const Text('open'),
      ),
    ),
  ),
);

Todo _todoDue(String date, String time, {bool overdue = true}) =>
    Todo.fromJson({
      ...todoJson(),
      'due_date': date,
      'due_time': time,
      'due_at': '${date}T$time:00.000+03:00',
      'overdue': overdue,
    });

void main() {
  setUpAll(initializeDateFormatting);

  group('the account\'s clock, not the phone\'s', () {
    testWidgets('moved to today, a todo whose time is past for the account '
        'loses its time — it would be overdue at once', (tester) async {
      final api = FakeApi();
      final todo = _todoDue('2026-10-03', '14:00');
      await pumpWithRoutes(
        tester,
        api,
        overrides: [
          // 15:30 for the account, 12:30 on the phone.
          accountUtcOffsetProvider.overrideWithValue(
            _accountAhead(const Duration(hours: 3)),
          ),
        ],
        home: _consumerOpener(
          (context, ref) => moveTodos(
            context,
            ref,
            [todo],
            day: DateTime(2026, 10, 4),
            message: 'Bugüne alındı',
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').single, {
        'due_date': '2026-10-04',
        'due_time': null,
      });
      await tester.pumpAndSettle();
    });

    testWidgets('a time still ahead for the account is kept, whatever the '
        'phone says', (tester) async {
      final api = FakeApi();
      final todo = _todoDue('2026-10-03', '11:00');
      await pumpWithRoutes(
        tester,
        api,
        overrides: [
          // 09:30 for the account, 12:30 on the phone.
          accountUtcOffsetProvider.overrideWithValue(
            _accountAhead(const Duration(hours: -3)),
          ),
        ],
        home: _consumerOpener(
          (context, ref) => moveTodos(
            context,
            ref,
            [todo],
            day: DateTime(2026, 10, 4),
            message: 'Bugüne alındı',
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39').single, {
        'due_date': '2026-10-04',
      });
      await tester.pumpAndSettle();
    });

    testWidgets('a new event starts at the account\'s next full hour', (
      tester,
    ) async {
      await pumpWithRoutes(
        tester,
        FakeApi(),
        overrides: [
          accountUtcOffsetProvider.overrideWithValue(
            _accountAhead(const Duration(hours: 3)),
          ),
        ],
        home: opener((context) => openEventForm(context, day: fixtureNow)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('16:00'), findsOneWidget);
      expect(find.text('17:00'), findsOneWidget);
    });
  });

  testWidgets('after 22:00 a new event switched to all day is one day, not '
      'two', (tester) async {
    final api = FakeApi();
    await pumpWithRoutes(
      tester,
      api,
      overrides: [
        // 22:30 for the account.
        accountUtcOffsetProvider.overrideWithValue(
          _accountAhead(const Duration(hours: 10)),
        ),
      ],
      home: opener(
        (context) => openEventForm(context, day: DateTime(2026, 10, 4)),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('23:00'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Tatil günü');
    await tester.tap(find.text('Tüm gün'));
    await tester.pump();
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    final body = api.bodiesOf('POST /events').single as Map;
    expect(body['start_at'], '2026-10-04');
    expect(body['all_day'], isTrue);
    expect(body.containsKey('end_at'), isFalse, reason: 'one day');
    await tester.pumpAndSettle();
  });

  group('date pickers on a day further back than five years', () {
    testWidgets('a todo long overdue: "Tarih seç" opens on its day', (
      tester,
    ) async {
      final todo = _todoDue('2019-05-12', '09:00');
      await pumpWithRoutes(
        tester,
        FakeApi(),
        home: _consumerOpener(
          (context, ref) => pickTodoDay(context, ref, todo),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('a yearly series begun in 2019: its date chip opens', (
      tester,
    ) async {
      final series = Event.fromJson({
        ...eventJson(
          start: '2019-05-12',
          end: null,
          allDay: true,
          recurring: true,
          full: true,
        ),
        'recurrence_rule': 'FREQ=YEARLY',
      });
      await pumpWithRoutes(
        tester,
        FakeApi(),
        home: opener((context) => openEventForm(context, existing: series)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.calendar_today_outlined).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    test('the range widens to take the initial day, either side', () {
      final today = DateTime(2026, 10, 4);
      final back = pickerRange(DateTime(2019, 5, 12), today);
      expect(back.first, DateTime(2019, 5, 12));
      expect(back.last, DateTime(2036));
      final ahead = pickerRange(DateTime(2040, 1, 2), today);
      expect(ahead.first, DateTime(2021));
      expect(ahead.last, DateTime(2040, 1, 2));
    });
  });

  group('"n tamamlandı" belongs to the view where it was finished', () {
    late FakeApi api;
    var open = true;

    setUp(() {
      open = true;
      api = FakeApi()
        ..onRequest('GET /todos', (request) {
          final filter = request.uri.queryParameters['filter'];
          return {
            'todos': [
              if (filter == 'open' && open) todoJson(),
              if (filter == 'undated')
                {
                  ...todoJson(id: 50),
                  'title': 'Kitap al',
                  'due_date': null,
                  'due_time': null,
                  'due_at': null,
                  'overdue': false,
                },
            ],
            'meta': const {
              'counts': {'open': 1, 'overdue': 1, 'undated': 1},
            },
          };
        });
    });

    Future<GoRouter> tickAndFold(WidgetTester tester) async {
      final router = await pumpWithRoutes(
        tester,
        api,
        initialLocation: '/agenda',
      );
      open = false;
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('todo-39')),
          matching: find.byType(CheckPop),
        ),
      );
      await settleFrames(tester);
      await tester.pump(const Duration(seconds: 4));
      await settleFrames(tester);
      expect(find.text('1 tamamlandı'), findsOneWidget);
      return router;
    }

    testWidgets('the inbox, where nothing was finished, says nothing', (
      tester,
    ) async {
      final router = await tickAndFold(tester);
      router.go('/agenda?view=inbox');
      await settleFrames(tester);
      expect(find.text('Kitap al'), findsWidgets);
      expect(find.text('1 tamamlandı'), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('"Geri al" after the fold takes it out of the count', (
      tester,
    ) async {
      await tickAndFold(tester);
      open = true;
      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(find.byKey(const ValueKey('todo-39')), findsOneWidget);
      expect(find.text('1 tamamlandı'), findsNothing);
      await tester.pumpAndSettle();
    });
  });

  group('"n tamamlandı" counts only what the view would have listed', () {
    /// Todo [id] due tomorrow (never overdue), or with no day at all.
    Map<String, dynamic> todoOf(int id, {required bool dated}) => {
      ...todoJson(id: id),
      'title': 'Görev $id',
      'due_date': dated ? '2026-10-05' : null,
      'due_time': null,
      'due_at': dated ? '2026-10-05T23:59:59.000+03:00' : null,
      'overdue': false,
    };

    /// The Agenda at [view] over todo 60 ([dated]), ticked off there and
    /// folded into "1 tamamlandı".
    Future<GoRouter> finishIn(
      WidgetTester tester,
      String view, {
      required bool dated,
    }) async {
      var open = true;
      final api = FakeApi()
        ..onRequest('GET /todos', (request) {
          final filter = request.uri.queryParameters['filter'];
          final listed =
              open && (filter == 'open' || (filter == 'undated' && !dated));
          return {
            'todos': [if (listed) todoOf(60, dated: dated)],
            'meta': const {
              'counts': {'open': 1},
            },
          };
        });
      final router = await pumpWithRoutes(
        tester,
        api,
        initialLocation: '/agenda?view=$view',
      );
      open = false;
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('todo-60')),
          matching: find.byType(CheckPop),
        ),
      );
      await settleFrames(tester);
      await tester.pump(const Duration(seconds: 4));
      await settleFrames(tester);
      expect(find.text('1 tamamlandı'), findsOneWidget);
      return router;
    }

    testWidgets('a todo due tomorrow, finished in Yaklaşan: Gecikmiş says '
        'nothing of it', (tester) async {
      final router = await finishIn(tester, 'upcoming', dated: true);
      router.go('/agenda?view=overdue');
      await settleFrames(tester);
      expect(find.text('1 tamamlandı'), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('an undated todo, finished in the inbox: Yaklaşan says '
        'nothing of it', (tester) async {
      final router = await finishIn(tester, 'inbox', dated: false);
      router.go('/agenda?view=upcoming');
      await settleFrames(tester);
      expect(find.text('1 tamamlandı'), findsNothing);
      await tester.pumpAndSettle();
    });
  });

  group('a save is confirmed where it can be seen', () {
    testWidgets('an edit saved from the todo sheet: the snackbar sits above '
        'the capture bar', (tester) async {
      final api = FakeApi();
      await pumpWithRoutes(tester, api, initialLocation: '/agenda');
      await tester.tap(find.text('Faturayı öde'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Faturayı yatır');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.requests, contains('PATCH /todos/39'));
      final snack = find.text('Görev güncellendi');
      expect(snack, findsOneWidget);
      expect(
        tester.getRect(snack).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(CaptureBar)).top),
      );
      await tester.pumpAndSettle();
    });

    /// [snack]'s card ends above the capture bar.
    void expectAboveBar(WidgetTester tester, Finder snack) {
      expect(snack, findsOneWidget);
      expect(
        tester.getRect(snack).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(CaptureBar)).top),
      );
    }

    testWidgets('a new event from the capture bar\'s "Etkinlik ekle": its '
        '"eklendi" sits above the bar', (tester) async {
      final api = FakeApi();
      await pumpWithRoutes(tester, api, initialLocation: '/agenda');
      await tester.tap(find.byTooltip('Etkinlik ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Yoga');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.requests, contains('POST /events'));
      expectAboveBar(tester, find.textContaining('eklendi'));
      await tester.pumpAndSettle();
    });

    testWidgets('a list made from "Liste: Tümü" → "Yeni liste": its '
        '"oluşturuldu" sits above the bar', (tester) async {
      final api = FakeApi();
      await pumpWithRoutes(tester, api, initialLocation: '/agenda');
      await tester.ensureVisible(find.text('Liste: Tümü'));
      await tester.tap(find.text('Liste: Tümü'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yeni liste'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'İş');
      await tester.tap(find.text('Kaydet').last);
      await settleFrames(tester);
      expect(api.requests, contains('POST /todo_lists'));
      expectAboveBar(tester, find.textContaining('oluşturuldu'));
      await tester.pumpAndSettle();
    });

    for (final (size, keyboard) in const [
      (Size(430, 932), 0.0),
      (Size(360, 780), 300.0),
      (Size(412, 915), 320.0),
    ]) {
      testWidgets('"Kaydet ve yeni" says what it added in the sheet, which '
          'stays up — in sight on ${size.width.round()}×'
          '${size.height.round()}, keyboard ${keyboard.round()} dp', (
        tester,
      ) async {
        final api = FakeApi();
        await pumpWithRoutes(
          tester,
          api,
          home: opener((context) => openTodoSheet(context)),
        );
        tester.view.physicalSize = size * 3;
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Süt al');
        await tester.ensureVisible(find.text('Kaydet ve yeni'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kaydet ve yeni'));
        await settleFrames(tester);
        expect(api.requests, contains('POST /todos'));
        final said = find.byKey(const ValueKey('todo-saved-and-new'));
        expect(said, findsOneWidget);
        expect(said.hitTestable(), findsOneWidget, reason: 'in sight');
        expect(
          tester.getRect(said).bottom,
          lessThanOrEqualTo(size.height - keyboard),
          reason: 'above the keyboard',
        );
        await tester.pumpAndSettle();
      });
    }
  });

  testWidgets('the lists page shows a skeleton while its first read is on '
      'its way', (tester) async {
    final api = FakeApi()..hold('GET /todo_lists');
    await pumpWithRoutes(tester, api, initialLocation: '/agenda/lists');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Bone), findsWidgets);
    api.release('GET /todo_lists');
    await settleFrames(tester);
    await tester.pumpAndSettle();
    expect(find.byType(Bone), findsNothing);
  });

  testWidgets('"Tamamlanan": a day of another year carries its year', (
    tester,
  ) async {
    final api = FakeApi()
      ..onRequest(
        'GET /todos',
        (_) => {
          'todos': [
            {
              ...todoJson(status: 'done'),
              'completed_at': '2026-10-02T10:00:00.000+03:00',
            },
            {
              ...todoJson(id: 41, status: 'done'),
              'completed_at': '2025-10-06T10:00:00.000+03:00',
            },
          ],
          'meta': const {'counts': <String, int>{}},
        },
      );
    await pumpWithRoutes(tester, api, initialLocation: '/agenda?view=done');
    await settleFrames(tester);
    expect(find.text('Cuma · 2 Ekim'), findsOneWidget);
    expect(find.text('Pazartesi · 6 Ekim 2025'), findsOneWidget);
  });
}
