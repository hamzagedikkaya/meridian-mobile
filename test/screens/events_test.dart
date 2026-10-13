/// Events (contract §10): the form — defaults, all-day dates, repetition,
/// an end after the start, a series edited as a whole — the event sheet and
/// its deletes (a one-off with "Geri al", a series as a whole or from an
/// occurrence on), the agenda, Today's agenda and todos, and quick
/// capture's "add as an event".
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/theme/entity_color.dart';
import 'package:meridian_mobile/ui/screens/agenda/event_form.dart';
import 'package:meridian_mobile/ui/screens/agenda/event_sheet.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/choice_wrap.dart';

import '../support/app_harness.dart';
import '../support/fake_api.dart';

/// Types [hh]:[mm] into the open time picker, in its keyboard mode.
Future<void> _typeTime(WidgetTester tester, String hh, String mm) async {
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(
      of: find.byType(Dialog), matching: find.byType(TextField));
  await tester.enterText(fields.at(0), hh);
  await tester.enterText(fields.at(1), mm);
  await tester.tap(find.text('Tamam'));
  await tester.pumpAndSettle();
}

/// The Agenda's day list (not its sideways chip row).
final _agendaList = find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byType(Scrollable),
).first;

Future<void> _openForm(
  WidgetTester tester,
  FakeApi api, {
  Event? existing,
  DateTime? occurrence,
}) async {
  await pumpWithRoutes(
    tester,
    api,
    home: opener((context) => openEventForm(
          context,
          existing: existing,
          day: fixtureNow,
          occurrence: occurrence,
        )),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initializeDateFormatting);

  group('the event form', () {
    testWidgets('a new event starts at the next full hour, for an hour, and '
        'is sent as the account\'s wall clock', (tester) async {
      final api = FakeApi();
      await _openForm(tester, api);
      expect(find.text('Yeni etkinlik'), findsOneWidget);
      expect(find.text('13:00'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Dişçi');
      await tester.enterText(
          find.widgetWithText(TextField, 'Konum'), 'Moda Klinik');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /events').single, {
        'title': 'Dişçi',
        'start_at': '2026-10-04T13:00',
        'end_at': '2026-10-04T14:00',
        'all_day': false,
        'location': 'Moda Klinik',
        'color': recordSwatches.first,
        'event_type': 'personal',
      });
      expect(find.text('Yeni etkinlik'), findsNothing);
      expect(find.text('“Yoga” eklendi'), findsOneWidget,
          reason: 'the saved event, as the server answered');
      await tester.pumpAndSettle();
    });

    testWidgets('an all-day event sends its date; a weekly one its rule',
        (tester) async {
      final api = FakeApi();
      await _openForm(tester, api);
      await tester.enterText(find.byType(TextField).first, 'Pazar kahvaltısı');
      await tester.tap(find.text('Tüm gün'));
      await tester.pump();
      expect(find.text('13:00'), findsNothing, reason: 'no times all day');
      await tester.tap(find.text('Her hafta'));
      await tester.pump();
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /events').single, {
        'title': 'Pazar kahvaltısı',
        'start_at': '2026-10-04',
        'all_day': true,
        'color': recordSwatches.first,
        'event_type': 'personal',
        'recurrence_rule': 'FREQ=WEEKLY',
      });
      await tester.pumpAndSettle();
    });

    testWidgets('an end before the start is refused before anything is sent',
        (tester) async {
      final api = FakeApi();
      await _openForm(tester, api);
      await tester.enterText(find.byType(TextField).first, 'Toplantı');
      await tester.tap(find.text('14:00'));
      await tester.pumpAndSettle();
      await _typeTime(tester, '12', '00');
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      expect(find.text('Bitiş başlangıçtan sonra olmalı'), findsOneWidget);
      expect(api.bodiesOf('POST /events'), isEmpty);

      // Fixed live once a save was tried.
      await tester.tap(find.text('12:00'));
      await tester.pumpAndSettle();
      await _typeTime(tester, '15', '30');
      expect(find.text('Bitiş başlangıçtan sonra olmalı'), findsNothing);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /events').single,
          containsPair('end_at', '2026-10-04T15:30'));
      await tester.pumpAndSettle();
    });

    testWidgets('a rule the server refuses is said under the repetition',
        (tester) async {
      final api = FakeApi()
        ..on('POST /events', {
          'errors': {
            'recurrence_rule': ['Tekrar kuralı hiçbir güne denk gelmiyor'],
          },
          'code': 'validation_failed',
          'details': {
            'recurrence_rule': [
              {'error': 'no_occurrences'},
            ],
          },
        }, status: 422);
      await _openForm(tester, api);
      await tester.enterText(find.byType(TextField).first, 'x');
      await tester.tap(find.text('Her yıl'));
      await tester.pump();
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(find.text('Bu tekrar hiçbir güne denk gelmiyor'), findsOneWidget);
      expect(find.text('Yeni etkinlik'), findsOneWidget, reason: 'still open');
    });

    testWidgets('a series says a save changes all of it, and sends only what '
        'changed — its stored rule untouched', (tester) async {
      final api = FakeApi();
      await _openForm(
        tester,
        api,
        existing: Event.fromJson(eventJson(recurring: true, full: true)),
      );
      expect(find.text('Etkinliği düzenle'), findsOneWidget);
      expect(find.textContaining('serideki tüm etkinlikleri'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceWrap<RecurrencePreset>>(
                find.byType(ChoiceWrap<RecurrencePreset>))
            .selected,
        RecurrencePreset.weekly,
      );

      await tester.enterText(find.widgetWithText(TextField, 'Yoga'), 'Pilates');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /events/12').single, {'title': 'Pilates'});
      await tester.pumpAndSettle();
    });
    testWidgets('a series that ends after a number of times says so, and '
        'keeps its COUNT when the repetition is changed', (tester) async {
      final api = FakeApi();
      await _openForm(
        tester,
        api,
        existing: Event.fromJson({
          ...eventJson(recurring: true, full: true),
          'recurrence_rule': 'FREQ=WEEKLY;COUNT=10',
        }),
      );
      expect(find.text('10 kez'), findsOneWidget);
      expect(
        tester.widget<ChoiceWrap<Object>>(find.byWidgetPredicate(
          (w) => w is ChoiceWrap && w.choices.length == 3,
        )).selected.toString(),
        endsWith('count'),
      );
      await tester.tap(find.text('Her gün'));
      await tester.pump();
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /events/12').single,
          {'recurrence_rule': 'FREQ=DAILY;COUNT=10'});
      await tester.pumpAndSettle();
    });
  });

  for (final locale in const [Locale('tr'), Locale('en')]) {
    testWidgets('the form and the agenda lay out at 200% text ($locale)', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = FakeApi()
        ..on('GET /events', {
          'events': [
            eventJson(recurring: true, occurrences: ['2026-10-04']),
          ],
        });
      await pumpWithRoutes(tester, api,
          initialLocation: '/agenda?view=events', locale: locale);
      expect(tester.takeException(), isNull);
      // The capture bar's "Etkinlik ekle".
      await tester.tap(find.byTooltip(
          locale.languageCode == 'tr' ? 'Etkinlik ekle' : 'Add event'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(locale.languageCode == 'tr' ? 'Yeni etkinlik' : 'New event'),
        findsOneWidget,
      );
    });
  }

  group('the event sheet', () {
    Future<void> openSheet(
      WidgetTester tester,
      FakeApi api,
      Event event, {
      DateTime? day,
    }) async {
      await pumpWithRoutes(
        tester,
        api,
        home: opener((context) => showEventSheet(context, event, day: day)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows when and where, and the description from the full '
        'event; "Sil" deletes a one-off with "Geri al"', (tester) async {
      final api = FakeApi();
      await openSheet(tester, api, Event.fromJson(eventJson()));
      expect(find.textContaining('18:00 – 19:00'), findsOneWidget);
      expect(find.text('Stüdyo'), findsOneWidget);
      expect(find.text('Mat getir'), findsOneWidget);
      expect(find.text('Sağlık'), findsOneWidget);

      await tester.tap(find.text('Sil'));
      await settleFrames(tester);
      expect(find.text('“Yoga” silindi'), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /events/12')));
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /events/12'));
    });

    testWidgets('"Düzenle" opens the form with the full event', (tester) async {
      final api = FakeApi();
      await openSheet(tester, api, Event.fromJson(eventJson()));
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      expect(find.text('Etkinliği düzenle'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Mat getir'), findsOneWidget);
    });

    testWidgets('a series asks: this one and the rest end the series the day '
        'before; the whole series goes with "Geri al"', (tester) async {
      final api = FakeApi()
        ..on('GET /events/12', {
          'event': eventJson(recurring: true, full: true),
        });
      final series = Event.fromJson(eventJson(recurring: true));
      await openSheet(tester, api, series, day: DateTime(2026, 10, 11));
      expect(find.textContaining('Her hafta'), findsOneWidget,
          reason: 'how it repeats');
      expect(find.textContaining('tüm seriyi'), findsNothing);
      expect(find.textContaining('serideki tüm etkinlikleri'), findsOneWidget);

      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Tekrarlayan etkinlik'), findsOneWidget);
      expect(find.text('11 Ekim öncesindeki etkinlikler kalır.'),
          findsOneWidget);
      expect(find.textContaining('Yalnızca bu'), findsNothing,
          reason: 'a series is one record: there is no "only this one"');
      await tester.tap(find.text('Bu ve sonrakileri sil'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /events/12').single,
          {'recurrence_rule': 'FREQ=WEEKLY;UNTIL=20261010'});
      expect(find.text('“Yoga” serisi bu tarihten itibaren kaldırıldı'),
          findsOneWidget);
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tüm seriyi sil'));
      await settleFrames(tester);
      expect(find.text('“Yoga” silindi'), findsOneWidget);
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /events/12'));
    });

    testWidgets('from its first occurrence, a series can only go whole',
        (tester) async {
      final api = FakeApi()
        ..on('GET /events/12', {
          'event': eventJson(recurring: true, full: true),
        });
      await openSheet(
        tester,
        api,
        Event.fromJson(eventJson(recurring: true)),
        day: DateTime(2026, 10, 4),
      );
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Tüm seriyi sil'), findsOneWidget);
      expect(find.textContaining('ve sonrakiler'), findsNothing);
    });
    // "Hafta içi her gün", begun on a Sunday: its first occurrence is the
    // Monday after.
    Map<String, dynamic> weekdays(String rule) => {
          ...eventJson(recurring: true, full: true),
          'recurrence_rule': rule,
        };

    testWidgets('a weekdays series begun on a Sunday can only go whole from '
        'its first Monday', (tester) async {
      final api = FakeApi()
        ..on('GET /events/12', {
          'event': weekdays('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'),
        });
      await openSheet(
        tester,
        api,
        Event.fromJson(eventJson(recurring: true)),
        day: DateTime(2026, 10, 5),
      );
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Tüm seriyi sil'), findsOneWidget);
      expect(find.textContaining('ve sonrakiler'), findsNothing);
      await tester.tap(find.text('Tüm seriyi sil'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /events/12'), isEmpty);
      expect(find.text('“Yoga” silindi'), findsOneWidget);
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /events/12'));
    });

    testWidgets('when ending the series would leave nothing, the whole '
        'series goes, with "Geri al"', (tester) async {
      // A rule the app does not read ahead: the first Monday of each month.
      final api = FakeApi()
        ..on('GET /events/12', {'event': weekdays('FREQ=MONTHLY;BYDAY=1MO')})
        ..on('PATCH /events/12', {
          'errors': {
            'recurrence_rule': ['Tekrar kuralı hiçbir güne denk gelmiyor'],
          },
          'code': 'validation_failed',
          'details': {
            'recurrence_rule': [
              {'error': 'no_occurrences'},
            ],
          },
        }, status: 422);
      await openSheet(
        tester,
        api,
        Event.fromJson(eventJson(recurring: true)),
        day: DateTime(2026, 10, 5),
      );
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      // "Yarın/Bugün/… ve sonrakiler": the day is named against the clock.
      await tester.tap(find.textContaining('ve sonrakiler'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /events/12'), hasLength(1));
      expect(find.text('Bu tekrar hiçbir güne denk gelmiyor'), findsNothing);
      expect(find.text('“Yoga” silindi'), findsOneWidget);
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /events/12'));
    });
  });

  group('the agenda', () {
    testWidgets('each occurrence under its day; "Daha fazla göster" asks for '
        'thirty more days', (tester) async {
      final api = FakeApi();
      final queries = <Map<String, dynamic>>[];
      api.onRequest('GET /events', (RequestOptions request) {
        queries.add(request.queryParameters);
        return {
          'events': [
            eventJson(
              recurring: true,
              occurrences: ['2026-10-04', '2026-10-11'],
            ),
            {
              ...eventJson(
                id: 14,
                title: 'Tatil',
                allDay: true,
                start: '2026-10-05T00:00:00.000+03:00',
                end: null,
              ),
              'occurrences': ['2026-10-05'],
            },
          ],
        };
      });
      api.on('GET /events/14', {
        'event': eventJson(id: 14, title: 'Tatil', allDay: true, full: true),
      });
      await pumpWithRoutes(tester, api, initialLocation: '/agenda?view=events');
      expect(queries.single, {'from': '2026-10-04', 'to': '2026-11-02'});
      expect(find.text('Bugün · 4 Ekim'), findsOneWidget);
      expect(find.text('Yarın · 5 Ekim'), findsOneWidget);
      expect(find.text('Sonra'), findsOneWidget,
          reason: 'a week ahead and on: one group, each row with its day');
      expect(find.text('Paz 11'), findsOneWidget);
      expect(find.text('Yoga'), findsNWidgets(2), reason: 'each occurrence');
      expect(find.text('Tatil'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(find.text('Daha fazla göster'), 200,
          scrollable: _agendaList);
      await tester.tap(find.text('Daha fazla göster'));
      await settleFrames(tester);
      expect(queries.last, {'from': '2026-10-04', 'to': '2026-12-02'});
      expect(find.text('Tatil'), findsOneWidget,
          reason: 'kept on screen meanwhile and after');

      await tester.tap(find.text('Tatil'));
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsOneWidget, reason: 'its sheet');
    });
    testWidgets('when the longer window fails, the days shown stay, with '
        'why and "Tekrar dene" in place of the spinner', (tester) async {
      final api = FakeApi()
        ..on('GET /events', {
          'events': [
            eventJson(recurring: true, occurrences: ['2026-10-04']),
          ],
        });
      await pumpWithRoutes(tester, api, initialLocation: '/agenda?view=events');
      expect(find.text('Yoga'), findsOneWidget);

      api.failNetwork('GET /events');
      await tester.scrollUntilVisible(find.text('Daha fazla göster'), 200,
          scrollable: _agendaList);
      await tester.tap(find.text('Daha fazla göster'));
      await settleFrames(tester);
      await tester.pump(const Duration(seconds: 10));
      await settleFrames(tester);
      expect(find.text('Yoga'), findsOneWidget, reason: 'still shown');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Tekrar dene'), findsOneWidget);

      api.on('GET /events', {
        'events': [
          eventJson(
            recurring: true,
            occurrences: ['2026-10-04', '2026-11-15'],
          ),
        ],
      });
      await tester.tap(find.text('Tekrar dene'));
      await settleFrames(tester);
      expect(find.text('Tekrar dene'), findsNothing);
      expect(find.text('Yoga'), findsNWidgets(2));
      await tester.scrollUntilVisible(find.text('Daha fazla göster'), 200,
          scrollable: _agendaList);
      expect(find.text('Daha fazla göster'), findsOneWidget);
    });
  });

  group('Today', () {
    testWidgets('the Today card: today\'s events from /events — each with '
        'a sheet — and the way to the full agenda', (tester) async {
      final api = FakeApi();
      final queries = <Map<String, dynamic>>[];
      api.onRequest('GET /events', (RequestOptions request) {
        queries.add(request.queryParameters);
        return {
          'events': [
            eventJson(recurring: true, occurrences: ['2026-10-04']),
            {
              ...eventJson(
                id: 15,
                title: 'Standup',
                start: '2026-10-05T09:00:00.000+03:00',
                end: '2026-10-05T09:15:00.000+03:00',
              ),
              'occurrences': ['2026-10-05'],
            },
          ],
        };
      });
      final router = await pumpWithRoutes(
        tester,
        api,
        home: const TodayScreen(),
      );
      // Today only: tomorrow and later are the Agenda's.
      expect(queries.last, {'from': '2026-10-04', 'to': '2026-10-04'});
      expect(find.text('Yoga'), findsOneWidget);
      expect(find.text('Standup'), findsNothing);

      await tester.tap(find.text('Yoga'));
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsOneWidget);
      Navigator.of(tester.element(find.text('Düzenle'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tümü').first);
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/agenda');
    });

    testWidgets('events already over fold into "+1 geçti", which opens on a '
        'tap', (tester) async {
      final api = FakeApi()
        ..on('GET /events', {
          'events': [
            eventJson(recurring: true, occurrences: ['2026-10-04']),
            {
              ...eventJson(
                id: 16,
                title: 'Kahvaltı',
                start: '2026-10-04T08:00:00.000+03:00',
                end: '2026-10-04T09:00:00.000+03:00',
              ),
              'occurrences': ['2026-10-04'],
            },
          ],
        });
      await pumpWithRoutes(tester, api, home: const TodayScreen());
      expect(find.text('Yoga'), findsOneWidget);
      expect(find.text('Kahvaltı'), findsNothing);
      await tester.tap(find.text('+1 geçti'));
      await tester.pumpAndSettle();
      expect(find.text('Kahvaltı'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the todos: a tick on the checkbox, and "Bugün için görev '
        'ekle" adding one due today in place', (tester) async {
      final milk = {
        ...todoJson(id: 41),
        'title': 'Süt al',
        'priority': 'medium',
        'due_at': null,
        'due_time': null,
        'overdue': false,
      };
      final api = FakeApi()..on('POST /todos', {'todo': milk}, status: 201);
      await pumpWithRoutes(tester, api, home: const TodayScreen());
      expect(find.byKey(const ValueKey('todo-39')), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('todo-39')),
        matching: find.byType(CheckPop),
      ));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /todos/39/toggle').single, {'done': true});
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bugün için görev ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Süt al');
      api.on('GET /home', homeJson(todos: [todoJson(status: 'done'), milk]));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleFrames(tester);
      expect(api.bodiesOf('POST /todos').single, {
        'title': 'Süt al',
        'priority': 'medium',
        'due_date': '2026-10-04',
      });
      expect(find.text('Süt al'), findsOneWidget, reason: 'on Today');
      expect(find.byType(TextField), findsOneWidget,
          reason: 'the field stays for the next one');
      await tester.pumpAndSettle();
    });

    testWidgets('the Today card lays out at 200% text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = FakeApi()
        ..on('GET /events', {
          'events': [
            eventJson(recurring: true, occurrences: ['2026-10-04']),
            {
              ...eventJson(id: 14, title: 'Tatil', allDay: true, end: null),
              'occurrences': ['2026-10-04'],
            },
          ],
        });
      await pumpWithRoutes(tester, api, home: const TodayScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('Tatil'), findsOneWidget);
    });

    testWidgets('until /events answers, today\'s events come from /home',
        (tester) async {
      final api = FakeApi()
        ..failNetwork('GET /events')
        ..on('GET /home', {
          ...homeJson(),
          'today_events_count': 5,
          'today_events': [eventJson(title: 'Yoga', recurring: true)],
        });
      await pumpWithRoutes(tester, api, home: const TodayScreen());
      expect(find.text('Yoga'), findsOneWidget);
      expect(find.text('+4 daha'), findsOneWidget,
          reason: '/home lists four at most, and says how many there are');
    });
  });
}
