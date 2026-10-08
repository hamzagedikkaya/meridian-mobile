/// Today's writes against the G1 explicit-state endpoints: todos done and
/// undone, habits set to a count (with the day's log sheet to step back),
/// and the notice for a phone in another time zone than the account.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/sync.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/todo_row.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/semantics.dart';

const _toggle = 'PATCH /todos/39/toggle';
const _logSu = 'PUT /habits/8/logs/2026-10-04';
const _logRun = 'PUT /habits/7/logs/2026-10-04';

const _istanbul = User(
  id: 9,
  displayName: 'Demo',
  initials: 'D',
  email: 'demo@meridian.local',
  currency: 'TRY',
  subunitToUnit: 100,
  locale: 'tr',
  themePreference: 'dark',
  timezone: 'Istanbul',
  timezoneIana: 'Europe/Istanbul',
  utcOffset: Duration(hours: 3),
);

Future<SharedPreferences> _openToday(
  WidgetTester tester,
  FakeApi api, {
  User? user,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1170, 3900);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(api.dio),
        sharedPrefsProvider.overrideWithValue(prefs),
        currentUserProvider.overrideWithValue(user),
        ...overrides,
      ],
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
        home: const TodayScreen(),
      ),
    ),
  );
  await _settle(tester);
  return prefs;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

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

TodoRow? _todo(WidgetTester tester) {
  final row = find.byKey(const ValueKey('todo-39'));
  return row.evaluate().isEmpty ? null : tester.widget<TodoRow>(row);
}

/// The todo's checkbox: a tap on the rest of the row opens it for editing.
Finder _checkbox() => find.descendant(
  of: find.byKey(const ValueKey('todo-39')),
  matching: find.byType(CheckPop),
);

Finder _ring(int habitId) => find.descendant(
  of: find.byKey(ValueKey('habit-$habitId')),
  matching: find.byType(CheckPop),
);

