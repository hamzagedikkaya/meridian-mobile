@Tags(['golden'])
/// Ajanda (Agenda): the days ahead, the inbox, the todo sheet, the event
/// sheet and the event form (design-analysis §7.4).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-7.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/models/todo.dart';
import 'package:meridian_mobile/ui/screens/agenda/agenda_screen.dart';
import 'package:meridian_mobile/ui/screens/agenda/event_form.dart';
import 'package:meridian_mobile/ui/screens/agenda/event_sheet.dart';
import 'package:meridian_mobile/ui/screens/agenda/todo_sheet.dart';

import 'golden_harness.dart';

const _en = <String, String>{
  'Vergi beyannamesini gönder': 'File the tax return',
  'İş': 'Work',
  'Ev': 'Home',
  'Sunum slaytlarını hazırla': 'Prepare the slide deck',
  'Market alışverişi yap': 'Do the grocery run',
  'Takım toplantısı': 'Team meeting',
  'Diş hekimi randevusu': 'Dentist appointment',
  'Annemin doğum günü': "Mum's birthday",
  'Faturayı öde': 'Pay the bill',
  'Yoga': 'Yoga',
  'Stüdyo': 'Studio',
  'Kitap kulübü notları': 'Book club notes',
  'Proje teslimi': 'Project hand-in',
  'Pasaport yenile': 'Renew the passport',
  'Kafe': 'Café',
  'Dişçiyi ara': 'Call the dentist',
  'Kombi bakımı': 'Boiler service',
  'Hediye fikirleri': 'Gift ideas',
  'Mat getir, 10 dk erken gel.': 'Bring a mat, come 10 minutes early.',
  'Elektrik ve su': 'Electricity and water',
  '100 günde 100 kitap': '100 books in 100 days',
};

String _fx(String tr) => fx(tr, _en);

// --- Fixtures -----------------------------------------------------------------

Map<String, dynamic> _list(int id) => id == 1
    ? {'id': 1, 'name': _fx('İş'), 'color': '#6B8FA0'}
    : {'id': 2, 'name': _fx('Ev'), 'color': '#6B8E5A'};

Map<String, dynamic> _todo(
  int id,
  String title, {
  DateTime? due,
  String? time,
  String priority = 'medium',
  bool overdue = false,
  int? list,
  String? body,
}) =>
    {
      'id': id,
      'title': _fx(title),
      'body': body == null ? null : _fx(body),
      'status': 'pending',
      'priority': priority,
      'due_at': due == null
          ? null
          : '${ymd(due)}T${time ?? '23:59'}:00.000+03:00',
      'due_date': due == null ? null : ymd(due),
      'due_time': time,
      'completed_at': null,
      'overdue': overdue,
      'position': id,
      'goal_id': null,
      'todo_list': list == null ? null : _list(list),
      'subtask_count': 0,
    };

Map<String, dynamic> _event(
  int id,
  String title, {
  required List<DateTime> on,
  String? start,
  String? end,
  String color = '#6B8FA0',
  String? location,
  bool recurring = false,
  bool full = false,
}) =>
    {
      'id': id,
      'title': _fx(title),
      'start_at': start == null
          ? '${ymd(on.first)}T00:00:00.000+03:00'
          : '${ymd(on.first)}T$start:00.000+03:00',
      'end_at': end == null ? null : '${ymd(on.first)}T$end:00.000+03:00',
      'all_day': start == null,
      'color': color,
      'event_type': 'health',
      'location': location == null ? null : _fx(location),
      'duration_minutes': start == null || end == null
          ? null
          : _minutes(end) - _minutes(start),
      'recurring': recurring,
      'occurrences': [for (final d in on) ymd(d)],
      if (full) 'description': _fx('Mat getir, 10 dk erken gel.'),
      if (full)
        'recurrence_rule':
            recurring ? 'FREQ=WEEKLY;UNTIL=20261231T205959Z' : null,
    };

int _minutes(String hhmm) =>
    int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3));

List<Map<String, dynamic>> _open() => [
      _todo(11, 'Vergi beyannamesini gönder',
          due: daysAgo(1), time: '17:00', priority: 'urgent', overdue: true, list: 1),
      _todo(12, 'Sunum slaytlarını hazırla',
          due: goldenNow, time: '15:30', priority: 'high', list: 1),
      _todo(13, 'Market alışverişi yap', due: goldenNow, priority: 'low', list: 2),
      _todo(14, 'Faturayı öde', due: daysAhead(1), list: 2),
      _todo(15, 'Kitap kulübü notları', due: daysAhead(2)),
      _todo(16, 'Pasaport yenile', due: daysAhead(16), priority: 'high'),
    ];

