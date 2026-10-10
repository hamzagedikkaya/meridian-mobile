import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/sync.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_form.dart';
import 'package:meridian_mobile/ui/screens/habits/habits_screen.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/today_skeleton.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/todo_row.dart';
import 'package:meridian_mobile/ui/screens/agenda/agenda_screen.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/offline_banner.dart';

import '../support/fake_api.dart';

Widget _app(
  Widget home,
  List<Override> overrides, {
  Duration? Function(int retryCount, Object error)? retry,
}) =>
    ProviderScope(
      overrides: overrides,
      retry: retry,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        supportedLocales: AppL10n.supportedLocales,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

void _tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 3900);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps until the fake API has answered and the providers have settled.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

bool _checked(WidgetTester tester, Finder habitCard) => tester
    .widget<CheckPop>(
        find.descendant(of: habitCard, matching: find.byType(CheckPop)))
    .checked;

/// GET /home once Su (8) is at [count] of 3.
Map<String, dynamic> _homeWithSuAt(int count) {
  final home = homeJson();
  home['today_habits'] = [
    for (final habit in home['today_habits'] as List<Map<String, dynamic>>)
      if (habit['id'] == 8)
        {...habit, 'today_count': count, 'completed_today': count >= 3}
      else
        habit,
  ];
  return home;
}

