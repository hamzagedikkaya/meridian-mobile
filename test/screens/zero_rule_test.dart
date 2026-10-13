/// The zero rules (design-analysis §7.15, WP-17): no screen ever shows a
/// signed zero ("+0,00", "−₺0"), a flame or streak of nothing ("🔥 0",
/// "0 seri", "0 günlük seri"), a rate of nothing yet ("%0 hafta",
/// "%0 (30g)"), or a chart with nothing on its axis.
///
/// The whole app runs (`MeridianApp` signed in, the real router and read
/// models, the scripted API) on a tall phone screen so every section is
/// built, and every page and the habit sheet are visited with three sets of
/// data — the fixtures as they are, a brand-new account with nothing in it,
/// and an account whose every number is zero — in Turkish and in English.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/router/app_router.dart';
import 'package:meridian_mobile/ui/flows/flows.dart' as flows;
import 'package:meridian_mobile/ui/widgets/category_bars.dart';
import 'package:meridian_mobile/ui/widgets/charts.dart';
import 'package:meridian_mobile/ui/widgets/pace_line.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_fonts.dart';
import '../support/fake_api.dart';
import '../support/fake_stores.dart';

/// What must never be on screen, with why.
final _forbidden = <RegExp, String>{
  // A signed zero amount: "+0,00", "−₺0", "-$0.00", "+0 gr".
  RegExp(r'[+−-]\s*[₺$€£]?\s*0(?:[.,]0+)?(?![\d.,])'): 'a signed zero',
  RegExp(r'🔥\s*0(?!\d)'): 'a flame beside 0',
  RegExp(r'(?<![\d.,])0\s+(?:günlük\s+)?seri', caseSensitive: false):
      'a streak of 0',
  RegExp(r'(?<![\d.,])0[-\s]day\s+streak', caseSensitive: false):
      'a streak of 0',
  RegExp(r'%\s*0\s*(?:\(|hafta)', caseSensitive: false):
      'a rate of nothing yet',
  RegExp(r'(?<![\d.,])0\s*%\s*(?:\(|this\s+week|week)', caseSensitive: false):
      'a rate of nothing yet',
  // A count of nothing over an empty list: its empty state says it.
  RegExp(r'^0 (?:kayıt|entries)$'): 'a count of nothing',
  // Nothing in, nothing out: "₺0 gelir · ₺0 gider".
  RegExp(r'[₺$€£]?\s*0(?:[.,]0+)?\s*(?:gelir|in) · [₺$€£]?\s*0(?:[.,]0+)?\s*(?:gider|out)'):
      'two zero totals',
};

/// Today, as the fixtures give it.
const _today = '2026-10-04';

/// A brand-new account: nothing recorded anywhere.
void _fresh(FakeApi api) {
  api
    ..on('GET /home', {
      ...homeJson(),
      'month_net_cents': 0,
      'active_streaks': 0,
      'open_todos': 0,
      'overdue_count': 0,
      'habit_completion_pct': 0,
      'spending_7d': const [],
      'today_habits': const [],
      'upcoming_todos': const [],
      'active_goals': const [],
      'perfect_day': {'chain': const [], 'current_streak': 0},
    })
    ..on('GET /habits', {
      'habits': const [],
      'meta': {
        ...habitsMeta(totalActive: 0),
        'perfect_day': {
          'chain': const [],
          'current_streak': 0,
          'longest_streak': 0,
        },
      },
    })
    ..on('GET /goals', {
      'active': const [],
      'achieved': const [],
      'abandoned': const [],
    })
    ..on('GET /accounts', {'accounts': const []})
    ..on('GET /finance_categories', {'categories': const []})
    ..on('GET /budgets', budgetsJson(budgets: const []))
    ..on('GET /subscriptions', subscriptionsJson(active: const []))
    ..onRequest('GET /transactions', transactionsFeed(const []))
    ..on('GET /todos', {
      'todos': const [],
      'meta': const {
        'open_count': 0,
        'overdue_count': 0,
        'total_count': 0,
        'counts': {
          'open': 0,
          'today': 0,
          'week': 0,
          'upcoming': 0,
          'overdue': 0,
          'undated': 0,
          'done': 0,
          'cancelled': 0,
          'all': 0,
        },
      },
    })
    ..on('GET /todo_lists', {
      'todo_lists': const [],
      'meta': const {'unlisted_open_count': 0},
    })
    ..on('GET /journal_entries', {
      'entries': const [],
      'meta': const {
        'entries_count': 0,
        'journal_streak': 0,
        'journal_streak_weeks': 0,
        'mood_counts': {
          'great': 0,
          'good': 0,
          'neutral': 0,
          'bad': 0,
          'awful': 0,
        },
        'range': '30d',
      },
    });
}