List<Map<String, dynamic>> _undated() => [
      _todo(21, 'Dişçiyi ara', priority: 'high'),
      _todo(22, 'Kombi bakımı', list: 2),
      _todo(23, 'Hediye fikirleri', priority: 'low'),
    ];

const _counts = {
  'open': 6,
  'today': 2,
  'upcoming': 3,
  'overdue': 1,
  'undated': 3,
  'done': 4,
};

TodosBundle _bundle(List<Map<String, dynamic>> todos) => TodosBundle.fromJson({
      'todos': todos,
      'meta': {
        'open_count': 9,
        'overdue_count': 1,
        'total_count': todos.length,
        'counts': _counts,
      },
    });

List<Event> _events() => [
      for (final json in [
        _event(31, 'Annemin doğum günü', on: [goldenNow], color: '#B8860B'),
        _event(32, 'Takım toplantısı',
            on: [goldenNow], start: '09:30', end: '10:15', location: 'Zoom'),
        _event(33, 'Diş hekimi randevusu',
            on: [goldenNow], start: '14:00', end: '14:45', color: '#B85450'),
        _event(34, 'Yoga',
            on: [daysAhead(1), daysAhead(8)],
            start: '18:00',
            end: '19:00',
            color: '#6B8E5A',
            location: 'Stüdyo',
            recurring: true),
        _event(35, 'Proje teslimi', on: [daysAhead(2)], color: '#B8860B'),
      ])
        Event.fromJson(json),
    ];

Event _yoga({bool full = true}) => Event.fromJson(_event(34, 'Yoga',
    on: [daysAhead(1)],
    start: '18:00',
    end: '19:00',
    color: '#6B8E5A',
    location: 'Stüdyo',
    recurring: true,
    full: full));

TodoListsBundle _lists() => TodoListsBundle.fromJson({
      'todo_lists': [
        {..._list(1), 'position': 0, 'archived': false, 'open_count': 2, 'todos_count': 5},
        {..._list(2), 'position': 1, 'archived': false, 'open_count': 3, 'todos_count': 4},
      ],
      'meta': const {'unlisted_open_count': 2},
    });

HomeSummary _home() => HomeSummary.fromJson({
      'today': ymd(goldenNow),
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'overdue_count': 1,
      'open_todos': 9,
    });

List<Override> _agendaOverrides() => [
      homeProvider.overrideWithBuild((ref, _) => Fetched(_home(), goldenNow)),
      todosProvider.overrideWithBuild((ref, notifier) => Fetched(
            _bundle(switch (notifier.query.filter) {
              'undated' => _undated(),
              _ => _open(),
            }),
            goldenNow,
          )),
      eventsProvider.overrideWith((ref, window) => Fetched(_events(), goldenNow)),
      todoListsProvider.overrideWith((ref) => Fetched(_lists(), goldenNow)),
      goalsProvider.overrideWith((ref) async => Fetched(
            GoalsBundle.fromJson({
              'active': [
                {
                  'id': 3,
                  'name': _fx('100 günde 100 kitap'),
                  'color': '#6B8E5A',
                  'goal_type': 'manual',
                  'status': 'active',
                  'progress_percent': 40.0,
                },
              ],
              'achieved': const [],
              'abandoned': const [],
            }),
            goldenNow,
          )),
      eventDetailProvider
          .overrideWith((ref, id) => Fetched(_yoga(), goldenNow)),
    ];

/// A screen that opens [open] once it is up — a sheet or a form over the
/// Agenda.
class _Opener extends StatefulWidget {
  final void Function(BuildContext context) open;
  const _Opener(this.open);

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) => const AgendaTabScreen();
}

void main() {
  setUpGoldens();

  goldenScreen(
    'agenda_upcoming',
    variants: GoldenVariant.withLargeText,
    (tester, _) async {
      await tester.pumpWidget(
          goldenHost(const AgendaTabScreen(), _agendaOverrides()));
      await tester.pumpAndSettle();
    },
  );

  goldenScreen('agenda_inbox', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const AgendaTabScreen(view: 'inbox'),
      _agendaOverrides(),
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('todo_sheet', (tester, _) async {
    final todo = Todo.fromJson(_todo(14, 'Faturayı öde',
        due: daysAhead(1), time: '18:00', list: 2, body: 'Elektrik ve su'));
    await tester.pumpWidget(goldenHost(
      _Opener((context) => openTodoSheet(context, existing: todo)),
      _agendaOverrides(),
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('event_sheet', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      _Opener((context) =>
          showEventSheet(context, _yoga(full: false), day: daysAhead(1))),
      _agendaOverrides(),
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('event_form', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      _Opener((context) => openEventForm(context, existing: _yoga())),
      _agendaOverrides(),
    ));
    await tester.pumpAndSettle();
  });
}