void main() {
  setUpAll(initializeDateFormatting);

  group('todos', () {
    testWidgets('a tick sends done=true and offers undo; undo sends '
        'done=false and puts the todo back where it was', (tester) async {
      final api = FakeApi();
      await _openToday(tester, api);
      expect(_todo(tester)!.done, isFalse);

      // Once done, /home lists open todos only.
      api.on('GET /home', {
        ...homeJson(todos: const []),
        'open_todos': 0,
        'overdue_count': 0,
      });
      await tester.tap(_checkbox());
      await tester.pump();
      expect(_todo(tester)!.done, isTrue, reason: 'checked on the spot');
      expect(find.text('“Faturayı öde” tamamlandı'), findsOneWidget);
      await _settle(tester);
      expect(api.bodiesOf(_toggle).single, {'done': true});
      expect(_todo(tester), isNull, reason: 'the refetch dropped it');

      api.on('GET /home', homeJson());
      await tester.tap(find.text('Geri al'));
      await tester.pump();
      expect(_todo(tester)!.done, isFalse, reason: 'back at once, open');
      await _settle(tester);
      expect(api.bodiesOf(_toggle).last, {'done': false});
      expect(_todo(tester)!.done, isFalse);
      expect(find.byKey(const ValueKey('todo-39')), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('a checked row tapped again before the refetch reopens it', (
      tester,
    ) async {
      final api = FakeApi()..hold(_toggle);
      await _openToday(tester, api);
      await tester.tap(_checkbox());
      await tester.pump();
      expect(_todo(tester)!.done, isTrue);
      await tester.tap(_checkbox());
      await tester.pump();
      expect(_todo(tester)!.done, isFalse);

      api.release(_toggle);
      await _settle(tester);
      expect(api.bodiesOf(_toggle), [
        {'done': true},
        {'done': false},
      ]);
      expect(_todo(tester)!.done, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('a refusal says why, and the tick is taken back', (
      tester,
    ) async {
      final api = FakeApi()
        ..on(_toggle, {
          'errors': {
            'title': ['Title is too long (maximum is 200 characters)'],
          },
          'code': 'validation_failed',
          'details': {
            'title': [
              {'error': 'too_long', 'count': 200},
            ],
          },
        }, status: 422);
      await _openToday(tester, api);
      await tester.tap(_checkbox());
      await _settle(tester);
      expect(_todo(tester)!.done, isFalse);
      expect(
        find.text('Başlık: En fazla 200 karakter olabilir'),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
    });
  });

  group('habits', () {
    testWidgets('a single habit\'s ring sends its target, or 0 to undo', (
      tester,
    ) async {
      final api = FakeApi();
      await _openToday(tester, api);
      // The server, once the write is in.
      api.on('GET /home', homeJson(habit7Done: true));
      await tester.tap(_ring(7));
      await _settle(tester);
      expect(api.bodiesOf(_logRun).single, {'count': 1});
      expect(tester.widget<CheckPop>(_ring(7)).checked, isTrue);

      api.on('GET /home', homeJson());
      await tester.tap(_ring(7));
      await _settle(tester);
      expect(api.bodiesOf(_logRun).last, {'count': 0});
      expect(tester.widget<CheckPop>(_ring(7)).checked, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('a full counter opens the day\'s log, where it steps back and '
        'resets', (tester) async {
      final api = FakeApi()..on('GET /home', _homeWithSuAt(3));
      await _openToday(tester, api);
      await tester.tap(_ring(8));
      await tester.pumpAndSettle();
      expect(find.text('Bugünün kaydı'), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(
        api.requests.where((r) => r.startsWith('PUT')),
        isEmpty,
        reason: 'one more could do nothing: nothing is sent',
      );

      api.on('GET /home', _homeWithSuAt(2));
      await tester.tap(find.byTooltip('Bir azalt'));
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget, reason: 'at once');
      await _settle(tester);
      expect(api.bodiesOf(_logSu).single, {'count': 2});

      api.on('GET /home', _homeWithSuAt(0));
      await tester.tap(find.text('Sıfırla'));
      await _settle(tester);
      expect(api.bodiesOf(_logSu).last, {'count': 0});
      expect(find.text('0 / 3'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('a long-press opens the day\'s log of any habit', (
      tester,
    ) async {
      final api = FakeApi();
      await _openToday(tester, api);
      await tester.longPress(_ring(7));
      await tester.pumpAndSettle();
      expect(find.text('Bugünün kaydı'), findsOneWidget);
      expect(find.text('Bugün henüz yapılmadı'), findsOneWidget);
      api.on('GET /home', homeJson(habit7Done: true));
      await tester.tap(find.text('Tamamla'));
      await _settle(tester);
      expect(api.bodiesOf(_logRun).single, {'count': 1});
      expect(find.text('Bugün tamamlandı'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('a refused log is said in the sheet, and taken back', (
      tester,
    ) async {
      final api = FakeApi()
        ..on(_logRun, {
          'errors': {
            'base': ['Archived habits cannot be logged.'],
          },
          'code': 'habit_archived',
        }, status: 422);
      await _openToday(tester, api);
      await tester.longPress(_ring(7));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tamamla'));
      await _settle(tester);
      expect(find.text('Arşivlenmiş alışkanlık işaretlenemez'), findsOneWidget);
      expect(find.text('Bugün henüz yapılmadı'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('a screen reader', () {
    testWidgets('a habit ring is one stop, with its name and its day: a '
        'double-tap logs it, a long-press opens the day\'s log', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final api = FakeApi();
      await _openToday(tester, api);
      final ring = tester.getSemantics(_ring(7));
      expect(ring.label, 'Koşu, henüz yapılmadı');
      final data = ring.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      expect(ring.childrenCount, 0, reason: 'no second, unlabelled stop');

      api.on('GET /home', homeJson(habit7Done: true));
      tester.semantics.tap(find.semantics.byLabel('Koşu, henüz yapılmadı'));
      await _settle(tester);
      expect(api.bodiesOf(_logRun).single, {'count': 1});
      expect(find.semantics.byLabel('Koşu, bugün tamamlandı'), findsOne);

      tester.semantics.longPress(
        find.semantics.byLabel('Koşu, bugün tamamlandı'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bugünün kaydı'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a todo row is one stop: a double-tap edits it, and '
        'checking it off is its action', (tester) async {
      final handle = tester.ensureSemantics();
      final api = FakeApi();
      await _openToday(tester, api);
      final row = tester.getSemantics(find.byKey(const ValueKey('todo-39')));
      expect(row.label, startsWith('Faturayı öde'));
      expect(row.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(row.childrenCount, 0,
          reason: 'the checkbox is not a stop of its own');

      performCustomAction(row, 'Tamamla');
      await _settle(tester);
      expect(api.bodiesOf(_toggle).single, {'done': true});

      tester.semantics.tap(find.semantics.byLabel(RegExp('^Faturayı öde')));
      await tester.pumpAndSettle();
      expect(find.text('Görevi düzenle'), findsOneWidget,
          reason: 'a tap opens the todo for editing');
      handle.dispose();
    });
  });

  group('the undo snackbar after a todo is checked off', () {
    const message = '“Faturayı öde” tamamlandı';

    testWidgets('goes after 6 s, like any other', (tester) async {
      await _openToday(tester, FakeApi());
      await tester.tap(_checkbox());
      await _settle(tester);
      expect(find.text(message), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(message), findsOneWidget, reason: 'still within 6 s');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('stays until dismissed while a screen reader is on', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _openToday(tester, FakeApi());
      await tester.tap(_checkbox());
      await _settle(tester);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.text('Geri al'), findsOneWidget);
    });
  });

  testWidgets('a habit archived elsewhere: the refusal says so, and Today '
      'refetches and drops it instead of refusing every tap', (tester) async {
    final api = FakeApi()
      ..on(_logRun, {
        'errors': {
          'base': ['Archived habits cannot be logged.'],
        },
        'code': 'habit_archived',
      }, status: 422);
    await _openToday(tester, api);
    api.clearLog();
    // The server no longer lists it as active.
    final home = homeJson();
    home['today_habits'] = [
      for (final habit in home['today_habits'] as List<Map<String, dynamic>>)
        if (habit['id'] != 7) habit,
    ];
    api.on('GET /home', home);

    await tester.tap(_ring(7));
    await _settle(tester);
    expect(find.text('Arşivlenmiş alışkanlık işaretlenemez'), findsOneWidget);
    expect(api.gets, contains('/home'));
    expect(find.byKey(const ValueKey('habit-7')), findsNothing);
    await tester.pumpAndSettle();
  });

  group('how often a habit repeats, which /home does not say', () {
    Finder inRow(int id, String text) => find.descendant(
      of: find.byKey(ValueKey('habit-$id')),
      matching: find.text(text),
    );

    testWidgets('read once, from the Habits list; until then a habit done '
        'more than once a day is a ring, done or not — never a count that '
        'may be wrong', (tester) async {
      final api = FakeApi()..hold('GET /habits');
      await _openToday(tester, api);
      expect(api.gets.where((p) => p == '/habits'), hasLength(1));
      // Su (8): three times a day, but Today cannot know that yet.
      expect(inRow(8, '1/3'), findsNothing);

      api.release('GET /habits');
      await _settle(tester);
      expect(inRow(8, '1/3'), findsWidgets, reason: 'a daily count');

      // Known now: a refetch of /home does not ask again.
      api.clearLog();
      tester.container().read(dataSyncProvider).refresh([homeProvider]);
      await _settle(tester);
      expect(api.gets, ['/home']);
    });

    testWidgets('a weekly habit is a ring, done or not, and a tap marks the '
        'day done', (tester) async {
      final handle = tester.ensureSemantics();
      final api = FakeApi()
        ..on('GET /habits', {
          'habits': [
            habitJson(),
            {
              ...habitJson(id: 8, name: 'Su', targetCount: 3, count: 1),
              'frequency': 'weekly',
            },
          ],
          'meta': habitsMeta(),
        });
      await _openToday(tester, api);
      expect(inRow(8, '1/3'), findsNothing);
      expect(find.bySemanticsLabel('Su, henüz yapılmadı'), findsOneWidget);

      await tester.tap(_ring(8));
      await _settle(tester);
      expect(api.bodiesOf(_logSu).single, {'count': 3});
      await tester.pumpAndSettle();
      handle.dispose();
    });
  });

  group('a phone in another time zone than the account', () {
    testWidgets('Today says which zone days and times follow, until '
        'dismissed for this pair of zones', (tester) async {
      final prefs = await _openToday(
        tester,
        FakeApi(),
        user: _istanbul,
        overrides: [
          deviceUtcOffsetProvider.overrideWithValue(const Duration(hours: -4)),
        ],
      );
      const notice =
          'Günler ve saatler hesabının saat dilimine göre: '
          'Europe/Istanbul (UTC+03:00)';
      expect(find.text(notice), findsOneWidget);

      await tester.tap(find.byTooltip('Kapat'));
      await tester.pump();
      expect(find.text(notice), findsNothing);
      expect(prefs.getString(PrefKeys.zoneNoticeDismissed), '180|-240');
    });

    testWidgets('nothing to say when the zones agree', (tester) async {
      await _openToday(
        tester,
        FakeApi(),
        user: _istanbul,
        overrides: [
          deviceUtcOffsetProvider.overrideWithValue(const Duration(hours: 3)),
        ],
      );
      expect(find.textContaining('saat dilimine göre'), findsNothing);
    });
  });
}
