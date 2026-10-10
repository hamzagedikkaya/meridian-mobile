/// The Agenda tab (design-analysis §7.4): todos and events merged day by
/// day, its views, the lingering of ticked-off todos, the capture bar, the
/// day headings' quick add, the chip row at phone width, and the event
/// form's series band.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/l10n/app_l10n_en.dart';
import 'package:meridian_mobile/l10n/app_l10n_tr.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/todo.dart';
import 'package:meridian_mobile/ui/screens/agenda/agenda_days.dart';
import 'package:meridian_mobile/ui/screens/agenda/agenda_screen.dart';
import 'package:meridian_mobile/ui/screens/agenda/event_form.dart';
import 'package:meridian_mobile/ui/screens/agenda/event_sheet.dart';
import 'package:meridian_mobile/ui/widgets/capture_bar.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/primary_button.dart';

import '../support/app_harness.dart';
import '../support/fake_api.dart';

final _today = DateTime(2026, 10, 4);

Todo _todo(int id, {DateTime? due, String? time, bool overdue = false}) =>
    Todo.fromJson({
      ...todoJson(id: id),
      'title': 'T$id',
      'due_at': null,
      'due_date': due == null
          ? null
          : '${due.year}-${'${due.month}'.padLeft(2, '0')}-'
                '${'${due.day}'.padLeft(2, '0')}',
      'due_time': time,
      'overdue': overdue,
    });

Occurrence _event(int id, DateTime day, {String? time}) => (
  day: day,
  event: Event.fromJson({
    ...eventJson(id: id, title: 'E$id', allDay: time == null),
    'start_at': time == null
        ? '2026-10-04T00:00:00.000+03:00'
        : '2026-10-04T$time:00.000+03:00',
    'end_at': null,
  }),
);

String _label(AgendaEntry e) => switch (e) {
  TodoEntry(:final todo) => todo.title,
  EventEntry(:final event) => event.title,
};

