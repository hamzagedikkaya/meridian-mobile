import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:meridian_mobile/core/haptics.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/lingering_todos.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/models/journal.dart';
import 'package:meridian_mobile/models/todo.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/today_agenda.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/today_goals.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/today_header.dart';
import 'package:meridian_mobile/ui/widgets/capture_bar.dart';
import 'package:meridian_mobile/ui/widgets/celebration_layer.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_fonts.dart';
import '../support/fake_api.dart';
import 'today_harness.dart';

/// Populated /home payload (shape lifted from api-samples.json).
Map<String, dynamic> populatedHome() => {
  'currency': 'TRY',
  'subunit_to_unit': 100,
  'month_net_cents': -6859733,
  'active_streaks': 3,
  'open_todos': 5,
  'overdue_count': 5,
  'today_events_count': 1,
  'habit_completion_pct': 40,
  'spending_7d': [
    for (var i = 5; i <= 11; i++)
      {'date': '2026-07-${i.toString().padLeft(2, '0')}', 'cents': i * 1000},
  ],
  'today_habits': [
    {
      'id': 50,
      'name': '5ee',
      'color': '#b8860b',
      'target_count': 5,
      'completed_today': false,
      'today_count': 2,
      'current_streak': 4,
    },
    {
      'id': 49,
      'name': 'Gym session',
      'color': '#B85450',
      'target_count': 1,
      'completed_today': true,
      'today_count': 1,
      'current_streak': 7,
    },
    {
      'id': 45,
      'name': 'Read 30 pages',
      'color': '#6B8FA0',
      'target_count': 1,
      'completed_today': false,
      'today_count': 0,
      'current_streak': 0,
    },
  ],
  'upcoming_todos': [
    {
      'id': 39,
      'title': 'Deploy v1.2',
      'body': null,
      'status': 'pending',
      'priority': 'urgent',
      'due_at': '2026-05-25T17:10:58.466Z',
      'overdue': true,
      'position': 7,
      'todo_list': {'id': 10, 'name': 'Work', 'color': '#6B8FA0'},
      'subtask_count': 0,
    },
    {
      'id': 36,
      'title': 'Buy milk, bread, eggs',
      'body': null,
      'status': 'pending',
      'priority': 'low',
      'due_at': '2026-05-26T19:10:58.466Z',
      'overdue': true,
      'position': 4,
      'todo_list': null,
      'subtask_count': 0,
    },
  ],
  'today_events': [
    {
      'id': 5,
      'title': 'Takım toplantısı',
      'start_at': '2026-07-11T09:30:00.000Z',
      'end_at': '2026-07-11T10:00:00.000Z',
      'all_day': false,
      'color': '#6B8FA0',
    },
    {
      'id': 6,
      'title': 'Doğum günü',
      'start_at': null,
      'end_at': null,
      'all_day': true,
      'color': '#B8860B',
    },
  ],
  'active_goals': [
    {
      'id': 18,
      'name': 'Read for 100 days',
      'color': '#6B8E5A',
      'progress_percent': 42.0,
    },
    {
      'id': 20,
      'name': 'Learn German — A2',
      'color': '#6B8FA0',
      'progress_percent': 0.0,
    },
  ],
  'perfect_day': {
    'chain': [
      {'date': '2026-07-11', 'status': 'missed'},
    ],
    'current_streak': 0,
  },
};

/// Empty/edge payload: every list empty, all-zero spending, zero net.
Map<String, dynamic> emptyHome() => {
  'currency': 'TRY',
  'subunit_to_unit': 100,
  'month_net_cents': 0,
  'active_streaks': 0,
  'open_todos': 0,
  'overdue_count': 0,
  'today_events_count': 0,
  'habit_completion_pct': 0,
  'spending_7d': [
    for (var i = 5; i <= 11; i++)
      {'date': '2026-07-${i.toString().padLeft(2, '0')}', 'cents': 0},
  ],
  'today_habits': const [],
  'upcoming_todos': const [],
  'today_events': const [],
  'active_goals': const [],
  'perfect_day': {'chain': const [], 'current_streak': 0},
};

const _fixtureUser = User(
  id: 9,
  displayName: 'Demo User',
  initials: 'DU',
  email: 'demo@meridian.local',
  currency: 'TRY',
  subunitToUnit: 100,
  locale: 'tr',
  themePreference: 'dark',
);

