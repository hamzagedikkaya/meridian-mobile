/// Today, as reviewed (WP-17 review, group g2): a counter tapped before its
/// cadence is known, `/home`'s six todos, the inline add above the capture
/// bar, the first-run card's steps, deletes waiting on their undo, the money
/// chip with accounts in other currencies, one haptic per long press, and
/// the goals slot once every goal is achieved.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/haptics.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/data_scope.dart';
import 'package:meridian_mobile/data/deferred_deletes.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/start_card.dart';
import 'package:meridian_mobile/ui/widgets/capture_bar.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/money_glance.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'today_harness.dart';

const _logSu = 'PUT /habits/8/logs/2026-10-04';

/// Today over [api] (the real repository and read models), on a phone
/// [size] dp, with [overrides].
Future<ProviderContainer> _openToday(
  WidgetTester tester,
  FakeApi api, {
  Size size = const Size(390, 1300),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(api.dio),
        sharedPrefsProvider.overrideWithValue(prefs),
        currentUserProvider.overrideWithValue(null),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 4, 12, 30)),
        ...overrides,
      ],
      retry: (_, _) => null,
      child: _app(const TodayScreen()),
    ),
  );
  await _settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(TodayScreen)));
}

Widget _app(Widget home) => MaterialApp(
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
);

/// Today over a fixed /home and read models, no network (the harness of
/// Today's screen tests).
Future<ProviderContainer> _pumpToday(
  WidgetTester tester,
  Map<String, dynamic> home, {
  List<Map<String, dynamic>>? accounts = const [],
  List<Map<String, dynamic>>? journal = const [],
  List<Map<String, dynamic>>? events = const [],
  List<Override> overrides = const [],
  DateTime Function()? clock,
  bool ownDashboard = false,
}) async {
  tester.view.physicalSize = const Size(1170, 3900);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final at = DateTime(2026, 10, 4);
  final summary = HomeSummary.fromJson(home);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeProvider.overrideWithBuild((ref, _) => Fetched(summary, at)),
        currentUserProvider.overrideWithValue(null),
        sharedPrefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(
          clock ?? () => DateTime(2026, 10, 4, 9, 41),
        ),
        ...todayReadOverrides(
          at: at,
          accounts: accounts,
          journal: journal,
          events: events,
          // A dashboard of the test's own, in [overrides].
          subscriptions: ownDashboard ? null : const [],
        ),
        ...overrides,
      ],
      child: _app(const TodayScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(TodayScreen)));
}

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
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

Finder _ring(int habitId) => find.descendant(
  of: find.byKey(ValueKey('habit-$habitId')),
  matching: find.byType(CheckPop),
);

/// An open todo [id] due on [date] at [time] (null: the day alone).
Map<String, dynamic> _todo(
  int id,
  String date, {
  String? time,
  bool overdue = false,
  String title = 'Görev',
}) => {
  ...todoJson(id: id),
  'title': '$title $id',
  'due_date': date,
  'due_time': time,
  'due_at':
      '${date}T${time ?? '23:59:59'}${time == null ? '' : ':00'}'
      '.000+03:00',
  'overdue': overdue,
};

