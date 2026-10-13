import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/theme/entity_color.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_card.dart';
import 'package:meridian_mobile/ui/screens/habits/habits_screen.dart';
import 'package:meridian_mobile/ui/screens/habits/widgets/counter_pill.dart';
import 'package:meridian_mobile/ui/screens/habits/widgets/habit_day_cell.dart';
import 'package:meridian_mobile/ui/widgets/celebration_layer.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/nokturn_card.dart';
import 'package:meridian_mobile/ui/widgets/paced_progress_bar.dart';

import '../support/app_fonts.dart';
import '../support/fake_api.dart';

/// A rich /habits payload, shaped exactly like scratchpad/api-samples.json,
/// exercising the edge cases the screen must survive:
///   - habit 50: daily, target_count 5  → CounterPill
///   - habit 46: weekly, target_count 3 → period pill (no daily chain)
///   - habit 49: weekly, target_count 1 → HabitCheck + period pill
///   - habit 44: daily, 14-day chain all "missed"
///   - habit 45: daily, single-element chain
///   - perfect_day: 30-day chain with mixed statuses
const String _populatedJson = r'''
{
  "habits": [
    {
      "id": 50, "name": "5ee", "description": "ee", "frequency": "daily",
      "target_count": 5, "color": "#b8860b", "goal_id": null,
      "current_streak": 0, "longest_streak": 1, "completion_rate_30d": 0.0,
      "today": { "date": "2026-07-11", "completed": false, "count": 2 },
      "chain": [ { "date": "2026-07-11", "status": "today_pending" } ]
    },
    {
      "id": 46, "name": "Günde 2L su iç ve bol bol yürü", "description": "",
      "frequency": "weekly", "target_count": 3, "color": "#6b8e5a",
      "goal_id": null, "current_streak": 0, "longest_streak": 14,
      "completion_rate_30d": 0.0,
      "today": { "date": "2026-07-11", "completed": false, "count": 0 },
      "chain": [ { "date": "2026-07-11", "status": "today_pending" } ],
      "period": {
        "range_start": "2026-07-06", "range_end": "2026-07-12",
        "completed_count": 2, "complete": false
      }
    },
    {
      "id": 49, "name": "Gym session", "description": "Three times per week.",
      "frequency": "weekly", "target_count": 1, "color": "#B85450",
      "goal_id": null, "current_streak": 0, "longest_streak": 7,
      "completion_rate_30d": 1.0,
      "today": { "date": "2026-07-11", "completed": true, "count": 1 },
      "chain": [ { "date": "2026-07-11", "status": "today_pending" } ],
      "period": {
        "range_start": "2026-07-06", "range_end": "2026-07-12",
        "completed_count": 1, "complete": true
      }
    },
    {
      "id": 44, "name": "Morning workout", "description": "Stretch + yoga.",
      "frequency": "daily", "target_count": 1, "color": "#D4A574",
      "goal_id": null, "current_streak": 0, "longest_streak": 7,
      "completion_rate_30d": 0.0,
      "today": { "date": "2026-07-11", "completed": false, "count": 0 },
      "chain": [
        { "date": "2026-06-28", "status": "missed" },
        { "date": "2026-06-29", "status": "missed" },
        { "date": "2026-06-30", "status": "missed" },
        { "date": "2026-07-01", "status": "missed" },
        { "date": "2026-07-02", "status": "missed" },
        { "date": "2026-07-03", "status": "missed" },
        { "date": "2026-07-04", "status": "missed" },
        { "date": "2026-07-05", "status": "missed" },
        { "date": "2026-07-06", "status": "missed" },
        { "date": "2026-07-07", "status": "missed" },
        { "date": "2026-07-08", "status": "missed" },
        { "date": "2026-07-09", "status": "missed" },
        { "date": "2026-07-10", "status": "missed" },
        { "date": "2026-07-11", "status": "missed" }
      ]
    },
    {
      "id": 45, "name": "Read 30 pages", "description": "Fiction.",
      "frequency": "daily", "target_count": 1, "color": "#6B8FA0",
      "goal_id": null, "current_streak": 3, "longest_streak": 7,
      "completion_rate_30d": 0.42,
      "today": { "date": "2026-07-11", "completed": false, "count": 0 },
      "chain": [ { "date": "2026-07-11", "status": "completed" } ]
    }
  ],
  "meta": {
    "completed_today": 1,
    "total_active": 5,
    "perfect_day": {
      "chain": [
        { "date": "2026-06-12", "status": "perfect" },
        { "date": "2026-06-13", "status": "partial" },
        { "date": "2026-06-14", "status": "missed" },
        { "date": "2026-06-15", "status": "completed" },
        { "date": "2026-06-16", "status": "no_habits" },
        { "date": "2026-06-17", "status": "today_pending" }
      ],
      "current_streak": 2,
      "longest_streak": 9
    }
  }
}
''';

