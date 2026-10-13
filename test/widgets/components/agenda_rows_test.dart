/// What a screen reader hears from the shared agenda rows (§4.6): a todo's
/// priority and list, an event's repeat and whether it is over — all of it
/// on screen as colour, meta text or an icon.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/formats.dart' show setAppToday;
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/todo.dart';
import 'package:meridian_mobile/ui/widgets/agenda_rows.dart';

import '../../support/fake_api.dart';
import 'component_harness.dart';

String _labelOf(WidgetTester tester, Type row) =>
    tester.getSemantics(find.byType(row)).getSemanticsData().label;

void main() {
  setUpComponentFonts();
  setUp(() => setAppToday(DateTime(2026, 10, 5)));
  tearDown(() => setAppToday(null));

  Todo todo({String priority = 'urgent', String? body}) => Todo.fromJson({
        ...todoJson(),
        'title': 'Vergi beyannamesini gönder',
        'priority': priority,
        'body': body,
        'due_at': null,
        'due_date': '2026-10-04',
        'due_time': null,
        'todo_list': todoListJson(id: 3, name: 'İş'),
      });

  testWidgets('a todo row names its priority, list and notes', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpComponent(
      tester,
      TodoRow(todo: todo(body: 'Belgeler'), done: false, onToggle: () {}),
    );
    expect(find.text('İş'), findsOneWidget, reason: 'on screen');
    expect(
      _labelOf(tester, TodoRow),
      'Vergi beyannamesini gönder, Dün, gecikmiş, acil, liste: İş, notu var',
    );

    await pumpComponent(
      tester,
      TodoRow(todo: todo(priority: 'high'), done: false, onToggle: () {}),
      locale: const Locale('en'),
    );
    expect(
      _labelOf(tester, TodoRow),
      'Vergi beyannamesini gönder, Yesterday, overdue, high priority, '
      'list: İş',
    );

    // Medium and low are the default: nothing to add.
    await pumpComponent(
      tester,
      TodoRow(
        todo: todo(priority: 'medium'),
        done: false,
        showList: false,
        onToggle: () {},
      ),
    );
    expect(
      _labelOf(tester, TodoRow),
      'Vergi beyannamesini gönder, Dün, gecikmiş',
    );
    handle.dispose();
  });

  testWidgets('an event row from a list payload says it repeats, on screen '
      'and to a screen reader, and says when it is over', (tester) async {
    final handle = tester.ensureSemantics();
    // `GET /events` items carry `recurring` but not the rule.
    final event = Event.fromJson(eventJson(recurring: true));
    expect(event.recurrenceRule, isNull);
    await pumpComponent(tester, EventRow(event: event, finished: true));
    // On screen the ⟳ says it repeats; the line keeps the place.
    expect(find.text('Stüdyo'), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    expect(
      _labelOf(tester, EventRow),
      'Yoga, 18:00 – 19:00, Tekrarlıyor, Stüdyo, bitti',
    );

    // A full event's weekly rule reads as such.
    await pumpComponent(
      tester,
      EventRow(
        event: Event.fromJson(eventJson(recurring: true, full: true)),
      ),
      locale: const Locale('en'),
    );
    expect(find.text('Stüdyo · Every week'), findsOneWidget);
    expect(
      _labelOf(tester, EventRow),
      'Yoga, 18:00 – 19:00, Every week, Stüdyo',
    );
    handle.dispose();
  });

  testWidgets('a repeating event keeps its place on the line at large text',
      (tester) async {
    for (final scale in [1.0, 1.6, 2.0]) {
      for (final (json, place) in [
        (eventJson(recurring: true), 'Stüdyo'),
        (eventJson(recurring: true, full: true), 'Stüdyo · Her hafta'),
        (
          {...eventJson(recurring: true), 'location': 'Moda Sahnesi'},
          'Moda Sahnesi',
        ),
      ]) {
        await pumpComponent(
          tester,
          ListView(children: [EventRow(event: Event.fromJson(json))]),
          textScale: scale,
        );
        final meta = find.textContaining(place.split(' · ').first);
        expect(meta, findsOneWidget, reason: '$place at $scale');
        final paragraph = tester.renderObject<RenderParagraph>(meta);
        if (place.contains(' · ')) continue; // the label may give way
        expect(paragraph.didExceedMaxLines, isFalse,
            reason: '$place at $scale');
      }
    }
  });
}