/// An account whose every number is zero: a habit made today, a goal not
/// started, an empty wallet, six quiet months.
void _zeros(FakeApi api) {
  Map<String, dynamic> newHabit(int id, String name, {int target = 1}) => {
        ...habitJson(id: id, name: name, targetCount: target, streak: 0),
        'longest_streak': 0,
        'completion_rate_30d': 0.0,
        'start_date': _today,
        'created_at': '${_today}T08:00:00.000+03:00',
        'chain': const [
          {'date': _today, 'status': 'today_pending'},
        ],
      };
  final habits = [newHabit(7, 'Koşu'), newHabit(8, 'Su', target: 3)];
  api
    ..on('GET /home', {
      ...homeJson(goalProgress: 0),
      'month_net_cents': 0,
      'active_streaks': 0,
      'habit_completion_pct': 0,
      'spending_7d': const [
        {'date': _today, 'cents': 0},
      ],
      'today_habits': [
        for (final h in homeJson()['today_habits'] as List)
          {...(h as Map<String, dynamic>), 'current_streak': 0, 'today_count': 0},
      ],
      'perfect_day': {
        'chain': const [
          {'date': _today, 'status': 'missed'},
        ],
        'current_streak': 0,
      },
    })
    ..on('GET /habits', {
      'habits': habits,
      'meta': {
        ...habitsMeta(),
        'perfect_day': {
          'chain': const [
            {'date': _today, 'status': 'missed'},
          ],
          'current_streak': 0,
          'longest_streak': 0,
        },
      },
    })
    ..on('GET /habits/7', {
      'habit': {
        ...habits.first,
        'logged_days_count': 0,
        'completed_days_count': 0,
        'tracked_by_goals': const [],
      },
    })
    ..on('GET /goals', {
      'active': [goalJson(current: 0)],
      'achieved': const [],
      'abandoned': const [],
    })
    ..on('GET /goals/3', {'goal': goalJson(current: 0)})
    ..on('GET /accounts', {
      'accounts': [accountJson(balance: 0)],
    })
    ..on('GET /budgets', budgetsJson(budgets: [budgetJson(spent: 0)]))
    ..on('GET /finance/dashboard', {
      ...financeDashboardJson(),
      'six_month_series': const {
        'labels': ['May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki'],
        'income_cents': [0, 0, 0, 0, 0, 0],
        'expense_cents': [0, 0, 0, 0, 0, 0],
      },
      'budgets': [budgetJson(spent: 0)],
    })
    ..on('GET /journal_entries', {
      'entries': [journalListItemJson()],
      'meta': const {
        'entries_count': 1,
        'journal_streak': 0,
        'journal_streak_weeks': 0,
        'mood_counts': {
          'great': 0,
          'good': 1,
          'neutral': 0,
          'bad': 0,
          'awful': 0,
        },
        'range': '30d',
      },
    });
}

final _datasets = <String, void Function(FakeApi api)>{
  'the fixtures': (_) {},
  'a brand-new account': _fresh,
  'every number zero': _zeros,
};

/// Every page a user reaches, by its route.
const _pages = [
  '/today',
  '/agenda',
  '/finance',
  '/finance/transactions',
  '/finance/accounts',
  '/finance/account/1',
  '/finance/categories',
  '/finance/subscriptions',
  '/habits',
  '/habits/archived',
  '/goals',
  '/goals/3',
  '/journal',
  '/journal/20',
  '/profile',
];

/// Lets the fake API answer and the screens settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Every string drawn on screen now (onstage only).
List<String> _shownTexts(WidgetTester tester) => [
      for (final t in tester.widgetList<RichText>(find.byType(RichText)))
        t.text.toPlainText(),
    ];

