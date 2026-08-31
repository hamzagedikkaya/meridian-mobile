import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';

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

Future<void> pumpToday(WidgetTester tester, Map<String, dynamic> home) async {
  final summary = HomeSummary.fromJson(home);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeProvider.overrideWith(
          (ref) => Fetched(summary, DateTime(2026, 7, 11)),
        ),
        currentUserProvider.overrideWithValue(_fixtureUser),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('tr'), Locale('en')],
        home: const TodayScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // Widgets format overdue todo dates with DateFormat('…','tr_TR').
    await initializeDateFormatting();
  });

  testWidgets('Bugün renders populated /home without exceptions', (tester) async {
    // Tall canvas (390×1300 logical) so every section is laid out by the
    // SliverList and reachable by find.text, while width 390 still surfaces
    // any horizontal overflow via takeException.
    tester.view.physicalSize = const Size(1170, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpToday(tester, populatedHome());

    expect(tester.takeException(), isNull);

    // User + section headers.
    expect(find.text('Demo User'), findsOneWidget);
    expect(find.text('Alışkanlıklar'), findsOneWidget);
    expect(find.text('Hedefler'), findsOneWidget);

    // Entities from each section.
    expect(find.text('Gym session'), findsOneWidget);
    expect(find.text('Read for 100 days'), findsOneWidget);
    expect(find.text('Deploy v1.2'), findsOneWidget);
    expect(find.text('Takım toplantısı'), findsOneWidget);
    expect(find.text('Tüm gün'), findsOneWidget);
  });

  testWidgets('Bugün renders empty/edge /home without exceptions',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpToday(tester, emptyHome());

    expect(tester.takeException(), isNull);

    // Empty-state copy for each section (design §4.3).
    expect(find.text('Bugün plan yok — sakin bir gün ☁'), findsOneWidget);
    expect(find.text('Henüz alışkanlık yok — küçük başla'), findsOneWidget);
    expect(find.text('Henüz hedef yok — ilk hedefini koy'), findsOneWidget);

    // Zero net still renders as signed "+0,00 ₺" (net ≥ 0, tr_TR, 2 decimals).
    expect(find.text('+0,00 ₺'), findsOneWidget);
  });
}
