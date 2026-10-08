/// Managing a habit from its detail sheet (contract G1 habit logs, G4):
/// logging any past day from the calendar, editing every field, archiving
/// with what it freezes, restoring from the archive, and deleting with what
/// it loses.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/date_utils.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/habits/archived_habits_screen.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_detail_sheet.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_form.dart';
import 'package:meridian_mobile/ui/screens/habits/habits_screen.dart';
import 'package:meridian_mobile/ui/screens/habits/widgets/habit_calendar.dart';
import 'package:meridian_mobile/ui/screens/habits/widgets/habit_check.dart';

import '../support/fake_api.dart';

/// Koşu (7) as `GET /habits/:id` answers: started 20 September, a chain
/// from then through today (4 October), done on the 3rd.
Map<String, dynamic> _detail({
  List<Map<String, Object>> goals = const [],
  bool archived = false,
  Set<DateTime> done = const {},
}) {
  final days = [
    for (
      var d = DateTime(2026, 9, 20);
      !d.isAfter(DateTime(2026, 10, 4));
      d = DateTime(d.year, d.month, d.day + 1)
    )
      d,
  ];
  return {
    ...habitJson(),
    'description': 'Sabah, kahvaltıdan önce',
    'start_date': '2026-09-20',
    'archived': archived,
    'archived_at': archived ? '2026-09-28T18:00:00.000+03:00' : null,
    'chain': [
      for (final d in days)
        {
          'date': isoDate(d),
          'status': d == DateTime(2026, 10, 3) || done.contains(d)
              ? 'completed'
              : d == DateTime(2026, 10, 4)
              ? 'today_pending'
              : 'missed',
        },
    ],
    'logged_days_count': 12,
    'completed_days_count': 10,
    'tracked_by_goals': goals,
  };
}

final _kosu = Habit.fromJson(habitJson());

Future<void> _pump(WidgetTester tester, FakeApi api, Widget home) async {
  tester.view.physicalSize = const Size(1170, 4200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/habits/archived',
        builder: (_, _) => const ArchivedHabitsScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(api.dio)],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        supportedLocales: AppL10n.supportedLocales,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    ),
  );
  await _settle(tester);
}

/// A screen with a button that opens Koşu's detail sheet.
Widget _opener() => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showHabitDetailSheet(context, _kosu),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await _settle(tester);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