void main() {
  setUpAll(initializeDateFormatting);

  group('a habit counted several times a day, before its cadence is known', () {
    testWidgets('a tap steps it up one — never to its target', (tester) async {
      final api = FakeApi()..hold('GET /habits');
      await _openToday(tester, api);
      await tester.tap(_ring(8));
      await _settle(tester);
      expect(api.bodiesOf(_logSu).single, {'count': 2});
      api.release('GET /habits');
      await tester.pumpAndSettle();
    });

    testWidgets('done already, a tap opens its log — never a reset to 0', (
      tester,
    ) async {
      final api = FakeApi()
        ..hold('GET /habits')
        ..on('GET /home', _homeWithSuAt(3));
      await _openToday(tester, api);
      await tester.tap(find.text('1 tamamlandı'));
      await tester.pumpAndSettle();
      await tester.tap(_ring(8));
      await tester.pumpAndSettle();
      expect(find.text('Bugünün kaydı'), findsOneWidget);
      expect(api.requests.where((r) => r.startsWith('PUT')), isEmpty);
      api.release('GET /habits');
      await tester.pumpAndSettle();
    });
  });

  testWidgets('a long press on a habit row plays one haptic, not two', (
    tester,
  ) async {
    final played = <String?>[];
    Haptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            played.add(call.arguments as String?);
          }
          return null;
        });
    addTearDown(() {
      Haptics.debugReset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await _openToday(tester, FakeApi());
    played.clear();
    await tester.longPress(
      find.descendant(
        of: find.byKey(const ValueKey('habit-7')),
        matching: find.text('Koşu'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bugünün kaydı'), findsOneWidget);
    expect(played, hasLength(1));

    // On the ring, too: one.
    Navigator.of(tester.element(find.text('Bugünün kaydı'))).pop();
    await tester.pumpAndSettle();
    played.clear();
    await tester.longPress(_ring(7));
    await tester.pumpAndSettle();
    expect(played, hasLength(1));
  });

  testWidgets('un-ticking a todo that only lingers keeps its row while '
      'the server answers', (tester) async {
    final api = FakeApi();
    await _openToday(tester, api);
    final row = find.byKey(const ValueKey('todo-39'));
    final box = find.descendant(of: row, matching: find.byType(CheckPop));
    // Ticked; the refetch drops it from /home: it lingers, done.
    api.on('GET /home', homeJson(todos: const []));
    await tester.tap(box);
    await _settle(tester);
    expect(row, findsOneWidget);

    api
      ..hold('PATCH /todos/39/toggle')
      ..on('GET /home', homeJson());
    await tester.tap(box);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(row, findsOneWidget, reason: 'back in its place at once');
    expect(tester.widget<CheckPop>(box).checked, isFalse);
    api.release('PATCH /todos/39/toggle');
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
  });

  group('/home lists only its six soonest todos', () {
    Map<String, dynamic> backlog() => {
      ...homeJson(),
      'open_todos': 12,
      'overdue_count': 9,
      'upcoming_todos': [
        for (var i = 1; i <= 6; i++)
          _todo(100 + i, '2026-09-2$i', overdue: true),
      ],
    };

    testWidgets('with six overdue listed, today\'s are read too, and the '
        'rest are counted: "+N daha" and the header say so', (tester) async {
      final api = FakeApi()
        ..on('GET /home', backlog())
        ..onRequest('GET /todos', (request) {
          expect(request.uri.queryParameters['filter'], 'today');
          return {
            'todos': [_todo(300, '2026-10-04', title: 'Dişçiyi ara')],
            'meta': const {'open_count': 12, 'overdue_count': 9},
          };
        });
      await _openToday(tester, api);
      expect(api.gets, contains('/todos'));
      // Six rows shown; one of today's past them, and three overdue that
      // no list here has (9 overdue, 6 listed).
      expect(find.text('+4 daha'), findsOneWidget);
      // 7 known open todos + the 3 unlisted overdue ones.
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('a swipe to tomorrow, while the move is on its way, keeps '
        'the rest counted', (tester) async {
      final api = FakeApi()
        ..on('GET /home', backlog())
        ..onRequest(
          'GET /todos',
          (_) => {
            'todos': [
              _todo(300, '2026-10-04', title: 'Dişçiyi ara'),
              _todo(301, '2026-10-04', title: 'Süt al'),
            ],
            'meta': const {'open_count': 12, 'overdue_count': 9},
          },
        )
        ..hold('PATCH /todos/101');
      await _openToday(tester, api);
      // 8 known (6 overdue, 2 of today's) + 3 overdue unlisted; 6 shown.
      expect(find.text('11'), findsOneWidget);
      expect(find.text('+5 daha'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('todo-101')),
        const Offset(-600, 0),
      );
      await _settle(tester, frames: 20);
      expect(api.requests, contains('PATCH /todos/101'));
      // One overdue fewer, the others all still counted.
      expect(find.text('10'), findsOneWidget);
      expect(find.text('+4 daha'), findsOneWidget);
      api.release('PATCH /todos/101');
      await tester.pumpAndSettle();
    });

    testWidgets('with fewer, nothing more is read', (tester) async {
      final api = FakeApi();
      await _openToday(tester, api);
      expect(api.gets, isNot(contains('/todos')));
      expect(find.textContaining('daha'), findsNothing);
    });

    testWidgets('a todo added from the card stays counted past /home\'s '
        'refetch', (tester) async {
      var added = false;
      final api = FakeApi()
        ..on('GET /home', backlog())
        ..on('POST /todos', {
          'todo': _todo(300, '2026-10-04', title: 'Dişçiyi ara'),
        }, status: 201)
        ..onRequest(
          'GET /todos',
          (_) => {
            'todos': [
              if (added) _todo(300, '2026-10-04', title: 'Dişçiyi ara'),
            ],
            'meta': const {'open_count': 12, 'overdue_count': 9},
          },
        );
      await _openToday(tester, api);
      expect(find.text('+3 daha'), findsOneWidget);
      await tester.tap(find.text('Bugün için görev ekle'));
      await tester.pumpAndSettle();
      added = true;
      await tester.enterText(find.byType(TextField), 'Dişçiyi ara');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester, frames: 20);
      expect(api.requests, contains('POST /todos'));
      // /home's refetch still lists the same six: today's list has it.
      expect(find.text('+4 daha'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('what quick add saves is said above the capture bar', () {
    /// [snack]'s text ends above the capture bar.
    void expectAboveBar(WidgetTester tester, Finder snack) {
      expect(snack, findsOneWidget);
      expect(
        tester.getRect(snack).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(CaptureBar)).top),
      );
    }

    Future<void> typeInQuickAdd(WidgetTester tester, String line) async {
      await tester.tap(find.text('Ekle: görev, harcama, etkinlik…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, line);
      await tester.pump();
    }

    testWidgets('a task', (tester) async {
      final api = FakeApi();
      await _openToday(tester, api, size: const Size(390, 844));
      await typeInQuickAdd(tester, 'süt al');
      await tester.tap(find.byType(FilledButton).last);
      await _settle(tester, frames: 20);
      expect(api.requests, contains('POST /todos'));
      expectAboveBar(tester, find.text('Geri al'));
      await tester.pumpAndSettle();
    });

    testWidgets('an event, through its form', (tester) async {
      final api = FakeApi();
      await _openToday(tester, api, size: const Size(390, 844));
      await typeInQuickAdd(tester, 'Toplantı');
      await tester.tap(find.text('Etkinlik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Etkinlik olarak aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet'));
      await _settle(tester, frames: 20);
      expect(api.requests, contains('POST /events'));
      expectAboveBar(tester, find.textContaining('eklendi'));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('the inline add field stays above the capture bar after each '
      'Enter, with the keyboard up', (tester) async {
    var created = 0;
    final made = <Map<String, dynamic>>[];
    final api = FakeApi()
      ..onRequest('POST /todos', (_) {
        final todo = _todo(400 + created++, '2026-10-04', title: 'Yeni');
        made.add(todo);
        return {'todo': todo};
      })
      ..onRequest('GET /home', (_) => homeJson(todos: [todoJson(), ...made]));
    await _openToday(tester, api, size: const Size(360, 780));
    await tester.tap(find.text('Bugün için görev ekle'));
    await tester.pumpAndSettle();
    // The keyboard opens after the tap, as a real one does.
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pumpAndSettle();

    Rect field() => tester.getRect(find.byType(TextField));
    Rect bar() => tester.getRect(find.byType(CaptureBar));
    for (var i = 0; i < 3; i++) {
      await tester.enterText(find.byType(TextField), 'Görev $i');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester, frames: 20);
      await tester.pumpAndSettle();
      expect(
        field().bottom,
        lessThanOrEqualTo(bar().top),
        reason: 'after add ${i + 1}: field ${field()}, bar ${bar()}',
      );
    }
    expect(made, hasLength(3));
  });

  group('the first-run card', () {
    testWidgets('a step once done stays done: finishing the first task '
        'does not take it back', (tester) async {
      final container = await _pumpToday(tester, {
        ...homeJson(),
        'today_habits': const [],
        'open_todos': 1,
        'upcoming_todos': [todoJson()],
      });
      expect(find.text('Başlayalım · 1/4'), findsOneWidget);
      // The todo is done: /home lists no open one any more.
      container
          .read(homeProvider.notifier)
          .patch((h) => h.copyWith(upcomingTodos: const [], openTodos: 0))
          .confirm();
      await tester.pumpAndSettle();
      expect(find.text('Başlayalım · 1/4'), findsOneWidget);
      expect(find.text('Başlayalım · 0/4'), findsNothing);
    });

    test('its flags are read afresh for each session: another account '
        'decides for itself', () async {
      SharedPreferences.setMockInitialValues({
        TodayStartFlags.dismissedKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          sessionProvider.overrideWith(_Switchable.new),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(todayStartFlagsProvider, (_, _) {});
      addTearDown(sub.close);
      expect(container.read(todayStartFlagsProvider).dismissed, isTrue);

      // Signed out (the device store is wiped), then in as someone else.
      await prefs.clear();
      final session = container.read(sessionProvider.notifier) as _Switchable;
      session.set(const SessionLoggedOut());
      session.set(const SessionLoggedIn());
      expect(container.read(todayStartFlagsProvider).dismissed, isFalse);
    });
  });

  group('a delete waiting out its undo is gone from Today at once', () {
    testWidgets('the next-up chip lets the event go', (tester) async {
      final container = await _pumpToday(
        tester,
        {...homeJson(), 'today': '2026-10-04'},
        accounts: [todayAccountJson()],
        events: [eventJson()],
        clock: () => DateTime(2026, 10, 4, 17, 30),
      );
      expect(find.text('18:00 · Yoga · 30 dk'), findsOneWidget);
      container.read(deferredDeletesProvider.notifier).stage((
        scope: DataScope.events,
        id: 12,
      ), send: () async {});
      await tester.pump();
      expect(find.textContaining('Yoga'), findsNothing);
    });

    testWidgets('the journal card asks about today again', (tester) async {
      final container = await _pumpToday(
        tester,
        {...homeJson(), 'today': '2026-10-04'},
        accounts: [todayAccountJson()],
        journal: [todayJournalEntryJson('2026-10-04')],
      );
      expect(find.text('Bugün yazdın'), findsOneWidget);
      container.read(deferredDeletesProvider.notifier).stage((
        scope: DataScope.journal,
        id: 20,
      ), send: () async {});
      await tester.pump();
      expect(find.text('Bugün yazdın'), findsNothing);
    });
  });

  testWidgets('with an account in another currency the money chip shows '
      'Finance\'s month, not /home\'s unconverted sum', (tester) async {
    await _pumpToday(
      tester,
      {...homeJson(), 'month_net_cents': 100000},
      accounts: [
        todayAccountJson(),
        {...todayAccountJson(), 'id': 2, 'name': 'Dolar', 'currency': 'USD'},
      ],
      ownDashboard: true,
      overrides: [
        financeDashboardProvider.overrideWith(
          (ref) async => Fetched(
            FinanceDashboard.fromJson({
              'currency': 'TRY',
              'subunit_to_unit': 100,
              'month': {
                'income_cents': 50000,
                'expense_cents': 20000,
                'net_cents': 30000,
              },
              'totals_by_currency': const [],
            }),
            DateTime(2026, 10, 4),
          ),
        ),
      ],
    );
    expect(
      tester.widget<MoneyGlance>(find.byType(MoneyGlance)).netCents,
      30000,
    );
  });

  testWidgets('one currency: the chip keeps /home\'s month', (tester) async {
    await _pumpToday(
      tester,
      {...homeJson(), 'month_net_cents': 100000},
      accounts: [todayAccountJson()],
    );
    expect(
      tester.widget<MoneyGlance>(find.byType(MoneyGlance)).netCents,
      100000,
    );
  });

  testWidgets('no active goal on an account past its first run: the goals '
      'slot does not say there are none yet', (tester) async {
    await _pumpToday(
      tester,
      {...homeJson(), 'active_goals': const []},
      accounts: [todayAccountJson()],
    );
    expect(find.text('Aktif hedef yok — yeni bir hedef koy'), findsOneWidget);
    expect(find.text('Henüz hedef yok — ilk hedefini koy'), findsNothing);
  });

  testWidgets('a new account: the goals slot says nothing until it is '
      'known whether it is new, then that there are none yet', (tester) async {
    final api = FakeApi()
      ..on('GET /home', {
        ...homeJson(),
        'today_habits': const [],
        'upcoming_todos': const [],
        'today_events': const [],
        'active_goals': const [],
        'open_todos': 0,
        'overdue_count': 0,
        'today_events_count': 0,
      })
      ..on('GET /accounts', {'accounts': const []})
      ..on('GET /journal_entries', {
        'entries': const [],
        'meta': const {
          'entries_count': 0,
          'journal_streak': 0,
          'journal_streak_weeks': 0,
          'range': '30d',
        },
      })
      ..hold('GET /accounts')
      ..hold('GET /journal_entries');
    await _openToday(tester, api);
    // Neither in sight (the card keeps its place, unseen).
    expect(
      find.text('Aktif hedef yok — yeni bir hedef koy').hitTestable(),
      findsNothing,
    );
    expect(
      find.text('Henüz hedef yok — ilk hedefini koy').hitTestable(),
      findsNothing,
    );
    api
      ..release('GET /accounts')
      ..release('GET /journal_entries');
    await _settle(tester);
    expect(
      find.text('Henüz hedef yok — ilk hedefini koy').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Aktif hedef yok — yeni bir hedef koy'), findsNothing);
    await tester.pumpAndSettle();
  });
}

/// A session a test moves between signed in and out.
class _Switchable extends SessionController {
  @override
  SessionState build() => const SessionLoggedIn();

  void set(SessionState next) => state = next;
}