/// Pumps Today over [home]. [accounts] / [journal] null leave those reads
/// to [overrides] (a test that holds them); [clock] moves time; [wrap] puts
/// something around the screen; [settle] false stops after the first frame.
Future<void> pumpToday(
  WidgetTester tester,
  Map<String, dynamic> home, {
  List<Map<String, dynamic>>? accounts = const [],
  List<Map<String, dynamic>>? journal = const [],
  List<Override> overrides = const [],
  bool celebrations = false,
  DateTime Function()? clock,
  Locale locale = const Locale('tr'),
  Widget Function(Widget screen)? wrap,
  bool settle = true,
}) async {
  final summary = HomeSummary.fromJson(home);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final at = DateTime(2026, 7, 11);
  const screen = TodayScreen();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeProvider.overrideWithBuild((ref, _) => Fetched(summary, at)),
        currentUserProvider.overrideWithValue(_fixtureUser),
        sharedPrefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(
          clock ?? () => DateTime(2026, 7, 11, 9, 41),
        ),
        ...todayReadOverrides(at: at, accounts: accounts, journal: journal),
        ...overrides,
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        locale: locale,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('tr'), Locale('en')],
        builder: celebrations
            ? (context, child) => CelebrationLayer(child: child!)
            : null,
        home: wrap == null ? screen : wrap(screen),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// A phone 360 × 780 dp with a 24 dp status bar (design-analysis §7.2).
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = const FakeViewPadding(top: 72);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
}

/// /home for the fold: five habits, three events, three todos.
Map<String, dynamic> _foldHome() => {
  ...populatedHome(),
  'today': '2026-07-11',
  'today_habits': [
    for (var i = 1; i <= 5; i++)
      {
        'id': i,
        'name': 'Alışkanlık $i',
        'color': '#6B8FA0',
        'target_count': 1,
        'completed_today': false,
        'today_count': 0,
        'current_streak': i,
      },
  ],
};

Iterable<String> _texts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
  for (final t in tester.widgetList<RichText>(find.byType(RichText)))
    t.text.toPlainText(),
];