Finder _day(String date) => find.byKey(ValueKey('habit-day-$date'));

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  setUpAll(initializeDateFormatting);

  group('logging a past day from the calendar', () {
    testWidgets('a tap on a past day opens it, and its check sets that day '
        'with PUT /habits/:id/logs/:date', (tester) async {
      // The server keeps what was set: the refetch after the write has it.
      final done = <DateTime>{};
      final api = FakeApi()
        ..onRequest(
          'GET /habits/7',
          (_) => {
            'habit': _detail(done: {...done}),
          },
        )
        ..onRequest('PUT /habits/7/logs/2026-10-02', (_) {
          done.add(DateTime(2026, 10, 2));
          return logAnswer(7, '2026-10-04', 0);
        });
      await _pump(tester, api, _opener());
      await _openSheet(tester);
      expect(find.text('Ekim 2026'), findsOneWidget);

      await _tapVisible(tester, _day('2026-10-02'));
      expect(find.text('Cuma, 2 Ekim'), findsOneWidget);
      expect(find.text('Yapılmadı'), findsOneWidget);

      await _tapVisible(
        tester,
        find.descendant(
          of: find.byType(HabitDayEditor),
          matching: find.byType(HabitCheck),
        ),
      );
      expect(api.bodiesOf('PUT /habits/7/logs/2026-10-02'), [
        {'count': 1},
      ]);
      expect(find.text('Yapıldı'), findsOneWidget);
      // Back-filled days never celebrate, and nothing went wrong.
      expect(tester.takeException(), isNull);
    });

    testWidgets('a day can be opened by a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
      await _pump(tester, api, _opener());
      await _openSheet(tester);
      await tester.ensureVisible(_day('2026-10-02'));
      await tester.pump();
      final node = tester.getSemantics(_day('2026-10-02'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.semantics.tap(find.semantics.byPredicate((n) => n.id == node.id));
      await _settle(tester);
      expect(find.text('Cuma, 2 Ekim'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('earlier months open back to the day the habit started; days '
        'before it and after today say why they cannot be logged', (
      tester,
    ) async {
      final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
      await _pump(tester, api, _opener());
      await _openSheet(tester);

      await _tapVisible(tester, _day('2026-10-05'));
      expect(find.text('Gelecek günler işaretlenemez.'), findsOneWidget);

      await _tapVisible(tester, find.byTooltip('Önceki ay'));
      expect(find.text('Eylül 2026'), findsOneWidget);
      // September is as far back as the habit goes.
      final previous = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Önceki ay'),
          matching: find.byType(IconButton),
        ),
      );
      expect(previous.onPressed, isNull);

      await _tapVisible(tester, _day('2026-09-19'));
      expect(find.textContaining('henüz yoktu'), findsOneWidget);
      await _tapVisible(tester, _day('2026-09-21'));
      expect(find.text('Yapılmadı'), findsOneWidget);
      expect(api.requests.where((r) => r.startsWith('PUT')), isEmpty);
    });

    testWidgets('a day the server refuses comes back as it was, with the '
        'server\'s reason', (tester) async {
      final api = FakeApi()
        ..on('GET /habits/7', {'habit': _detail()})
        ..on('PUT /habits/7/logs/2026-10-02', {
          'errors': {
            'base': ['x'],
          },
          'code': 'habit_archived',
        }, status: 422);
      await _pump(tester, api, _opener());
      await _openSheet(tester);
      await _tapVisible(tester, _day('2026-10-02'));
      await _tapVisible(
        tester,
        find.descendant(
          of: find.byType(HabitDayEditor),
          matching: find.byType(HabitCheck),
        ),
      );
      expect(find.text('Arşivlenmiş alışkanlık işaretlenemez'), findsWidgets);
      expect(find.text('Yapılmadı'), findsOneWidget);
    });

    testWidgets('an archived habit\'s calendar is read-only', (tester) async {
      final api = FakeApi()
        ..on('GET /habits/7', {'habit': _detail(archived: true)});
      await _pump(tester, api, _opener());
      await _openSheet(tester);
      expect(find.textContaining('Arşivde:'), findsOneWidget);
      await _tapVisible(tester, _day('2026-10-02'));
      expect(find.byType(HabitCheck), findsNothing);
      expect(find.text('Arşivlenmiş alışkanlık işaretlenemez'), findsOneWidget);
    });
  });

  testWidgets('edit: every field prefilled — the description written on the '
      'web included — and only the change is sent', (tester) async {
    final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
    await _pump(tester, api, _opener());
    await _openSheet(tester);

    await _tapVisible(tester, find.text('Düzenle'));
    expect(find.byType(HabitFormScreen), findsOneWidget);
    expect(find.text('Alışkanlığı düzenle'), findsOneWidget);
    expect(find.text('Sabah, kahvaltıdan önce'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Alışkanlık adı'),
      'Sabah koşusu',
    );
    await tester.pump();
    await _tapVisible(tester, find.text('Kaydet'));
    expect(api.bodiesOf('PATCH /habits/7'), [
      {'name': 'Sabah koşusu'},
    ]);
    expect(find.byType(HabitFormScreen), findsNothing);
    expect(find.text('Alışkanlık güncellendi ✓'), findsOneWidget);
  });

  testWidgets('edit: closing a changed form asks before dropping the change', (
    tester,
  ) async {
    final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
    await _pump(tester, api, _opener());
    await _openSheet(tester);
    await _tapVisible(tester, find.text('Düzenle'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Alışkanlık adı'),
      'Başka',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Kapat'));
    await _settle(tester);
    expect(find.text('Düzenlemeye devam'), findsOneWidget);
    expect(api.bodiesOf('PATCH /habits/7'), isEmpty);
  });

  testWidgets('archive: at once, with undo — which restores it', (
    tester,
  ) async {
    final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
    await _pump(tester, api, _opener());
    await _openSheet(tester);

    await _tapVisible(tester, find.text('Arşivle'));
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'no goal counts it: nothing to warn about',
    );
    expect(api.requests, contains('PATCH /habits/7/archive'));
    expect(find.text('“Koşu” arşivlendi'), findsOneWidget);

    await tester.tap(find.text('Geri al'));
    await _settle(tester);
    expect(api.requests, contains('PATCH /habits/7/unarchive'));
  });

  testWidgets('archive: a habit that goals count asks first, and says those '
      'goals freeze', (tester) async {
    final api = FakeApi()
      ..on('GET /habits/7', {
        'habit': _detail(
          goals: [
            {'id': 6667, 'name': 'Maraton', 'status': 'active'},
          ],
        ),
      });
    await _pump(tester, api, _opener());
    await _openSheet(tester);
    expect(
      find.textContaining('Maraton'),
      findsOneWidget,
      reason: 'the sheet says which goals count it',
    );

    await _tapVisible(tester, find.text('Arşivle'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('ilerlemeleri durur'),
      ),
      findsOneWidget,
    );
    await tester.tap(_inDialog('Vazgeç'));
    await _settle(tester);
    expect(api.requests, isNot(contains('PATCH /habits/7/archive')));

    await _tapVisible(tester, find.text('Arşivle'));
    await tester.tap(_inDialog('Arşivle'));
    await _settle(tester);
    expect(api.requests, contains('PATCH /habits/7/archive'));
  });

  testWidgets('an active habit is archived, never deleted, from its sheet', (
    tester,
  ) async {
    final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
    await _pump(tester, api, _opener());
    await _openSheet(tester);
    expect(find.text('Arşivle'), findsOneWidget);
    expect(find.text('Alışkanlığı sil'), findsNothing);
  });

  testWidgets('delete, from the archive: the dialog says what goes — the '
      'logged days and the goal links — and the habit leaves at once', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('GET /habits/7', {
        'habit': _detail(
          archived: true,
          goals: [
            {'id': 6667, 'name': 'Maraton', 'status': 'active'},
          ],
        ),
      });
    await _pump(tester, api, _opener());
    await _openSheet(tester);

    await _tapVisible(tester, find.text('Alışkanlığı sil'));
    expect(find.text('“Koşu” silinsin mi?'), findsOneWidget);
    final body = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.textContaining('12 gün'),
    );
    expect(body, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Maraton'),
      ),
      findsOneWidget,
    );
    await tester.tap(_inDialog('Sil'));
    await _settle(tester);
    expect(api.requests, contains('DELETE /habits/7'));
    expect(find.text('“Koşu” silindi'), findsOneWidget);
  });

  testWidgets('the Habits tab opens the archive, where a habit is restored '
      'in a tap', (tester) async {
    final api = FakeApi()
      ..onRequest('GET /habits', (request) {
        if (request.queryParameters['archived'] == true) {
          return {
            'habits': [
              {
                ...habitJson(id: 11, name: 'Kitap'),
                'archived': true,
                'archived_at': '2026-09-28T18:00:00.000+03:00',
              },
            ],
            'meta': habitsMeta(),
          };
        }
        return habitsJson();
      })
      ..on('PATCH /habits/11/unarchive', {'habit': habitJson(id: 11)});
    await _pump(tester, api, const HabitsScreen());

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Arşivlenmiş alışkanlıklar'));
    await _settle(tester);
    expect(find.byType(ArchivedHabitsScreen), findsOneWidget);
    expect(find.text('Kitap'), findsOneWidget);
    expect(find.text('Arşivlendi: 28 Eylül'), findsOneWidget);

    await tester.tap(find.text('Arşivden çıkar'));
    await _settle(tester);
    expect(api.requests, contains('PATCH /habits/11/unarchive'));
    expect(find.text('“Kitap” yeniden aktif'), findsOneWidget);
  });

  testWidgets('an empty archive says so', (tester) async {
    final api = FakeApi()
      ..onRequest(
        'GET /habits',
        (request) => {'habits': const [], 'meta': habitsMeta()},
      );
    await _pump(tester, api, const ArchivedHabitsScreen());
    expect(find.text('Arşivde alışkanlık yok'), findsOneWidget);
  });
}
