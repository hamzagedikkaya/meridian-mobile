/// Managing a habit from its detail sheet (contract G1 habit logs, G4):
/// logging any past day from the calendar, editing every field, archiving
/// with what it freezes, restoring from the archive, and deleting with what
/// it loses.
library;

import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/formats.dart' show setAppToday;
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/date_utils.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_form.dart';
import 'package:meridian_mobile/ui/screens/habits/archived_habits_screen.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_detail_sheet.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_form.dart';
import 'package:meridian_mobile/ui/screens/habits/habits_screen.dart';
import 'package:meridian_mobile/ui/screens/habits/widgets/habit_calendar.dart';
import 'package:meridian_mobile/ui/screens/habits/widgets/habit_day_cell.dart';
import 'package:meridian_mobile/ui/widgets/celebration_layer.dart';
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/stat_tile.dart';

import '../support/app_fonts.dart';
import '../support/app_harness.dart' show fixtureNow;
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

Future<void> _pump(
  WidgetTester tester,
  FakeApi api,
  Widget home, {
  Size size = const Size(1170, 4200),
  double textScale = 1,
}) async {
  setAppToday(fixtureNow);
  addTearDown(() => setAppToday(null));
  tester.view.physicalSize = size;
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
      overrides: [
        dioProvider.overrideWithValue(api.dio),
        // The fixtures' day, so their dates read the same on any run day.
        clockProvider.overrideWithValue(() => fixtureNow),
      ],
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
        // The app's celebration layer: a past day must not set it off.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: CelebrationLayer(child: child!),
        ),
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

/// The archive: Kitap (11), archived on 28 September; its detail says
/// what a delete would take.
FakeApi _archiveApi() => FakeApi()
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
  ..on('GET /habits/11', {
    'habit': {
      ...habitDetailJson(id: 11, name: 'Kitap', logged: 42),
      'archived': true,
      'archived_at': '2026-09-28T18:00:00.000+03:00',
    },
  })
  ..on('DELETE /habits/11', null, status: 204);