void main() {
  /// `HapticFeedback.vibrate` calls, by argument.
  final played = <String?>[];
  setUp(() {
    played.clear();
    Haptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            played.add(call.arguments as String?);
          }
          return null;
        });
  });
  tearDown(() {
    Haptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  setUpAll(() async {
    // Widgets format overdue todo dates with DateFormat('…','tr_TR').
    await initializeDateFormatting();
    // Measured as on a phone: the fold is a matter of real line heights.
    await loadAppFonts();
  });

  testWidgets('Bugün renders populated /home without exceptions', (
    tester,
  ) async {
    // Tall canvas (390×1300 logical) so every section is laid out by the
    // SliverList and reachable by find.text, while width 390 still surfaces
    // any horizontal overflow via takeException.
    tester.view.physicalSize = const Size(1170, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpToday(tester, populatedHome(), accounts: [todayAccountJson()]);

    expect(tester.takeException(), isNull);

    // The greeting with the first name, and the section headers.
    expect(find.text('İyi sabahlar, Demo'), findsOneWidget);
    expect(find.text('Alışkanlıklar'), findsOneWidget);
    expect(find.text('Hedefler'), findsOneWidget);

    // Entities from each section.
    expect(find.text('5ee'), findsOneWidget);
    expect(find.text('Read for 100 days'), findsOneWidget);
    expect(find.text('Deploy v1.2'), findsOneWidget);
    expect(find.text('Takım toplantısı'), findsWidgets);
    expect(find.text('Tüm gün'), findsOneWidget);
    // The streak is a flame, never an emoji.
    expect(find.byIcon(Icons.local_fire_department_rounded), findsWidgets);
    expect(_texts(tester).where((t) => t.contains('🔥')), isEmpty);
  });

  testWidgets('a new account: the first-run card, the add row and the goals '
      'ghost — and never a "0"', (tester) async {
    tester.view.physicalSize = const Size(1170, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpToday(tester, emptyHome());

    expect(tester.takeException(), isNull);
    expect(find.text('Başlayalım · 0/4'), findsOneWidget);
    expect(find.text('Nakit hesabı aç'), findsOneWidget);
    expect(find.text('Bugün plan yok — sakin bir gün'), findsOneWidget);
    expect(find.text('Bugün için görev ekle'), findsOneWidget);
    expect(find.text('Henüz hedef yok — ilk hedefini koy'), findsOneWidget);
    // The money chip's "start" is the card's first step: shown once.
    expect(find.text('Nakit hesabıyla başla'), findsNothing);
    // Sections with nothing in them stay away.
    expect(find.text('Alışkanlıklar'), findsNothing);

    final zeros = RegExp(r'(^|[^\d/])0([^\d/,.]|$)|₺0|0,00|%0');
    expect(
      _texts(tester).where((t) => t != 'Başlayalım · 0/4' && zeros.hasMatch(t)),
      isEmpty,
    );
  });

  testWidgets('an account at exactly zero this month: "₺0", no sign (D33)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpToday(tester, emptyHome(), accounts: [todayAccountJson()]);

    expect(tester.takeException(), isNull);
    expect(find.text('₺0'), findsOneWidget);
    expect(find.text('Henüz alışkanlık yok — küçük başla'), findsOneWidget);
  });

  testWidgets('the fold: with five habits, three events and three todos the '
      'first ring sits within 260 dp of the top', (tester) async {
    _phone(tester);
    await pumpToday(tester, _foldHome(), accounts: [todayAccountJson()]);
    final ring = find.descendant(
      of: find.byKey(const ValueKey('habit-1')),
      matching: find.byType(CheckPop),
    );
    expect(tester.getCenter(ring).dy, lessThanOrEqualTo(260));
    // The fifth ring is on the first screen too, above the capture bar.
    final fifth = find.descendant(
      of: find.byKey(const ValueKey('habit-5')),
      matching: find.byType(CheckPop),
    );
    expect(
      tester.getCenter(fifth).dy,
      lessThan(tester.getTopLeft(find.byType(CaptureBar)).dy),
    );
  });

  for (final locale in const [Locale('tr'), Locale('en')]) {
    testWidgets('at 200% text (${locale.languageCode}) nothing overflows and '
        'every target is 48 dp — a large net beside the next event too', (
      tester,
    ) async {
      _phone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final handle = tester.ensureSemantics();
      await pumpToday(
        tester,
        {..._foldHome(), 'month_net_cents': 4275000},
        accounts: [todayAccountJson()],
        clock: () => DateTime(2026, 7, 11, 9, 5),
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      // The guidelines skip whatever touches the edge of the view, so they
      // run again at each step down to the end of the screen: every target
      // below the fold is measured too.
      final position = tester
          .state<ScrollableState>(find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          ).first)
          .position;
      for (var step = 0; step < 30; step++) {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        if (position.pixels >= position.maxScrollExtent) break;
        await tester.drag(
            find.byType(CustomScrollView), const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(position.pixels, position.maxScrollExtent,
          reason: 'measured down to the end');
      handle.dispose();
    });

    testWidgets('at 1.0 on a 360 dp phone (${locale.languageCode}) the '
        'next-up chip keeps its time and minutes beside a six-digit net; '
        'the money chip keeps its 48 dp target', (tester) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      await pumpToday(
        tester,
        {..._foldHome(), 'month_net_cents': 123456700},
        accounts: [todayAccountJson()],
        clock: () => DateTime(2026, 7, 11, 9, 5),
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      final chip = find.byType(TodayNextUp);
      final minutes = locale.languageCode == 'tr' ? ' · 25 dk' : ' · 25 min';
      expect(
        find.descendant(of: chip, matching: find.text('09:30 · ')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chip, matching: find.text(minutes)),
        findsOneWidget,
      );
      // The amount is whole (",00" dropped, §3.7), never cut.
      expect(
        _texts(
          tester,
        ).where((t) => t.contains('1.234.567') || t.contains('1,234,567')),
        isNotEmpty,
      );
      expect(_texts(tester).where((t) => t.contains('567,00')), isEmpty);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }

  testWidgets('the avatar and the mood buttons are buttons a screen reader '
      'can press', (tester) async {
    tester.view.physicalSize = const Size(1170, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handle = tester.ensureSemantics();
    await pumpToday(tester, populatedHome(), accounts: [todayAccountJson()]);
    for (final label in const [
      'Profil ve ayarlar',
      'Harika',
      'İyi',
      'Normal',
      'Kötü',
      'Berbat',
    ]) {
      final nodes = find.semantics.byLabel(label).evaluate();
      expect(nodes, isNotEmpty, reason: label);
      for (final node in nodes) {
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue, reason: label);
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
      }
    }
    handle.dispose();
  });

  group('the greeting shares its row with search and the avatar', () {
    final style = buildTheme(Brightness.dark).textTheme.headlineLarge!;
    const greeting = 'İyi akşamlar, Demo';

    Future<double> fullWidth(WidgetTester tester) async {
      final painter = TextPainter(
        text: TextSpan(text: greeting, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    Future<void> pumpGreeting(
      WidgetTester tester, {
      required double width,
      double scale = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: SizedBox(
                width: width,
                child: TodayGreeting(
                  text: greeting,
                  style: style,
                  large: scale > 1.3,
                ),
              ),
            ),
          ),
        ),
      );
    }

    double sizeOf(WidgetTester tester) =>
        tester.widget<Text>(find.text(greeting)).style!.fontSize!;
    int linesOf(WidgetTester tester) => tester
        .renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(greeting),
            matching: find.byType(RichText),
          ),
        )
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: greeting.length),
        )
        .map((box) => box.top.round())
        .toSet()
        .length;

    testWidgets('a little too wide: one line, set a little smaller', (
      tester,
    ) async {
      final full = await fullWidth(tester);
      await pumpGreeting(tester, width: full * 0.92);
      expect(linesOf(tester), 1);
      expect(sizeOf(tester), lessThan(style.fontSize!));
      expect(
        sizeOf(tester),
        greaterThanOrEqualTo(style.fontSize! * TodayGreeting.minFit),
      );
    });

    testWidgets('far too wide: full size, on two lines', (tester) async {
      final full = await fullWidth(tester);
      await pumpGreeting(tester, width: full * 0.7);
      expect(sizeOf(tester), style.fontSize);
      expect(linesOf(tester), 2);
    });

    testWidgets('at large text: never set smaller', (tester) async {
      final full = await fullWidth(tester);
      await pumpGreeting(tester, width: full * 1.2, scale: 1.5);
      expect(sizeOf(tester), style.fontSize);
      expect(linesOf(tester), greaterThan(1));
    });
  });

  testWidgets('the header offers search, just before the avatar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpToday(tester, populatedHome(), accounts: [todayAccountJson()]);
    final search = find.byTooltip('Ara');
    expect(search, findsOneWidget);
    final avatar = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_Avatar',
    );
    expect(tester.getCenter(search).dx, lessThan(tester.getCenter(avatar).dx));
    expect(
      (tester.getCenter(search).dy - tester.getCenter(avatar).dy).abs(),
      lessThan(24),
      reason: 'on the greeting row',
    );
  });

  testWidgets('a new account while the accounts and the journal load: no '
      '"₺0", no empty habits card — then the first-run card', (tester) async {
    tester.view.physicalSize = const Size(1170, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final accounts = Completer<Fetched<List<Account>>>();
    final journal = Completer<Fetched<JournalBundle>>();
    await pumpToday(
      tester,
      emptyHome(),
      accounts: null,
      journal: null,
      settle: false,
      overrides: [
        accountsProvider.overrideWith((ref) => accounts.future),
        journalProvider.overrideWith((ref, range) => journal.future),
      ],
    );
    final zeros = RegExp(r'(^|[^\d/])0([^\d/,.]|$)|₺0|0,00|%0');
    for (var i = 0; i < 12; i++) {
      expect(tester.takeException(), isNull);
      expect(
        _texts(
          tester,
        ).where((t) => t != 'Başlayalım · 0/4' && zeros.hasMatch(t)),
        isEmpty,
        reason: 'frame $i',
      );
      expect(find.text('Henüz alışkanlık yok — küçük başla'), findsNothing);
      expect(find.text('Nakit hesabıyla başla'), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
    }
    final at = DateTime(2026, 7, 11);
    accounts.complete(Fetched(const <Account>[], at));
    journal.complete(
      Fetched(
        JournalBundle.fromJson({
          'entries': const [],
          'meta': {
            'entries_count': 0,
            'journal_streak': 0,
            'mood_counts': const <String, int>{},
            'range': '7d',
          },
        }),
        at,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Başlayalım · 0/4'), findsOneWidget);
    expect(find.text('Henüz alışkanlık yok — küçük başla'), findsNothing);
    expect(
      _texts(tester).where((t) => t != 'Başlayalım · 0/4' && zeros.hasMatch(t)),
      isEmpty,
    );
  });

  testWidgets('the next-up chip and the fold of finished events move with '
      'the clock', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    var now = DateTime(2026, 7, 11, 9, 5);
    await pumpToday(
      tester,
      {...populatedHome(), 'today': '2026-07-11'},
      accounts: [todayAccountJson()],
      clock: () => now,
    );
    expect(
      find.bySemanticsLabel('09:30 · Takım toplantısı · 25 dk'),
      findsOneWidget,
    );
    expect(find.text('+1 geçti'), findsNothing);

    // The meeting under way.
    now = DateTime(2026, 7, 11, 9, 40);
    await tester.pump(const Duration(minutes: 1));
    expect(find.bySemanticsLabel('Şimdi · Takım toplantısı'), findsOneWidget);

    // Over: no chip, and it folds into "+1 geçti".
    now = DateTime(2026, 7, 11, 10, 30);
    await tester.pump(const Duration(minutes: 1));
    expect(find.bySemanticsLabel(RegExp('Şimdi|09:30 ·')), findsNothing);
    expect(find.text('+1 geçti'), findsOneWidget);
    handle.dispose();
  });

  group('lingering todos', () {
    Map<String, dynamic> todoMap(int id) => {
      'id': id,
      'title': 'Faturayı öde',
      'status': 'pending',
      'priority': 'medium',
      'due_date': '2026-07-11',
      'overdue': false,
      'position': 1,
      'subtask_count': 0,
    };
    final todo = Todo.fromJson(todoMap(77));

    /// Today over an empty day, with [todo] ticked off and folded into
    /// "1 tamamlandı"; [shown] says whether its tab is shown.
    Future<ProviderContainer> ticked(
      WidgetTester tester,
      ValueNotifier<bool> shown,
    ) async {
      tester.view.physicalSize = const Size(1170, 3900);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpToday(
        tester,
        {...emptyHome(), 'today': '2026-07-11'},
        accounts: [todayAccountJson()],
        wrap: (screen) => ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (_, on, child) => TickerMode(enabled: on, child: child!),
          child: screen,
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TodayScreen)),
      );
      container.read(lingeringTodosProvider.notifier).add(todo, 0);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('1 tamamlandı'), findsOneWidget);
      return container;
    }

    testWidgets('leaving the tab lets the lingering rows go, but a day '
        'whose tasks are all done is still "Hepsi tamam", never "plan yok" '
        '(§7.15)', (tester) async {
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      final container = await ticked(tester, shown);
      // Ticked again and still lingering when the tab is left: its row
      // goes, but it is finished all the same.
      final other = Todo.fromJson(todoMap(78));
      container.read(lingeringTodosProvider.notifier).add(other, 0);
      await tester.pump();
      shown.value = false;
      await tester.pump();
      await tester.pump();
      expect(container.read(lingeringTodosProvider).isEmpty, isTrue);
      expect(container.read(lingeringTodosProvider).finished, 2);
      shown.value = true;
      await tester.pumpAndSettle();
      expect(find.text('2 tamamlandı'), findsOneWidget);
      expect(find.text('Hepsi tamam'), findsOneWidget);
      expect(find.text('Bugün plan yok — sakin bir gün'), findsNothing);
    });

    testWidgets('a todo ticked a moment before the tab is left still makes '
        'the day "Hepsi tamam"', (tester) async {
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      tester.view.physicalSize = const Size(1170, 3900);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpToday(
        tester,
        {...emptyHome(), 'today': '2026-07-11'},
        accounts: [todayAccountJson()],
        wrap: (screen) => ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (_, on, child) => TickerMode(enabled: on, child: child!),
          child: screen,
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TodayScreen)),
      );
      // Ticked (the refetch dropped it), and the tab left a second later,
      // while it still lingers.
      container.read(lingeringTodosProvider.notifier).add(todo, 0);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      shown.value = false;
      await tester.pump();
      await tester.pump();
      shown.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Hepsi tamam'), findsOneWidget);
      expect(find.text('1 tamamlandı'), findsOneWidget);
      expect(find.text('Bugün plan yok — sakin bir gün'), findsNothing);
    });

    testWidgets('a new day forgets yesterday\'s ticks: "plan yok", not '
        '"Hepsi tamam"', (tester) async {
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      final container = await ticked(tester, shown);
      container
          .read(homeProvider.notifier)
          .patch(
            (_) =>
                HomeSummary.fromJson({...emptyHome(), 'today': '2026-07-12'}),
          );
      await tester.pump();
      expect(find.text('1 tamamlandı'), findsNothing);
      expect(find.text('Bugün plan yok — sakin bir gün'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(container.read(lingeringTodosProvider).finished, 0);
      expect(find.text('1 tamamlandı'), findsNothing);
      expect(find.text('Bugün plan yok — sakin bir gün'), findsOneWidget);
    });
  });

  testWidgets('a habit tick rebuilds the habits, not the header', (
    tester,
  ) async {
    _phone(tester);
    await pumpToday(tester, _foldHome(), accounts: [todayAccountJson()]);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TodayScreen)),
    );
    int header() => TodayHeader.debugBuilds;
    int chips() => TodayHeader.debugChipBuilds;
    int nextUp() => TodayNextUp.debugBuilds;
    int agenda() => TodayAgendaSection.debugBuilds;
    int goals() => TodayGoalsSection.debugBuilds;
    final before = [header(), chips(), nextUp(), agenda(), goals()];
    // The tick, as the write's optimistic patch shows it.
    container
        .read(homeProvider.notifier)
        .patch((h) => h.withHabitToday(1, (completed: true, count: 1)));
    await tester.pump();
    expect(find.text('1 tamamlandı'), findsOneWidget, reason: 'redrawn');
    expect(
      [header(), chips(), nextUp(), agenda(), goals()],
      before,
      reason: 'header, chips, next-up, Today card, goals',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('the tap that finishes the day celebrates it from that ring, '
      'once', (tester) async {
    _phone(tester);
    final api = FakeApi()..hold('PUT /habits/3/logs/2026-07-11');
    final home = _foldHome();
    home['today_habits'] = [
      for (final h in home['today_habits'] as List)
        {...(h as Map<String, dynamic>), 'completed_today': h['id'] != 3},
    ];
    await pumpToday(
      tester,
      home,
      accounts: [todayAccountJson()],
      celebrations: true,
      // The write itself is not this test's: it is never answered.
      overrides: [dioProvider.overrideWithValue(api.dio)],
    );
    final ring = find.descendant(
      of: find.byKey(const ValueKey('habit-3')),
      matching: find.byType(CheckPop),
    );
    final centre = tester.getCenter(ring);
    await tester.tap(ring);
    await tester.pump();
    expect(find.byType(ConfettiBurst), findsOneWidget);
    // It bursts from the ring that was tapped.
    final origin = tester.widget<ConfettiBurst>(find.byType(ConfettiBurst));
    expect(origin.origin, isNotNull);
    expect((origin.origin! - centre).distance, lessThan(2));
    // One gesture, one haptic: the day's confirm, not the check under it.
    expect(played, hasLength(1));
    expect(played.single, contains('success'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('one habit ticked: its check, one light haptic; the row stays '
      'a moment, then folds into "1 tamamlandı"', (tester) async {
    _phone(tester);
    final api = FakeApi()..hold('PUT /habits/1/logs/2026-07-11');
    await pumpToday(
      tester,
      _foldHome(),
      accounts: [todayAccountJson()],
      overrides: [dioProvider.overrideWithValue(api.dio)],
    );
    final ring = find.descendant(
      of: find.byKey(const ValueKey('habit-1')),
      matching: find.byType(CheckPop),
    );
    await tester.tap(ring);
    await tester.pump();
    expect(tester.widget<CheckPop>(ring).checked, isTrue);
    expect(played, hasLength(1));
    expect(played.single, contains('light'));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(ring, findsOneWidget, reason: 'held in place');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(ring, findsNothing);
    expect(find.text('1 tamamlandı'), findsOneWidget);
    expect(played, hasLength(1), reason: 'the fold is silent');
  });
}