/// All-complete case (X == Y): every habit done, single-element perfect chain.
/// Exercises the "Hepsi tamam" badge + pct==1.0 progress bar on first build,
/// and the confetti guard (must NOT fire on build, only on transition).
const String _allDoneJson = r'''
{
  "habits": [
    {
      "id": 60, "name": "Sabah esnemesi", "description": "",
      "frequency": "daily", "target_count": 1, "color": "#D4A853",
      "goal_id": null, "current_streak": 5, "longest_streak": 5,
      "completion_rate_30d": 1.0,
      "today": { "date": "2026-07-11", "completed": true, "count": 1 },
      "chain": [ { "date": "2026-07-11", "status": "completed" } ]
    }
  ],
  "meta": {
    "completed_today": 1,
    "total_active": 1,
    "perfect_day": {
      "chain": [ { "date": "2026-07-11", "status": "perfect" } ],
      "current_streak": 1,
      "longest_streak": 1
    }
  }
}
''';

HabitsBundle _bundle(String json) =>
    HabitsBundle.fromJson(jsonDecode(json) as Map<String, dynamic>);

const _delegates = [
  AppL10n.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _app(HabitsBundle bundle, {double textScale = 1}) {
  return ProviderScope(
    overrides: [
      habitsProvider.overrideWithBuild(
        (ref, _) async => Fetched(bundle, DateTime(2026, 7, 11)),
      ),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: _delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const HabitsScreen(),
    ),
  );
}

/// The Habits tab against the fake server, under the app's celebration
/// layer.
Widget _live(FakeApi api) => ProviderScope(
  overrides: [dioProvider.overrideWithValue(api.dio)],
  child: MaterialApp(
    theme: buildTheme(Brightness.dark),
    locale: const Locale('tr'),
    supportedLocales: AppL10n.supportedLocales,
    localizationsDelegates: _delegates,
    builder: (context, child) => CelebrationLayer(child: child!),
    home: const HabitsScreen(),
  ),
);

/// A widget whose semantics label is [label] (a number that rolls reads
/// as one label).
Finder _labelled(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340); // 360×780 dp
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  testWidgets('renders populated habits with all edge-case shapes', (t) async {
    t.view.physicalSize = const Size(1080, 4200);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(_bundle(_populatedJson)));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);

    // App bar + the hero's count ("1 / 5 tamamlandı", its number rolling).
    expect(find.text('Alışkanlıklar'), findsOneWidget);
    expect(_labelled('1 / 5 tamamlandı'), findsOneWidget);

    // The perfect-day streak, with its record, in the hero.
    expect(
      find.textContaining('Mükemmel seri 2 · Rekor 9', findRichText: true),
      findsOneWidget,
    );

    // A long Turkish habit name renders (two lines at most, no overflow).
    expect(find.text('Günde 2L su iç ve bol bol yürü'), findsOneWidget);

    // Weekly habit period pills ("Bu hafta n/target").
    expect(find.text('Bu hafta 2/3'), findsOneWidget);
    expect(find.text('Bu hafta 1/1'), findsOneWidget);

    // CounterPill for the target_count>1 daily habit.
    expect(find.text('2/5'), findsOneWidget);

    // A broken streak is a new one, never "0" by a flame.
    expect(find.text('Yeni seri · Rekor 7'), findsWidgets);
  });

  testWidgets('no FAB covers a card: new habits start from the app bar and '
      'the dashed row that ends the list', (t) async {
    _phone(t);
    await t.pumpWidget(_app(_bundle(_populatedJson)));
    await t.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.widgetWithText(TextButton, 'Yeni'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Yeni alışkanlık'), 200);
    expect(find.text('Yeni alışkanlık'), findsOneWidget);
    expect(
      t
          .getSize(
            find
                .ancestor(
                  of: find.text('Yeni alışkanlık'),
                  matching: find.byType(ConstrainedBox),
                )
                .first,
          )
          .height,
      greaterThanOrEqualTo(56),
    );
  });

  testWidgets('on a 360×780 phone the first three cards sit above the fold', (
    t,
  ) async {
    _phone(t);
    final bundle = HabitsBundle.fromJson({
      'habits': [
        habitJson(id: 1, name: 'Sabah koşusu'),
        habitJson(id: 2, name: 'Su', targetCount: 8, count: 5),
        habitJson(id: 3, name: 'Kitap oku'),
        habitJson(id: 4, name: 'Meditasyon'),
      ],
      'meta': habitsMeta(totalActive: 4),
    });
    await t.pumpWidget(_app(bundle));
    await t.pumpAndSettle();
    // In the app the status bar takes 24 dp and the nav bar 80 of the 780.
    for (final id in [1, 2, 3]) {
      expect(
        t.getRect(find.byKey(ValueKey('habit-$id'))).bottom,
        lessThanOrEqualTo(780 - 24 - 80),
        reason: '$id',
      );
    }
  });

  testWidgets('open habits first, the ones done today after', (t) async {
    t.view.physicalSize = const Size(1080, 4200);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(_bundle(_populatedJson)));
    await t.pumpAndSettle();
    final ids = [
      for (final e in t.widgetList<KeyedSubtree>(
        find.byWidgetPredicate(
          (w) =>
              w is KeyedSubtree &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('habit-'),
        ),
      ))
        (e.key! as ValueKey<String>).value,
    ];
    // Gym session (49) is done today: it goes after the open ones.
    expect(ids, ['habit-50', 'habit-46', 'habit-44', 'habit-45', 'habit-49']);
  });

  testWidgets('empty: starter chips — a tap adds that habit at once', (
    t,
  ) async {
    final api = FakeApi()
      ..on('GET /habits', {'habits': const [], 'meta': habitsMeta()});
    await t.pumpWidget(_live(api));
    await _settle(t);

    expect(t.takeException(), isNull);
    expect(find.text('İlk alışkanlığını seç'), findsOneWidget);
    for (final chip in [
      'Su · günde 8',
      'Yürüyüş',
      'Kitap · 10 sayfa',
      'Erken yat',
      'Meditasyon',
      'Özel…',
    ]) {
      expect(find.text(chip), findsOneWidget, reason: chip);
    }
    // The chips are the way in: no second "new" control.
    expect(find.widgetWithText(TextButton, 'Yeni'), findsNothing);

    await t.tap(find.text('Su · günde 8'));
    await _settle(t);
    expect(api.bodiesOf('POST /habits').single, {
      'name': 'Su',
      'frequency': 'daily',
      'target_count': 8,
      'color': '#6B8FA0',
      'description': null,
      'goal_id': null,
    });
    await t.pumpAndSettle();
  });

  testWidgets('renders all-complete (X==Y) without confetti crash', (t) async {
    await t.pumpWidget(_app(_bundle(_allDoneJson)));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    // pct==1.0 progress bar + "Hepsi tamam" badge, and no burst on build.
    expect(_labelled('1 / 1 tamamlandı'), findsOneWidget);
    expect(find.text('Hepsi tamam'), findsOneWidget);
    expect(find.byType(ConfettiBurst), findsNothing);
    // The perfect-day streak stays beside the pill: the day just done is
    // what it counts.
    expect(find.textContaining('Mükemmel seri 1'), findsOneWidget);
    // Made today (no day before today in its chain, no start date): no
    // "%100 (30g)" or "%0 (30g)" yet.
    expect(find.textContaining('(30g)'), findsNothing);
  });

  testWidgets('a habit with a day of history shows its 30-day rate', (t) async {
    await t.pumpWidget(_app(_bundle(_populatedJson)));
    await t.pumpAndSettle();
    expect(find.textContaining('(30g)'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('the tap that finishes the day bursts from its check (tier 2), '
      'once; the card waits, then moves after the open ones', (t) async {
    _phone(t);
    final api = FakeApi()
      ..on('GET /habits', {
        'habits': [
          habitJson(),
          habitJson(id: 8, name: 'Su', completed: true, count: 1),
        ],
        'meta': habitsMeta(completedToday: 1),
      })
      ..on('PUT /habits/7/logs/2026-10-04', {
        ...logAnswer(7, '2026-10-04', 1),
        'meta': habitsMeta(completedToday: 2),
      });
    await t.pumpWidget(_live(api));
    await _settle(t);
    expect(find.byType(ConfettiBurst), findsNothing);

    final card = find.byKey(const ValueKey('habit-7'));
    // Its place in the list, under the hero — which may grow a line as
    // "Hepsi tamam" joins it.
    final hero = find.ancestor(
      of: find.byType(PacedProgressBar),
      matching: find.byType(NokturnCard),
    );
    double place() => t.getRect(card).top - t.getRect(hero).bottom;
    final top = place();
    await t.tap(find.descendant(of: card, matching: find.byType(CheckPop)));
    await t.pump();
    await t.pump();
    expect(find.byType(ConfettiBurst), findsOneWidget);
    await _settle(t);
    expect(place(), top, reason: 'it keeps its place a while');
    // Once: the burst ends, and neither the server's answer nor the move
    // that follows bursts again.
    var burstGone = false;
    for (var i = 0; i < 100; i++) {
      await t.pump(const Duration(milliseconds: 16));
      final bursts = find.byType(ConfettiBurst).evaluate().length;
      expect(bursts, lessThanOrEqualTo(1));
      if (bursts == 0) burstGone = true;
      if (burstGone) expect(bursts, 0, reason: 'a second burst');
    }
    expect(burstGone, isTrue);
    await t.pumpAndSettle();
    expect(find.byType(ConfettiBurst), findsNothing);
    expect(place(), top, reason: 'both are done: the order is the server\'s');
    expect(t.takeException(), isNull);
  });

  testWidgets('a refused re-check after a celebrated day does not give the '
      'day back: the accepted one after it does not burst again', (t) async {
    _phone(t);
    const key = 'PUT /habits/7/logs/2026-10-04';
    final api = FakeApi()
      ..on('GET /habits', {
        'habits': [habitJson()],
        'meta': habitsMeta(totalActive: 1),
      });
    void accept() => api.onRequest(key, (request) {
          final body = request.data is String
              ? jsonDecode(request.data as String)
              : request.data;
          final count = (body as Map)['count'] as int;
          return {
            ...logAnswer(7, '2026-10-04', count),
            'meta': habitsMeta(completedToday: count, totalActive: 1),
          };
        });
    accept();
    await t.pumpWidget(_live(api));
    await _settle(t);
    final check = find.descendant(
      of: find.byKey(const ValueKey('habit-7')),
      matching: find.byType(CheckPop),
    );
    var bursts = 0;
    Future<void> tapAndCount() async {
      await t.tap(check);
      var shown = false;
      for (var i = 0; i < 160; i++) {
        await t.pump(const Duration(milliseconds: 16));
        final now = find.byType(ConfettiBurst).evaluate().isNotEmpty;
        if (now && !shown) bursts++;
        shown = now;
      }
      await t.pumpAndSettle();
    }

    // (1) The day finished, the write accepted: the day's burst.
    await tapAndCount();
    expect(bursts, 1);
    // (2) Unchecked.
    await tapAndCount();
    // (3) Checked again, the write refused.
    api.fail(key, 500);
    await tapAndCount();
    // (4) Checked again, accepted: the day was celebrated in (1).
    accept();
    await tapAndCount();
    expect(api.requests.where((r) => r == key), hasLength(4));
    expect(bursts, 1, reason: 'once a day (§5.7)');
    expect(t.takeException(), isNull);
  });

  testWidgets('a counter at its target cannot go past it', (t) async {
    final api = FakeApi()
      ..on('GET /habits', {
        'habits': [
          habitJson(
            id: 8,
            name: 'Su',
            targetCount: 3,
            count: 3,
            completed: true,
          ),
        ],
        'meta': habitsMeta(completedToday: 1, totalActive: 1),
      });
    final handle = t.ensureSemantics();
    await t.pumpWidget(_live(api));
    await _settle(t);
    final pill = find.byType(CounterPill);
    expect(find.text('3/3'), findsOneWidget);
    await t.tap(
      find.descendant(of: pill, matching: find.byIcon(Icons.add_rounded)),
    );
    await _settle(t);
    expect(api.requests.where((r) => r.startsWith('PUT')), isEmpty);
    final data = t.getSemantics(pill).getSemanticsData();
    expect(data.value, '3/3');
    expect(data.hasAction(SemanticsAction.increase), isFalse);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    handle.dispose();
    await t.pumpAndSettle();
  });

  testWidgets('a habit checked off keeps its place 1200 ms, then moves '
      'after the open ones', (t) async {
    _phone(t);
    final api = FakeApi()
      ..on('GET /habits', {
        'habits': [
          habitJson(),
          habitJson(id: 8, name: 'Su', targetCount: 3),
          habitJson(id: 9, name: 'Kitap'),
        ],
        'meta': habitsMeta(totalActive: 3),
      })
      ..on('PUT /habits/7/logs/2026-10-04', {
        ...logAnswer(7, '2026-10-04', 1),
        'meta': habitsMeta(completedToday: 1, totalActive: 3),
      });
    await t.pumpWidget(_live(api));
    await _settle(t);
    double top(int id) => t.getRect(find.byKey(ValueKey('habit-$id'))).top;
    final first = top(7);

    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('habit-7')),
        matching: find.byType(CheckPop),
      ),
    );
    await _settle(t);
    expect(top(7), first, reason: 'it lingers where it was');
    expect(
      find.byType(ConfettiBurst),
      findsNothing,
      reason: 'two habits are still open',
    );

    await t.pump(const Duration(milliseconds: 1300));
    await t.pumpAndSettle();
    expect(top(7), greaterThan(top(9)), reason: 'done ones go last');
    expect(top(8), first);
  });

  testWidgets('a starter chip tapped twice while its habit is on its way '
      'adds it once (D29)', (t) async {
    final api = FakeApi()
      ..on('GET /habits', {'habits': const [], 'meta': habitsMeta()})
      ..hold('POST /habits');
    await t.pumpWidget(_live(api));
    await _settle(t);

    await t.tap(find.text('Su · günde 8'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Su · günde 8'), warnIfMissed: false);
    await t.pump();
    expect(api.requests.where((r) => r == 'POST /habits'), hasLength(1));

    api.release('POST /habits');
    await _settle(t);
    // Added: its chip stays off until the list that has it arrives.
    await t.tap(find.text('Su · günde 8'), warnIfMissed: false);
    await _settle(t);
    expect(api.requests.where((r) => r == 'POST /habits'), hasLength(1));
    await t.pumpAndSettle();
  });

  testWidgets('a done habit unchecked moves up without the cards below it '
      'jumping: its ghost collapses at its old place (§5.4)', (t) async {
    _phone(t);
    final api = FakeApi()
      ..on('GET /habits', {
        // The server's order: Koşu first. Done, it is shown last.
        'habits': [
          habitJson(completed: true, count: 1),
          habitJson(id: 8, name: 'Su'),
          habitJson(id: 9, name: 'Kitap'),
        ],
        'meta': habitsMeta(completedToday: 1, totalActive: 3),
      });
    await t.pumpWidget(_live(api));
    await _settle(t);
    double top(int id) => t.getRect(find.byKey(ValueKey('habit-$id'))).top;
    expect(top(8), lessThan(top(9)));
    expect(top(9), lessThan(top(7)));

    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('habit-7')),
        matching: find.byType(CheckPop),
      ),
    );
    await t.pump();
    var last = (top(8), top(9));
    var moved = false;
    for (var i = 0; i < 120; i++) {
      await t.pump(const Duration(milliseconds: 16));
      final now = (top(8), top(9));
      final ghost = find.byKey(const ValueKey('habit-ghost-7'));
      if (!moved && ghost.evaluate().isNotEmpty) {
        moved = true;
        // The frame the move starts: nothing below shifts yet, and the
        // ghost is where the card was — under Kitap.
        expect((now.$1 - last.$1).abs(), lessThanOrEqualTo(2));
        expect((now.$2 - last.$2).abs(), lessThanOrEqualTo(2));
        expect(t.getRect(ghost).top, greaterThan(now.$2));
      }
      // Then a glide: never a card's height in one frame.
      expect((now.$1 - last.$1).abs(), lessThan(30), reason: 'frame $i');
      expect((now.$2 - last.$2).abs(), lessThan(30), reason: 'frame $i');
      last = now;
    }
    expect(moved, isTrue);
    await t.pumpAndSettle();
    expect(top(7), lessThan(top(8)), reason: 'open again: server order');
    expect(top(8), lessThan(top(9)));
    expect(t.takeException(), isNull);
  });

  testWidgets('a card is one button for a screen reader: its name, tap and '
      'long press on one node, no separator read out (§8.4)', (t) async {
    final handle = t.ensureSemantics();
    final api = FakeApi()..on('GET /habits', habitsJson());
    await t.pumpWidget(_live(api));
    await _settle(t);

    final data = t.getSemantics(find.text('Koşu')).getSemanticsData();
    expect(data.label, startsWith('Koşu'));
    expect(data.label, contains('%40'));
    expect(data.label, isNot(contains('·')));
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.longPress), isTrue);
    handle.dispose();
  });

  testWidgets('a counter step rebuilds its own card and the hero, not the '
      'list or the other cards (§8.8)', (t) async {
    _phone(t);
    final api = FakeApi()..on('GET /habits', habitsJson());
    await t.pumpWidget(_live(api));
    await _settle(t);
    expect(find.text('1/3'), findsOneWidget);

    final built = <String>[];
    debugOnRebuildDirtyWidget = (element, _) {
      final w = element.widget;
      if (w is HabitCard) built.add('card-${w.habit.id}');
      if (w is HabitsScreen) built.add('list');
      if (w is PerfectDayDots && w.count == 14) built.add('hero');
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('habit-8')),
        matching: find.byIcon(Icons.add_rounded),
      ),
    );
    await _settle(t);
    debugOnRebuildDirtyWidget = null;

    expect(api.bodiesOf('PUT /habits/8/logs/2026-10-04'), [
      {'count': 2},
    ]);
    expect(find.text('2/3'), findsOneWidget);
    expect(built, contains('card-8'));
    expect(built, isNot(contains('card-7')));
    expect(built, isNot(contains('list')));
    await t.pumpAndSettle();
  });

  test('a missed day\'s outline stands out from the card (3:1 or more), '
      'in both themes', () {
    for (final c in [NokturnColors.dark, NokturnColors.light]) {
      final colors = HabitDayColors.of(c, c.gold);
      expect(colors.missed, c.inkDisabled);
      expect(
        contrastRatio(colors.missed, c.surface1),
        greaterThanOrEqualTo(3.0),
        reason: '${c.isDark}',
      );
    }
  });

  // Last in the file: once loaded, the real fonts stay for every test after.
  group('with the real fonts', () {
    setUpAll(loadAppFonts);

    for (final scale in [1.0, 1.3]) {
      testWidgets('"Hepsi tamam" is never cut on a phone, in Turkish '
          '(×$scale, §10.1-18)', (t) async {
        _phone(t);
        await t.pumpWidget(_app(_bundle(_allDoneJson), textScale: scale));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final pill = t.renderObject<RenderParagraph>(find.text('Hepsi tamam'));
        expect(pill.didExceedMaxLines, isFalse);
        // On one line, at its own width.
        expect(
          pill.size.width,
          greaterThanOrEqualTo(
            pill.getMaxIntrinsicWidth(double.infinity) - 0.5,
          ),
        );
      });
    }
  });
}