void main() {
  setUpAll(initializeDateFormatting);

  group('the days ahead', () {
    test('overdue first, today always, the next six days only when they '
        'hold something, then "Sonra"', () {
      final groups = upcomingGroups(
        todos: [
          _todo(1, due: DateTime(2026, 10, 3), overdue: true),
          _todo(2, due: DateTime(2026, 10, 6)),
          _todo(3, due: DateTime(2026, 10, 20)),
          _todo(4), // no date: the inbox's
        ],
        occurrences: [_event(10, DateTime(2026, 10, 12), time: '09:00')],
        today: _today,
      );
      expect(
        [for (final g in groups) (g.kind, g.day)],
        [
          (AgendaGroupKind.overdue, null),
          (AgendaGroupKind.today, _today),
          (AgendaGroupKind.day, DateTime(2026, 10, 6)),
          (AgendaGroupKind.later, null),
        ],
      );
      expect(groups.first.entries.map(_label), ['T1']);
      expect(groups[1].entries, isEmpty, reason: 'today, empty, still there');
      expect(groups.last.entries.map(_label), [
        'E10',
        'T3',
      ], reason: 'later: by day');
    });

    test('within a day: all-day events, then events and todos by time, then '
        'todos with only a date', () {
      final groups = upcomingGroups(
        todos: [
          _todo(1, due: _today),
          _todo(2, due: _today, time: '14:00'),
          _todo(3, due: _today, time: '08:30'),
        ],
        occurrences: [
          _event(10, _today, time: '09:00'),
          _event(11, _today),
        ],
        today: _today,
      );
      expect(groups.single.entries.map(_label), [
        'E11',
        'T3',
        'E10',
        'T2',
        'T1',
      ]);
    });

    test('finished todos by the day they were finished, newest first', () {
      Todo done(int id, String at) => Todo.fromJson({
        ...todoJson(id: id, status: 'done'),
        'completed_at': at,
      });
      final groups = doneGroups([
        done(1, '2026-10-04T10:00:00.000+03:00'),
        done(2, '2026-10-02T10:00:00.000+03:00'),
        done(3, '2026-10-04T08:00:00.000+03:00'),
      ]);
      expect(groups.map((g) => g.day), [
        DateTime(2026, 10, 4),
        DateTime(2026, 10, 2),
      ]);
      expect(groups.first.todos.map((t) => t.id), [1, 3]);
    });
  });

  group('the Agenda tab', () {
    testWidgets('adds through its capture bar, with "Etkinlik ekle" beside '
        'it — no FAB', (tester) async {
      await pumpWithRoutes(tester, FakeApi(), initialLocation: '/agenda');
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(CaptureBar), findsOneWidget);
      expect(find.text('Ekle: görev, etkinlik…'), findsOneWidget);

      await tester.tap(find.byTooltip('Etkinlik ekle'));
      await tester.pumpAndSettle();
      expect(find.text('Yeni etkinlik'), findsOneWidget);
    });

    testWidgets('a long press on a day heading opens quick add', (
      tester,
    ) async {
      await pumpWithRoutes(tester, FakeApi(), initialLocation: '/agenda');
      await tester.longPress(find.text('Bugün · 4 Ekim'));
      await tester.pumpAndSettle();
      expect(find.text('Hızlı ekle'), findsOneWidget);
    });

    testWidgets('a ticked-off todo lingers, struck through, then folds into '
        '"1 tamamlandı", which shows the finished ones', (tester) async {
      final api = FakeApi();
      var open = true;
      final filters = <String?>[];
      api.onRequest('GET /todos', (request) {
        final filter = request.uri.queryParameters['filter'];
        filters.add(filter);
        return {
          'todos': [
            if (filter == 'open' && open) todoJson(),
            if (filter == 'done') todoJson(status: 'done'),
          ],
          'meta': const {
            'counts': {'open': 1, 'overdue': 1},
          },
        };
      });
      await pumpWithRoutes(tester, api, initialLocation: '/agenda');
      final row = find.byKey(const ValueKey('todo-39'));
      open = false;
      await tester.tap(
        find.descendant(of: row, matching: find.byType(CheckPop)),
      );
      await settleFrames(tester);
      expect(row, findsOneWidget, reason: 'the refetch dropped it; it lingers');
      expect(find.text('1 tamamlandı'), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(row, findsNothing);
      expect(find.text('1 tamamlandı'), findsOneWidget);

      await tester.tap(find.text('1 tamamlandı'));
      await settleFrames(tester);
      expect(filters.last, 'done');
      expect(row, findsOneWidget, reason: 'the finished ones');
      await tester.pumpAndSettle();
    });

    testWidgets('at 360 dp the chips scroll sideways', (tester) async {
      await pumpWithRoutes(tester, FakeApi(), initialLocation: '/agenda');
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pumpAndSettle();
      final chips = find
          .ancestor(
            of: find.text('Yaklaşan'),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(chips).position;
      expect(position.axis, Axis.horizontal);
      expect(position.maxScrollExtent, greaterThan(0));
      expect(
        find.ancestor(of: chips, matching: find.byType(ShaderMask)),
        findsOneWidget,
      );
      bool fading() =>
          (tester.state(
                        find.byWidgetPredicate(
                          (w) => w.runtimeType.toString() == '_ViewChips',
                        ),
                      )
                      as dynamic)
                  .fading
              as bool;
      expect(fading(), isTrue, reason: 'its end fades while more follow');
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(fading(), isFalse, reason: 'scrolled to its end: no fade');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tick keeps the row: its box fills in place', (tester) async {
      await pumpWithRoutes(tester, FakeApi(), initialLocation: '/agenda');
      final box = find.descendant(
        of: find.byKey(const ValueKey('todo-39')),
        matching: find.byType(CheckPop),
      );
      final before = tester.state(box);
      await tester.tap(box);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.state(box), same(before));
      await tester.pumpAndSettle();
    });

    testWidgets('→ "Tamamla" slides the row back, the same row', (
      tester,
    ) async {
      await pumpWithRoutes(tester, FakeApi(), initialLocation: '/agenda');
      final row = find.byKey(const ValueKey('todo-39'));
      final box = find.descendant(of: row, matching: find.byType(CheckPop));
      final before = tester.state(box);
      final x = tester.getTopLeft(row).dx;
      await tester.drag(row, const Offset(600, 0));
      await tester.pump();
      expect(tester.state(box), same(before));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(row).dx,
        greaterThan(x),
        reason: 'still sliding back',
      );
      await tester.pumpAndSettle();
      expect(tester.state(box), same(before));
      expect(tester.getTopLeft(row).dx, x);
    });

    testWidgets('← "Yarın" that fails slides the row back, whole', (
      tester,
    ) async {
      final api = FakeApi()..failNetwork('PATCH /todos/39');
      await pumpWithRoutes(tester, api, initialLocation: '/agenda');
      final row = find.byKey(const ValueKey('todo-39'));
      final height = tester.getSize(row).height;
      await tester.drag(row, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(api.requests, contains('PATCH /todos/39'));
      expect(row, findsOneWidget);
      expect(tester.getSize(row).height, height);
      expect(find.byType(SnackBar), findsOneWidget);
      // The Agenda rebuilds — a view change — without a dismissed row in it.
      await tester.ensureVisible(find.text('Tamamlanan'));
      await tester.tap(find.text('Tamamlanan'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Yaklaşan'));
      await tester.tap(find.text('Yaklaşan'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(row, findsOneWidget);
    });

    testWidgets('a view still loading keeps the last one as it was, then '
        'cross-fades', (tester) async {
      final api = FakeApi();
      await pumpWithRoutes(tester, api, initialLocation: '/agenda');
      final list = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      final before = tester.state(list.first);
      await tester.ensureVisible(find.text('Tamamlanan'));
      await tester.pumpAndSettle();
      api.hold('GET /todos');
      await tester.tap(find.text('Tamamlanan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(list, findsOneWidget);
      expect(
        tester.state(list.first),
        same(before),
        reason: 'the last view kept, its scroll offset with it',
      );
      api.release('GET /todos');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 60));
      expect(list, findsNWidgets(2), reason: 'cross-fading');
      await tester.pumpAndSettle();
      expect(list, findsOneWidget);
    });

    testWidgets('every tap target is labeled for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWithRoutes(tester, FakeApi(), initialLocation: '/agenda');
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    test('a weekly series on given days names them', () {
      final rule = Recurrence.parse(
        'FREQ=WEEKLY;BYDAY=TH,TU',
        anchor: DateTime(2026, 10, 6),
      );
      expect(rule.preset, RecurrencePreset.custom);
      expect(recurrenceText(const AppL10nTr(), rule), 'Her hafta Sal, Per');
      expect(
        recurrenceText(
          const AppL10nEn(),
          Recurrence.parse('FREQ=WEEKLY;BYDAY=MO,WE;INTERVAL=2'),
        ),
        isNot(contains('Mon')),
        reason: 'every other week is not "every week"',
      );
    });

    testWidgets('editing a series says, over "Kaydet", that it changes '
        'every event in it', (tester) async {
      await pumpWithRoutes(
        tester,
        FakeApi(),
        home: opener(
          (context) => openEventForm(
            context,
            existing: Event.fromJson(eventJson(recurring: true, full: true)),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final band = find.text('Bu değişiklik serideki tüm etkinlikleri etkiler');
      expect(band, findsOneWidget);
      expect(
        tester.getBottomLeft(band).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(PrimaryButton)).dy),
      );
      expect(
        find.descendant(
          of: find.ancestor(of: band, matching: find.byType(Row)).first,
          matching: find.byIcon(Icons.info_outline_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a one-off event\'s form has no band', (tester) async {
      await pumpWithRoutes(
        tester,
        FakeApi(),
        home: opener(
          (context) => openEventForm(
            context,
            existing: Event.fromJson(eventJson(full: true)),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('serideki'), findsNothing);
    });

    test('a link\'s view: p24\'s todo filters land on the Agenda\'s views', () {
      expect(AgendaView.of(null), isNull);
      expect(AgendaView.of('open'), AgendaView.upcoming);
      expect(AgendaView.of('today'), AgendaView.upcoming);
      expect(AgendaView.of('events'), AgendaView.upcoming);
      expect(AgendaView.of('inbox'), AgendaView.inbox);
      expect(AgendaView.of('undated'), AgendaView.inbox);
      expect(AgendaView.of('overdue'), AgendaView.overdue);
      expect(AgendaView.of('done'), AgendaView.done);
    });
  });
}
