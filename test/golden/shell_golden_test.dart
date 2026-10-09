@Tags(['golden'])
/// The signed-in shell: Bugün over the five-tab bar, with the overdue badge
/// on Ajanda (design-analysis §6.1, §4.18).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-4.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/shell/app_scaffold.dart';
import 'package:meridian_mobile/ui/screens/shell/app_tabs.dart';
import 'package:meridian_mobile/ui/screens/shell/fade_through_branches.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';

import 'golden_harness.dart';

const _en = <String, String>{
  'Sabah koşusu': 'Morning run',
  '2 litre su iç': 'Drink 2 L of water',
  '30 dakika kitap oku': 'Read for 30 minutes',
  'Vergi beyannamesini gönder': 'File the tax return',
  'Faturayı öde': 'Pay the bill',
  'İş': 'Work',
  'Takım toplantısı': 'Team meeting',
  '100 günde 100 kitap': '100 books in 100 days',
};

String _fx(String tr) => fx(tr, _en);

const _user = User(
  id: 1,
  displayName: 'Hamza Gedikkaya',
  initials: 'HG',
  email: 'hamza@meridian.local',
  currency: 'TRY',
  subunitToUnit: 100,
  locale: 'tr',
  themePreference: 'dark',
);

/// /home with two overdue todos — the count on the Ajanda tab.
HomeSummary _home() => HomeSummary.fromJson({
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'month_net_cents': 1250000,
      'active_streaks': 2,
      'open_todos': 2,
      'overdue_count': 2,
      'today_events_count': 1,
      'habit_completion_pct': 70,
      'spending_7d': [
        for (var i = 6; i >= 0; i--)
          {'date': ymd(daysAgo(i)), 'cents': 30000 + i * 7000},
      ],
      'today_habits': [
        {'id': 1, 'name': _fx('Sabah koşusu'), 'color': '#6B8E5A', 'target_count': 1, 'completed_today': true, 'today_count': 1, 'current_streak': 12},
        {'id': 2, 'name': _fx('2 litre su iç'), 'color': '#6B8FA0', 'target_count': 8, 'completed_today': false, 'today_count': 5, 'current_streak': 6},
        {'id': 3, 'name': _fx('30 dakika kitap oku'), 'color': '#B8860B', 'target_count': 1, 'completed_today': false, 'today_count': 0, 'current_streak': 3},
      ],
      'upcoming_todos': [
        {'id': 11, 'title': _fx('Vergi beyannamesini gönder'), 'status': 'pending', 'priority': 'urgent', 'due_at': '${ymd(daysAgo(1))}T17:00:00.000Z', 'overdue': true, 'position': 1, 'todo_list': {'id': 1, 'name': _fx('İş'), 'color': '#6B8FA0'}, 'subtask_count': 0},
        {'id': 12, 'title': _fx('Faturayı öde'), 'status': 'pending', 'priority': 'high', 'due_at': '${ymd(daysAgo(2))}T09:00:00.000Z', 'overdue': true, 'position': 2, 'subtask_count': 0},
      ],
      'today_events': [
        {'id': 21, 'title': _fx('Takım toplantısı'), 'start_at': '${ymd(goldenNow)}T09:30:00.000Z', 'end_at': '${ymd(goldenNow)}T10:15:00.000Z', 'all_day': false, 'color': '#6B8FA0'},
      ],
      'active_goals': [
        {'id': 31, 'name': _fx('100 günde 100 kitap'), 'color': '#6B8E5A', 'progress_percent': 68.0},
      ],
      'perfect_day': {
        'chain': [{'date': ymd(goldenNow), 'status': 'today_pending'}],
        'current_streak': 2,
        'longest_streak': 12,
      },
    });

/// The shell as the app builds it — [AppScaffold] over
/// [FadeThroughBranches] — with Bugün selected; the other tabs are never
/// built for the shot.
Widget _shellHost() {
  final variant = goldenVariant;
  final router = GoRouter(
    initialLocation: '/today',
    routes: [
      StatefulShellRoute(
        builder: (context, state, shell) => AppScaffold(shell: shell),
        navigatorContainerBuilder: (context, shell, children) =>
            FadeThroughBranches(
          currentIndex: shell.currentIndex,
          children: children,
        ),
        branches: [
          for (final tab in AppTab.values)
            StatefulShellBranch(routes: [
              GoRoute(
                path: tab.location,
                pageBuilder: (_, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: tab == AppTab.today
                      ? const TodayScreen()
                      : const SizedBox.shrink(),
                ),
              ),
            ]),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(() => goldenNow),
      homeProvider.overrideWithBuild((ref, _) => Fetched(_home(), goldenNow)),
      habitCadenceProvider.overrideWithBuild(
        (ref, _) => const {1: true, 2: true, 3: true},
      ),
      currentUserProvider.overrideWithValue(_user),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(variant.brightness),
      locale: Locale(variant.lang),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(variant.textScale)),
        child: child!,
      ),
      routerConfig: router,
    ),
  );
}

void main() {
  setUpGoldens();

  goldenScreen(
    'shell_today',
    variants: const [GoldenVariant.trDark, GoldenVariant.trLight],
    (tester, _) async {
      await tester.pumpWidget(_shellHost());
      await tester.pumpAndSettle();
    },
  );
}