const _log7 = 'PUT /habits/7/logs/2026-10-04';
const _log8 = 'PUT /habits/8/logs/2026-10-04';

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('Today keeps its data on screen while it refetches, with only '
      'a thin hint', (tester) async {
    _tallPhone(tester);
    final gate = Completer<void>();
    var builds = 0;
    await tester.pumpWidget(_app(const TodayScreen(), [
      currentUserProvider.overrideWithValue(null),
      homeProvider.overrideWithBuild((ref, _) async {
        if (++builds > 1) await gate.future;
        return Fetched(HomeSummary.fromJson(homeJson()), DateTime(2026, 10, 4));
      }),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Koşu'), findsOneWidget);

    tester.container().read(dataSyncProvider).refresh([homeProvider]);
    await tester.pump();
    expect(tester.container().read(homeProvider).isLoading, isTrue);
    // No skeleton, no spinner: yesterday's numbers stay where they were.
    expect(find.byType(TodaySkeleton), findsNothing);
    expect(find.text('Koşu'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // The hint waits a full second before it shows (a real timer), so a
    // quick refresh never flashes it.
    final hint = find.byType(LinearProgressIndicator);
    await tester.pump(const Duration(milliseconds: 900));
    expect(hint, findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 150));
    expect(hint, findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.ancestor(of: hint, matching: find.byType(AnimatedOpacity)).first).opacity,
      1,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Koşu'), findsOneWidget);
    expect(builds, 2);
  });

  testWidgets('Habits: a tick shows at once and never flicks back while the '
      'server answers', (tester) async {
    _tallPhone(tester);
    final api = FakeApi();
    await tester.pumpWidget(_app(const HabitsScreen(), [
      dioProvider.overrideWithValue(api.dio),
    ]));
    await _settle(tester);

    final card = find.byKey(const ValueKey('habit-7'));
    expect(_checked(tester, card), isFalse);

    api.hold(_log7);
    await tester.tap(find.descendant(of: card, matching: find.byType(CheckPop)));
    await tester.pump();
    expect(_checked(tester, card), isTrue, reason: 'optimistic');

    api.release(_log7);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(_checked(tester, card), isTrue, reason: 'frame $i');
    }
    // The hero's count rolls its number: it reads as one label.
    expect(
      find.byWidgetPredicate((w) =>
          w is Semantics && w.properties.label == '1 / 2 tamamlandı'),
      findsOneWidget,
    );
    // The write's own answer updated the list: no GET /habits round trip.
    expect(api.gets.where((p) => p == '/habits'), hasLength(1));
    await tester.pumpAndSettle();
  });

  group('Today: a failure once shown stays up while a retry fails again', () {
    Future<FakeApi> openToday(WidgetTester tester, FakeApi api) async {
      _tallPhone(tester);
      await tester.pumpWidget(_app(
        const TodayScreen(),
        [
          dioProvider.overrideWithValue(api.dio),
          currentUserProvider.overrideWithValue(null),
        ],
        retry: readRetry, // the app's policy: one quick retry
      ));
      return api;
    }

    Finder unreachable() => find.text('Sunucuya ulaşılamıyor');

    testWidgets('the error view: a retry while the server still refuses '
        'never turns it into the skeleton and back', (tester) async {
      final api = await openToday(tester, FakeApi()..failNetwork('GET /home'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(TodaySkeleton), findsNothing,
          reason: 'the first 400 ms show the frame only');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TodaySkeleton), findsOneWidget,
          reason: 'the first load, its quick retry pending');
      await tester.pump(const Duration(seconds: 1));
      expect(unreachable(), findsOneWidget);

      await tester.tap(find.text('Tekrar dene'));
      for (var ms = 100; ms <= 1200; ms += 100) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(TodaySkeleton), findsNothing, reason: '$ms ms');
        expect(unreachable(), findsOneWidget, reason: '$ms ms');
      }
      expect(api.gets.where((p) => p == '/home'), hasLength(4));
    });

    testWidgets('the offline banner: a second failed refresh never takes it '
        'down', (tester) async {
      final api = await openToday(tester, FakeApi());
      await _settle(tester);
      expect(find.text('Koşu'), findsOneWidget);

      api.failNetwork('GET /home');
      final sync = tester.container().read(dataSyncProvider);
      sync.refresh([homeProvider]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(OfflineBanner), findsNothing,
          reason: 'the quick retry is pending');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(OfflineBanner), findsOneWidget);

      // A pull, a resume or a re-tap while the server still refuses.
      sync.refresh([homeProvider]);
      for (var ms = 100; ms <= 1200; ms += 100) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(OfflineBanner), findsOneWidget, reason: '$ms ms');
      }
      expect(find.text('Koşu'), findsOneWidget);
    });
  });

  testWidgets('Habits: a pull-to-refresh keeps its spinner until the refetch '
      'lands, also when a habit is ticked meanwhile', (tester) async {
    _tallPhone(tester);
    final api = FakeApi();
    await tester.pumpWidget(_app(const HabitsScreen(), [
      dioProvider.overrideWithValue(api.dio),
    ]));
    await _settle(tester);
    Finder spinner() => find.byType(RefreshProgressIndicator);

    api.hold('GET /habits');
    await tester.fling(
        find.byType(CustomScrollView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // the scroll settles
    await tester.pump(const Duration(seconds: 1)); // the indicator settles
    expect(spinner(), findsOneWidget);
    expect(api.gets.where((p) => p == '/habits'), hasLength(2));

    // A tick (and its answer) while the refetch is on its way.
    final card = find.byKey(const ValueKey('habit-7'));
    await tester.tap(
        find.descendant(of: card, matching: find.byType(CheckPop)));
    await _settle(tester);
    expect(_checked(tester, card), isTrue);
    expect(api.requests, contains(_log7));
    expect(spinner(), findsOneWidget, reason: 'the refetch has not landed');

    api.release('GET /habits');
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(spinner(), findsNothing);
    expect(_checked(tester, card), isTrue);
  });

  testWidgets('Today: quick taps on a counted habit all count — none is '
      'dropped while the one before it waits for the server', (tester) async {
    _tallPhone(tester);
    final api = FakeApi();
    await tester.pumpWidget(_app(const TodayScreen(), [
      dioProvider.overrideWithValue(api.dio),
      currentUserProvider.overrideWithValue(null),
    ]));
    await _settle(tester);

    final row = find.byKey(const ValueKey('habit-8'));
    final ring = find.descendant(of: row, matching: find.byType(CheckPop));
    int patches() => api.requests.where((r) => r == _log8).length;
    expect(tester.widget<CheckPop>(ring).checked, isFalse);

    api.hold(_log8);
    await tester.tap(ring);
    await tester.pump();
    expect(find.descendant(of: row, matching: find.text('2/3')), findsWidgets);
    await tester.tap(ring);
    await tester.pump();
    // 1/3 → 3/3: both taps show, and the second waits for the first.
    expect(tester.widget<CheckPop>(ring).checked, isTrue);
    await _settle(tester);
    expect(patches(), 1);
    expect(tester.widget<CheckPop>(ring).checked, isTrue);

    api.on('GET /home', _homeWithSuAt(3));
    api.release(_log8);
    await _settle(tester);
    expect(patches(), 2);
    // Each tap asked for the count it showed: 2, then 3.
    expect(api.bodiesOf(_log8), [
      {'count': 2},
      {'count': 3},
    ]);
    expect(tester.widget<CheckPop>(ring).checked, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('Today: a ticked todo is drawn from the data, not a stuck local '
      'set', (tester) async {
    _tallPhone(tester);
    final api = FakeApi();
    await tester.pumpWidget(_app(const TodayScreen(), [
      dioProvider.overrideWithValue(api.dio),
      currentUserProvider.overrideWithValue(null),
    ]));
    await _settle(tester);

    TodoRow row() => tester.widget<TodoRow>(find.byKey(const ValueKey('todo-39')));
    expect(row().done, isFalse);

    // The server answers the tick, then (reopened on the web meanwhile)
    // still lists the todo as open.
    api.on('GET /home', homeJson(todos: [todoJson(status: 'pending')]));
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('todo-39')),
      matching: find.byType(CheckPop),
    ));
    await tester.pump();
    expect(row().done, isTrue, reason: 'checked on the spot');

    await _settle(tester);
    expect(row().done, isFalse, reason: 'the refetch is the truth');
    await tester.pumpAndSettle();
  });

  group('the Agenda decides like every screen', () {
    Future<void> open(WidgetTester tester, FakeApi api) async {
      _tallPhone(tester);
      await tester.pumpWidget(_app(
        const AgendaTabScreen(),
        [
          dioProvider.overrideWithValue(api.dio),
          currentUserProvider.overrideWithValue(null),
        ],
        retry: readRetry, // the app's policy: one quick retry
      ));
    }

    Finder failed() => find.text('Sunucuya ulaşılamıyor');

    testWidgets('a first load that blips and heals on the quick retry shows '
        'the skeleton throughout, never the failure', (tester) async {
      final api = FakeApi()..blip('GET /todos');
      await open(tester, api);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(failed(), findsNothing, reason: 'retry pending, ${i * 100} ms');
      }

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.gets.where((p) => p == '/todos'), hasLength(2));
      expect(failed(), findsNothing);
      expect(find.text('Faturayı öde'), findsWidgets);
    });

    testWidgets('a load that fails for good says so', (tester) async {
      final api = FakeApi()..failNetwork('GET /todos');
      await open(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(failed(), findsNothing, reason: 'the quick retry is pending');

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));
      expect(failed(), findsOneWidget);
    });
  });

  testWidgets('a write still refreshes Today when its form is closed before '
      'the server answers', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(_app(
      Consumer(
        builder: (context, ref, _) {
          // Stands in for the shell, which keeps /home live.
          ref.watch(homeProvider);
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => openHabitForm(context),
                child: const Text('open'),
              ),
            ),
          );
        },
      ),
      [dioProvider.overrideWithValue(api.dio)],
    ));
    await _settle(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Yeni');
    api.hold('POST /habits');
    await tester.tap(find.text('Kaydet'));
    await tester.pump();

    // Closed while saving.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(HabitFormScreen), findsNothing);
    api.clearLog();

    api.release('POST /habits');
    await _settle(tester);
    expect(api.gets, contains('/home'));
    expect(tester.takeException(), isNull);
  });
}