/// [finder]'s paragraph is on one line, at its own width — not squeezed
/// into a column a few letters wide.
void _expectOneLine(WidgetTester tester, Finder finder) {
  final p = tester.renderObject<RenderParagraph>(finder);
  expect(
    p.size.width,
    greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5),
  );
}

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
          matching: find.byType(CheckPop),
        ),
      );
      expect(api.bodiesOf('PUT /habits/7/logs/2026-10-02'), [
        {'count': 1},
      ]);
      expect(find.text('Yapıldı'), findsOneWidget);
      // Back-filled days never celebrate, and nothing went wrong.
      expect(find.byType(ConfettiBurst), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a past day that the server answers with a streak milestone '
        'and a perfect week celebrates nothing (tier 2 and 3)', (tester) async {
      final answer = logAnswer(7, '2026-10-04', 0);
      answer['habit'] = {
        ...(answer['habit'] as Map<String, dynamic>),
        'current_streak': 7,
      };
      answer['meta'] = {
        ...habitsMeta(completedToday: 2, totalActive: 2),
        'perfect_day': {
          'chain': [
            {'date': '2026-10-04', 'status': 'perfect'},
          ],
          'current_streak': 7,
          'longest_streak': 7,
        },
      };
      final api = FakeApi()
        ..on('GET /habits/7', {'habit': _detail()})
        ..on('PUT /habits/7/logs/2026-10-02', answer);
      // The Habits tab under the sheet: the list a tap there would
      // celebrate from.
      await _pump(tester, api, const HabitsScreen());
      await tester.tap(find.text('Koşu'));
      await _settle(tester);
      await _tapVisible(tester, _day('2026-10-02'));
      await _tapVisible(
        tester,
        find.descendant(
          of: find.byType(HabitDayEditor),
          matching: find.byType(CheckPop),
        ),
      );
      expect(api.bodiesOf('PUT /habits/7/logs/2026-10-02'), [
        {'count': 1},
      ]);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(ConfettiBurst), findsNothing);
        expect(find.text('7 gün · Koşu'), findsNothing);
        expect(find.text('İlk mükemmel hafta'), findsNothing);
      }
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
          matching: find.byType(CheckPop),
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
      expect(find.byType(CheckPop), findsNothing);
      expect(find.text('Arşivlenmiş alışkanlık işaretlenemez'), findsOneWidget);
    });
  });

  group('a day the habit as read does not cover', () {
    testWidgets('a habit older than the year read: a day before its chain is '
        'drawn without a log and cannot be set — no write from a guess', (
      tester,
    ) async {
      // A counter (8 a day) started in 2024; the detail reads 366 days, all
      // done.
      final days = [
        for (var i = 365; i >= 0; i--) DateTime(2026, 10, 4 - i),
      ];
      final api = FakeApi()
        ..on('GET /habits/7', {
          'habit': {
            ...habitJson(targetCount: 8, count: 8, completed: true),
            'start_date': '2024-01-01',
            'chain': [
              for (final d in days)
                {'date': isoDate(d), 'status': 'completed'},
            ],
            'tracked_by_goals': const [],
          },
        });
      await _pump(tester, api, _opener());
      await _openSheet(tester);
      for (var i = 0; i < 12; i++) {
        await _tapVisible(tester, find.byTooltip('Önceki ay'));
      }
      expect(find.text('Ekim 2025'), findsOneWidget);
      // Inside the chain: done.
      expect(
        tester
            .widget<HabitDayCellBox>(
              find.descendant(
                of: _day('2025-10-04'),
                matching: find.byType(HabitDayCellBox),
              ),
            )
            .state,
        HabitDayState.done,
      );
      // Before it: not known — no "missed" outline, no counter.
      expect(
        find.descendant(
          of: _day('2025-10-02'),
          matching: find.byType(HabitDayCellBox),
        ),
        findsNothing,
      );
      await _tapVisible(tester, _day('2025-10-02'));
      expect(
        find.text('Bu günün kaydı yüklenmedi, buradan değiştirilemez.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Bir artır'), findsNothing);
      expect(api.bodiesOf('PUT /habits/7/logs/2025-10-02'), isEmpty);
    });

    testWidgets('an archived habit: the days after its archive day — today '
        'too — have no log, never "missed" or "pending" (§5.1)', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('GET /habits/7', {
          'habit': {
            ..._detail(archived: true),
            // The contract's shape: the chain ends on the archive day.
            'chain': [
              for (var d = 20; d <= 28; d++)
                {
                  'date': isoDate(DateTime(2026, 9, d)),
                  'status': d == 26 ? 'completed' : 'missed',
                },
            ],
          },
        });
      await _pump(tester, api, _opener());
      await _openSheet(tester);
      Finder box(String day) => find.descendant(
        of: _day(day),
        matching: find.byType(HabitDayCellBox),
      );
      expect(box('2026-10-02'), findsNothing);
      expect(box('2026-10-04'), findsNothing);
      await _tapVisible(tester, find.byTooltip('Önceki ay'));
      expect(box('2026-09-30'), findsNothing);
      expect(tester.widget<HabitDayCellBox>(box('2026-09-27')).state,
          HabitDayState.missed);
      expect(tester.widget<HabitDayCellBox>(box('2026-09-26')).state,
          HabitDayState.done);
    });

    testWidgets('archived today: its open archive day is not drawn '
        '"pending", in the calendar or the heatmap', (tester) async {
      final api = FakeApi()
        ..on('GET /habits/7', {
          'habit': {
            // The chain ends today, the archive day, in today_pending.
            ..._detail(archived: true),
            'archived_at': '2026-10-04T10:00:00.000+03:00',
          },
        });
      await _pump(tester, api, _opener());
      await _openSheet(tester);
      Finder box(String day) => find.descendant(
        of: _day(day),
        matching: find.byType(HabitDayCellBox),
      );
      expect(box('2026-10-04'), findsNothing);
      expect(tester.widget<HabitDayCellBox>(box('2026-10-03')).state,
          HabitDayState.done);
      final heatmap = tester.widgetList<HabitDayCell>(find.descendant(
        of: find.byType(MiniHeatmap),
        matching: find.byType(HabitDayCell),
      ));
      expect(heatmap, isNotEmpty);
      expect(
        heatmap.map((c) => c.state),
        isNot(contains(HabitDayState.pending)),
      );
    });

    testWidgets('while the detail loads, a day before the list\'s two weeks '
        'cannot be set from them', (tester) async {
      final api = FakeApi()..hold('GET /habits/7');
      await _pump(tester, api, _opener());
      await _openSheet(tester);
      // The list's copy has 3 and 4 October only.
      await _tapVisible(tester, _day('2026-10-01'));
      expect(
        find.text('Bu günün kaydı yüklenmedi, buradan değiştirilemez.'),
        findsOneWidget,
      );
      expect(find.byType(CheckPop), findsNothing);
      api.release('GET /habits/7');
      await _settle(tester);
    });
  });

  testWidgets('a past day\'s check is read with its date, never as today', (
    tester,
  ) async {
    final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
    await _pump(tester, api, _opener());
    await _openSheet(tester);
    await _tapVisible(tester, _day('2026-10-03'));
    final check = tester.widget<CheckPop>(
      find.descendant(
        of: find.byType(HabitDayEditor),
        matching: find.byType(CheckPop),
      ),
    );
    expect(check.semanticLabel, 'Koşu, 3 Ekim 2026, yapıldı');
  });

  testWidgets('a habit with no record yet: no "0" shown or read out '
      '(§7.15)', (tester) async {
    final handle = tester.ensureSemantics();
    final api = FakeApi()
      ..on('GET /habits/7', {
        'habit': {..._detail(), 'current_streak': 0, 'longest_streak': 0},
      });
    await _pump(tester, api, _opener());
    await _openSheet(tester);
    final tiles = tester.widgetList<StatTile>(find.byType(StatTile)).toList();
    expect(tiles.map((t) => t.value), isNot(contains('0')));
    for (final t in tiles) {
      expect(t.semanticLabel ?? '', isNot(contains('0')));
    }
    expect(tiles.first.semanticLabel, 'Seri: henüz yok');
    handle.dispose();
  });

  group('the habit form\'s target', () {
    Widget newForm() => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => openHabitForm(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

    testWidgets('opening its keypad puts the system keyboard away: digits '
        'go to the target, not the name', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _pump(tester, FakeApi(), newForm());
        await _openSheet(tester);
        expect(tester.testTextInput.isVisible, isTrue, reason: 'name first');
        await tester.tap(find.text('günde 1 kez'));
        await _settle(tester);
        expect(find.byType(AmountKeypad), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
        // Back in the name: the keypad goes.
        await tester.tap(find.widgetWithText(TextField, 'Alışkanlık adı'));
        await _settle(tester);
        expect(find.byType(AmountKeypad), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the name taken up without a tap — a screen reader, a '
        'hardware keyboard — closes the keypad too', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _pump(tester, FakeApi(), newForm());
        await _openSheet(tester);
        await tester.tap(find.text('günde 1 kez'));
        await _settle(tester);
        expect(find.byType(AmountKeypad), findsOneWidget);
        // Focus and the keyboard, as a screen reader's activation asks for
        // them: TextField.onTap does not run.
        await tester.showKeyboard(
          find.widgetWithText(TextField, 'Alışkanlık adı'),
        );
        await _settle(tester);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(find.byType(AmountKeypad), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a weekly target is at most 7 days, a monthly one 31, and a '
        'daily one taken weekly comes down to 7', (tester) async {
      await _pump(tester, FakeApi(), newForm());
      await _openSheet(tester);
      for (var i = 0; i < 9; i++) {
        await tester.tap(find.byTooltip('Bir artır'));
        await tester.pump();
      }
      expect(find.text('günde 10 kez'), findsOneWidget);
      await _tapVisible(tester, find.text('Haftalık'));
      expect(find.text('haftada 7 gün'), findsOneWidget);
      final plus = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Bir artır'),
          matching: find.byType(IconButton),
        ),
      );
      expect(plus.onPressed, isNull);
      await _tapVisible(tester, find.text('Aylık'));
      await _tapVisible(tester, find.text('ayda 7 gün'));
      await tester.tap(find.text('3'));
      await tester.tap(find.text('5'));
      await tester.pump();
      expect(find.text('ayda 3 gün'), findsOneWidget, reason: '35 refused');
      await tester.tap(find.text('1'));
      await tester.pump();
      expect(find.text('ayda 31 gün'), findsOneWidget);
    });
  });

  testWidgets('the heatmap\'s weekday names are whole at 200 % text (§8.3)', (
    tester,
  ) async {
    final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
    await _pump(tester, api, _opener(), textScale: 2);
    await _openSheet(tester);
    for (final name in ['Pzt', 'Çar', 'Cum']) {
      final label = find.descendant(
        of: find.byType(MiniHeatmap),
        matching: find.text(name),
      );
      final p = tester.renderObject<RenderParagraph>(label);
      expect(
        p.size.width,
        greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5),
        reason: name,
      );
      expect(
        p.size.height,
        greaterThanOrEqualTo(
          p.getMaxIntrinsicHeight(double.infinity) - 0.5,
        ),
        reason: name,
      );
    }
    expect(tester.takeException(), isNull);
  });

  group('what the sheet says while it stays open is seen over it', () {
    testWidgets('an archive that fails', (tester) async {
      final api = FakeApi()
        ..on('GET /habits/7', {'habit': _detail()})
        ..fail('PATCH /habits/7/archive', 500);
      await _pump(tester, api, _opener(), size: const Size(1080, 2340));
      await _openSheet(tester);
      await _tapVisible(tester, find.text('Arşivle'));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.text('Arşivlenemedi, tekrar dene').hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('a restore that fails', (tester) async {
      final api = FakeApi()
        ..on('GET /habits/7', {'habit': _detail(archived: true)})
        ..fail('PATCH /habits/7/unarchive', 500);
      await _pump(tester, api, _opener(), size: const Size(1080, 2340));
      await _openSheet(tester);
      await _tapVisible(tester, find.text('Arşivden çıkar'));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.textContaining('Arşivden çıkarılamadı').hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('an edit saved from the pencil', (tester) async {
      final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
      await _pump(tester, api, _opener(), size: const Size(1080, 2340));
      await _openSheet(tester);
      await _tapVisible(tester, find.byTooltip('Düzenle'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Alışkanlık adı'),
        'Sabah koşusu',
      );
      await tester.pump();
      await _tapVisible(tester, find.text('Kaydet'));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.text('Alışkanlık güncellendi').hitTestable(),
        findsOneWidget,
      );
    });
  });

  testWidgets('edit: every field prefilled — the description written on the '
      'web included — and only the change is sent', (tester) async {
    final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
    await _pump(tester, api, _opener());
    await _openSheet(tester);

    await _tapVisible(tester, find.byTooltip('Düzenle'));
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
    expect(find.text('Alışkanlık güncellendi'), findsOneWidget);
  });

  testWidgets('edit: closing a changed form asks before dropping the change', (
    tester,
  ) async {
    final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
    await _pump(tester, api, _opener());
    await _openSheet(tester);
    await _tapVisible(tester, find.byTooltip('Düzenle'));
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

  testWidgets('"Bu alışkanlık için hedef koy" opens the goal form as a goal '
      'for this habit', (tester) async {
    final api = FakeApi()..on('GET /habits/7', {'habit': _detail()});
    await _pump(tester, api, _opener());
    await _openSheet(tester);
    await tester.ensureVisible(find.text('Bu alışkanlık için hedef koy'));
    await tester.tap(find.text('Bu alışkanlık için hedef koy'));
    await _settle(tester);
    final form = tester.widget<GoalFormScreen>(find.byType(GoalFormScreen));
    expect(form.initialHabitId, 7);
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

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await _settle(tester);
    await tester.tap(find.text('Arşiv'));
    await _settle(tester);
    expect(find.byType(ArchivedHabitsScreen), findsOneWidget);
    expect(find.text('Kitap'), findsOneWidget);
    expect(find.text('Arşivlendi: 28 Eylül'), findsOneWidget);

    await tester.tap(find.text('Arşivden çıkar'));
    await _settle(tester);
    expect(api.requests, contains('PATCH /habits/11/unarchive'));
    expect(find.text('“Kitap” yeniden aktif'), findsOneWidget);
  });

  testWidgets('the archive\'s ⋯ deletes a habit for good, after the dialog '
      'that says how many logged days go', (tester) async {
    final api = _archiveApi();
    await _pump(tester, api, const ArchivedHabitsScreen());
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await _settle(tester);
    await tester.tap(find.text('Kalıcı olarak sil'));
    await _settle(tester);
    expect(api.requests, contains('GET /habits/11'));
    expect(find.text('“Kitap” silinsin mi?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('42 gün'),
      ),
      findsOneWidget,
    );
    await tester.tap(_inDialog('Sil'));
    await _settle(tester);
    expect(api.requests, contains('DELETE /habits/11'));
    expect(find.text('Kitap'), findsNothing);
    expect(tester.takeException(), isNull);
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

  // Last in the file: once loaded, the real fonts stay for every test after.
  group('with the real fonts', () {
    setUpAll(loadAppFonts);

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('the archive on a phone at ×$scale text: the name and its '
          'date readable, nothing overflows (§8.3)', (tester) async {
        await _pump(
          tester,
          _archiveApi(),
          const ArchivedHabitsScreen(),
          size: const Size(1080, 2340),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Kitap'), findsOneWidget);
        expect(tester.getSize(find.text('Kitap')).width, greaterThan(40));
        _expectOneLine(tester, find.text('Kitap'));
        _expectOneLine(tester, find.text('Arşivlendi: 28 Eylül'));
        _expectOneLine(tester, find.text('Arşivden çıkar'));
        // Both actions still there, at least 48 dp.
        final restore = tester.getSize(
          find.widgetWithText(TextButton, 'Arşivden çıkar'),
        );
        expect(restore.width, greaterThanOrEqualTo(48));
        expect(restore.height, greaterThanOrEqualTo(48));
        expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
      });
    }
  });
}