/// What breaks a zero rule on screen now, as "where: what — why".
List<String> _violations(WidgetTester tester, String where) {
  final found = <String>[];
  for (final text in _shownTexts(tester)) {
    for (final MapEntry(key: rule, value: why) in _forbidden.entries) {
      final hit = rule.firstMatch(text);
      if (hit != null) found.add('$where: "$text" — $why ("${hit[0]}")');
    }
  }
  for (final bars in tester.widgetList<SixMonthBars>(find.byType(SixMonthBars))) {
    if (!SixMonthBars.hasEnoughData(bars.incomeCents, bars.expenseCents)) {
      found.add('$where: six-month bars with fewer than two months of data');
    }
  }
  for (final pace in tester.widgetList<PaceLine>(find.byType(PaceLine))) {
    final anything = pace.spent.any((v) => v > 0) ||
        (pace.reference?.any((v) => v > 0) ?? false);
    if (!anything) found.add('$where: a pace line with nothing on it');
  }
  for (final bars in tester.widgetList<CategoryBars>(find.byType(CategoryBars))) {
    if (!bars.items.any((i) => i.cents > 0)) {
      found.add('$where: category bars with nothing spent');
    }
  }
  return found;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    await loadAppFonts();
  });

  test('the rules catch what they are for, and nothing else', () {
    bool breaks(String text) => _forbidden.keys.any((r) => r.hasMatch(text));
    for (final bad in [
      '+0,00',
      '−₺0',
      '-₺0,00',
      '+\$0.00',
      '+0 gr',
      '🔥 0',
      '0 seri',
      '0 günlük seri',
      '0-day streak',
      '%0 hafta',
      '%0 (30g)',
      '0% (30d)',
      '0% this week',
      '0 kayıt',
      '0 entries',
      '₺0 gelir · ₺0 gider',
      '₺0 in · ₺0 out',
    ]) {
      expect(breaks(bad), isTrue, reason: bad);
    }
    for (final fine in [
      '₺0',
      '+₺1.250',
      '−₺0,50',
      '−10',
      '+1',
      '🔥 10',
      '10 günlük seri',
      '%40 (30g)',
      '%100 hafta',
      '40 / 100 kitap',
      'Rekor 0',
      '2026-10-04',
      '10 kayıt',
      '₺0 gelir · ₺138,74 gider',
    ]) {
      expect(breaks(fine), isFalse, reason: fine);
    }
  });

  for (final locale in ['tr', 'en']) {
    for (final MapEntry(key: name, value: seed) in _datasets.entries) {
      testWidgets('$locale, $name: no zero that is not one, no empty chart',
          (tester) async {
        // A tall phone: every section of a page is built.
        tester.view.physicalSize = const Size(1080, 7200);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          PrefKeys.locale: locale,
          PrefKeys.themeMode: 'dark',
          PrefKeys.reduceMotion: 'true',
        });
        final prefs = await SharedPreferences.getInstance();
        final api = FakeApi();
        seed(api);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            dioProvider.overrideWithValue(api.dio),
            ...signedInOverrides(tokens: MemoryTokenStore()),
          ],
          retry: (_, _) => null,
          child: const MeridianApp(),
        ));
        await _settle(tester);
        final router = tester.container().read(routerProvider);

        final found = <String>[];
        for (final page in _pages) {
          router.go(page);
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: page);
          found.addAll(_violations(tester, page));
        }

        // The habit's sheet: its record and its 30-day rate.
        final habits = api.gets.contains('/habits');
        if (habits && name != 'a brand-new account') {
          router.go('/habits');
          await _settle(tester);
          final habit = Habit.fromJson(
            name == 'every number zero'
                ? {
                    ...habitJson(streak: 0),
                    'longest_streak': 0,
                    'completion_rate_30d': 0.0,
                    'start_date': _today,
                    'chain': const [
                      {'date': _today, 'status': 'today_pending'},
                    ],
                  }
                : habitJson(),
          );
          flows.openHabitDetail(tester.element(find.byType(Scaffold).last), habit);
          await _settle(tester);
          expect(tester.takeException(), isNull);
          found.addAll(_violations(tester, 'habit sheet'));
        }

        expect(found, isEmpty, reason: found.join('\n'));
      });
    }
  }
}
