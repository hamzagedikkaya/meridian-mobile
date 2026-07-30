/// GOLDEN RENDER HARNESS (visual review, not correctness assertions).
///
/// Renders every screen at phone size (360×780 logical, dpr 3.0) with the REAL
/// bundled fonts (Fraunces + Inter) and rich, realistic Turkish fixtures, then
/// writes one PNG per screen under test/golden/images/ via `matchesGoldenFile`.
///
/// Generate with:
///   flutter test --update-goldens test/golden/render_screens_test.dart
///
/// The fixtures reuse the provider-override patterns from test/screens/*.dart
/// but are fully populated so the design can be judged from the images.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/models/journal.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/aliskanliklar/aliskanliklar_screen.dart';
import 'package:meridian_mobile/ui/screens/bugun/bugun_screen.dart';
import 'package:meridian_mobile/ui/screens/gunluk/gunluk_screen.dart';
import 'package:meridian_mobile/ui/screens/hedefler/hedefler_screen.dart';
import 'package:meridian_mobile/ui/screens/login_screen.dart';
import 'package:meridian_mobile/ui/screens/para/islemler_screen.dart';
import 'package:meridian_mobile/ui/screens/para/para_screen.dart';
import 'package:meridian_mobile/ui/screens/profil/profil_screen.dart';

// --- Dates (relative to "now" so Bugün/Dün/deadlines render correctly) --------

final DateTime _now = DateTime.now();
final DateTime _at = DateTime(_now.year, _now.month, _now.day, 9, 41);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _daysAgo(int n) => _now.subtract(Duration(days: n));
DateTime _daysAhead(int n) => _now.add(Duration(days: n));

// --- Fixtures -----------------------------------------------------------------

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

Map<String, dynamic> _acctRef(int id, String name, String color,
        {String currency = 'TRY', int subunit = 100}) =>
    {
      'id': id,
      'name': name,
      'color': color,
      'currency': currency,
      'subunit_to_unit': subunit,
    };

Map<String, dynamic> _cat(int id, String name, String color,
        {String kind = 'expense'}) =>
    {
      'id': id,
      'name': name,
      'kind': kind,
      'color': color,
      'parent_id': null,
      'position': 0,
    };

/// Rich /home payload for Bugün.
HomeSummary _home() => HomeSummary.fromJson({
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'month_net_cents': 4275000, // +42.750,00 ₺
      'active_streaks': 5,
      'open_todos': 3,
      'overdue_count': 1,
      'today_events_count': 3,
      'habit_completion_pct': 82,
      'spending_7d': [
        {'date': _ymd(_daysAgo(6)), 'cents': 32000},
        {'date': _ymd(_daysAgo(5)), 'cents': 87500},
        {'date': _ymd(_daysAgo(4)), 'cents': 41000},
        {'date': _ymd(_daysAgo(3)), 'cents': 123000},
        {'date': _ymd(_daysAgo(2)), 'cents': 64000},
        {'date': _ymd(_daysAgo(1)), 'cents': 98000},
        {'date': _ymd(_now), 'cents': 52000},
      ],
      'today_habits': [
        {'id': 1, 'name': 'Sabah koşusu', 'color': '#6B8E5A', 'target_count': 1, 'completed_today': true, 'today_count': 1, 'current_streak': 12},
        {'id': 2, 'name': '2 litre su iç', 'color': '#6B8FA0', 'target_count': 8, 'completed_today': false, 'today_count': 5, 'current_streak': 6},
        {'id': 3, 'name': '30 dakika kitap oku', 'color': '#B8860B', 'target_count': 1, 'completed_today': false, 'today_count': 0, 'current_streak': 3},
        {'id': 4, 'name': 'Meditasyon', 'color': '#8B5A00', 'target_count': 1, 'completed_today': true, 'today_count': 1, 'current_streak': 20},
        {'id': 5, 'name': 'Almanca çalış', 'color': '#B85450', 'target_count': 1, 'completed_today': false, 'today_count': 0, 'current_streak': 0},
      ],
      'upcoming_todos': [
        {'id': 11, 'title': 'Vergi beyannamesini gönder', 'status': 'pending', 'priority': 'urgent', 'due_at': '${_ymd(_daysAgo(1))}T17:00:00.000Z', 'overdue': true, 'position': 1, 'todo_list': {'id': 1, 'name': 'İş', 'color': '#6B8FA0'}, 'subtask_count': 2},
        {'id': 12, 'title': 'Sunum slaytlarını hazırla', 'status': 'pending', 'priority': 'high', 'due_at': '${_ymd(_now)}T15:30:00.000Z', 'overdue': false, 'position': 2, 'todo_list': {'id': 1, 'name': 'İş', 'color': '#6B8FA0'}, 'subtask_count': 0},
        {'id': 13, 'title': 'Market alışverişi yap', 'status': 'pending', 'priority': 'low', 'due_at': '${_ymd(_now)}T19:00:00.000Z', 'overdue': false, 'position': 3, 'todo_list': {'id': 2, 'name': 'Ev', 'color': '#6B8E5A'}, 'subtask_count': 0},
      ],
      'today_events': [
        {'id': 21, 'title': 'Takım toplantısı', 'start_at': '${_ymd(_now)}T09:30:00.000Z', 'end_at': '${_ymd(_now)}T10:15:00.000Z', 'all_day': false, 'color': '#6B8FA0'},
        {'id': 22, 'title': 'Diş hekimi randevusu', 'start_at': '${_ymd(_now)}T14:00:00.000Z', 'end_at': '${_ymd(_now)}T14:45:00.000Z', 'all_day': false, 'color': '#B85450'},
        {'id': 23, 'title': 'Annemin doğum günü', 'start_at': null, 'end_at': null, 'all_day': true, 'color': '#B8860B'},
      ],
      'active_goals': [
        {'id': 31, 'name': '100 günde 100 kitap', 'color': '#6B8E5A', 'progress_percent': 68.0},
        {'id': 32, 'name': 'Almanca A2 seviyesi', 'color': '#6B8FA0', 'progress_percent': 35.0},
        {'id': 33, 'name': 'İlk 5K koşusu', 'color': '#B8860B', 'progress_percent': 90.0},
      ],
      'perfect_day': {
        'chain': [{'date': _ymd(_now), 'status': 'today_pending'}],
        'current_streak': 5,
        'longest_streak': 12,
      },
    });

List<Account> _accounts() => [
      Account.fromJson(const {'id': 1, 'name': 'Altın', 'account_type': 'savings', 'currency': 'GAU', 'subunit_to_unit': 1, 'color': '#B8860B', 'initial_balance_cents': 300, 'balance_cents': 412, 'archived': false}),
      Account.fromJson(const {'id': 2, 'name': 'Maaş hesabı', 'account_type': 'bank', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#6B8FA0', 'initial_balance_cents': 850000, 'balance_cents': 4569050, 'archived': false}),
      Account.fromJson(const {'id': 3, 'name': 'Kredi kartı', 'account_type': 'credit_card', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#B85450', 'initial_balance_cents': 0, 'balance_cents': -1284730, 'archived': false}),
      Account.fromJson(const {'id': 4, 'name': 'Cüzdan', 'account_type': 'cash', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#D4A574', 'initial_balance_cents': 50000, 'balance_cents': 325000, 'archived': false}),
      Account.fromJson(const {'id': 5, 'name': 'Birikim', 'account_type': 'savings', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#6B8E5A', 'initial_balance_cents': 10000000, 'balance_cents': 12840000, 'archived': false}),
    ];

FinanceDashboard _dashboard() => FinanceDashboard.fromJson({
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'month': {'income_cents': 5780000, 'expense_cents': 3320000, 'net_cents': 2460000},
      'year': {'income_cents': 68400000, 'expense_cents': 47200000},
      'six_month_series': {
        'labels': ['2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07'],
        'income_cents': [4820000, 5140000, 4560000, 6230000, 5480000, 5780000],
        'expense_cents': [3210000, 3670000, 2980000, 4120000, 3540000, 3320000],
      },
      'pie': [
        {'id': 70, 'name': 'Kira', 'color': '#6B8FA0', 'amount_cents': 1800000, 'breakdown': const []},
        {'id': 61, 'name': 'Market', 'color': '#D4915A', 'amount_cents': 1240000, 'breakdown': [{'id': 61, 'name': 'Market', 'amount_cents': 1240000, 'is_root': true}]},
        {'id': 64, 'name': 'Restoran', 'color': '#6B8E5A', 'amount_cents': 890000, 'breakdown': const []},
        {'id': 63, 'name': 'Eğlence', 'color': '#8B5A00', 'amount_cents': 620000, 'breakdown': const []},
        {'id': 62, 'name': 'Ulaşım', 'color': '#B85450', 'amount_cents': 480000, 'breakdown': const []},
      ],
      'budgets': [
        {'category': {'id': 61, 'name': 'Market'}, 'color': '#D4915A', 'limit_cents': 1500000, 'spent_cents': 1240000, 'remaining_cents': 260000, 'percent_used': 82.7, 'pace_percent': 75.0, 'projected_cents': 1650000, 'state': 'warning'},
        {'category': {'id': 64, 'name': 'Restoran'}, 'color': '#6B8E5A', 'limit_cents': 800000, 'spent_cents': 890000, 'remaining_cents': -90000, 'percent_used': 111.0, 'pace_percent': 90.0, 'projected_cents': 980000, 'state': 'over'},
        {'category': {'id': 63, 'name': 'Eğlence'}, 'color': '#8B5A00', 'limit_cents': 1000000, 'spent_cents': 450000, 'remaining_cents': 550000, 'percent_used': 45.0, 'pace_percent': 60.0, 'projected_cents': 800000, 'state': 'under'},
      ],
      'upcoming_subscriptions': [
        {'id': 81, 'name': 'Netflix', 'amount_cents': 18999, 'frequency': 'monthly', 'next_charge_on': _ymd(_daysAhead(9)), 'account': _acctRef(2, 'Maaş hesabı', '#6B8FA0')},
        {'id': 82, 'name': 'Spotify', 'amount_cents': 7999, 'frequency': 'monthly', 'next_charge_on': _ymd(_daysAhead(4)), 'account': _acctRef(2, 'Maaş hesabı', '#6B8FA0')},
      ],
      'recent_transactions': [
        {'id': 501, 'kind': 'income', 'amount_cents': 5780000, 'date': _ymd(_now), 'description': 'Temmuz maaşı', 'note': null, 'account': _acctRef(2, 'Maaş hesabı', '#6B8FA0'), 'category': _cat(60, 'Maaş', '#6B8E5A', kind: 'income'), 'related_account': null},
        {'id': 502, 'kind': 'expense', 'amount_cents': 23450, 'date': _ymd(_now), 'description': 'Migros alışverişi', 'note': null, 'account': _acctRef(3, 'Kredi kartı', '#B85450'), 'category': _cat(61, 'Market', '#D4915A'), 'related_account': null},
        {'id': 503, 'kind': 'transfer', 'amount_cents': 500000, 'date': _ymd(_daysAgo(1)), 'description': null, 'note': null, 'account': _acctRef(4, 'Cüzdan', '#D4A574'), 'category': null, 'related_account': _acctRef(5, 'Birikim', '#6B8E5A')},
        {'id': 504, 'kind': 'expense', 'amount_cents': 124000, 'date': _ymd(_daysAgo(1)), 'description': 'Benzin', 'note': null, 'account': _acctRef(3, 'Kredi kartı', '#B85450'), 'category': _cat(62, 'Ulaşım', '#B85450'), 'related_account': null},
        {'id': 505, 'kind': 'income', 'amount_cents': 5, 'date': _ymd(_daysAgo(2)), 'description': '5 gr altın alımı', 'note': null, 'account': _acctRef(1, 'Altın', '#B8860B', currency: 'GAU', subunit: 1), 'category': null, 'related_account': null},
      ],
    });

Transaction _tx(Map<String, dynamic> json) => Transaction.fromJson(json);

/// A rich İşlemler feed spanning Bugün / Dün / older across all kinds.
TransactionsFeed _txFeed() {
  final items = [
    _tx({'id': 901, 'kind': 'income', 'amount_cents': 850000, 'date': _ymd(_now), 'description': 'Freelance ödemesi', 'note': null, 'account': _acctRef(2, 'Maaş hesabı', '#6B8FA0'), 'category': _cat(60, 'Serbest Gelir', '#6B8E5A', kind: 'income'), 'related_account': null}),
    _tx({'id': 902, 'kind': 'expense', 'amount_cents': 18500, 'date': _ymd(_now), 'description': 'Öğle yemeği', 'note': null, 'account': _acctRef(3, 'Kredi kartı', '#B85450'), 'category': _cat(64, 'Restoran', '#B85450'), 'related_account': null}),
    _tx({'id': 903, 'kind': 'expense', 'amount_cents': 9550, 'date': _ymd(_now), 'description': 'Kahve', 'note': null, 'account': _acctRef(4, 'Cüzdan', '#D4A574'), 'category': _cat(65, 'Kafe', '#8B5A00'), 'related_account': null}),
    _tx({'id': 904, 'kind': 'transfer', 'amount_cents': 300000, 'date': _ymd(_daysAgo(1)), 'description': null, 'note': null, 'account': _acctRef(4, 'Cüzdan', '#D4A574'), 'category': null, 'related_account': _acctRef(5, 'Birikim', '#6B8E5A')}),
    _tx({'id': 905, 'kind': 'expense', 'amount_cents': 45675, 'date': _ymd(_daysAgo(1)), 'description': 'Haftalık market', 'note': null, 'account': _acctRef(3, 'Kredi kartı', '#B85450'), 'category': _cat(61, 'Market', '#D4915A'), 'related_account': null}),
    _tx({'id': 906, 'kind': 'income', 'amount_cents': 1200000, 'date': _ymd(_daysAgo(5)), 'description': 'Kira geliri', 'note': null, 'account': _acctRef(2, 'Maaş hesabı', '#6B8FA0'), 'category': _cat(66, 'Kira Geliri', '#6B8E5A', kind: 'income'), 'related_account': null}),
    _tx({'id': 907, 'kind': 'expense', 'amount_cents': 89000, 'date': _ymd(_daysAgo(5)), 'description': 'Elektrik faturası', 'note': null, 'account': _acctRef(2, 'Maaş hesabı', '#6B8FA0'), 'category': _cat(67, 'Faturalar', '#6B8FA0'), 'related_account': null}),
    _tx({'id': 908, 'kind': 'expense', 'amount_cents': 24000, 'date': _ymd(_daysAgo(5)), 'description': 'Sinema', 'note': null, 'account': _acctRef(4, 'Cüzdan', '#D4A574'), 'category': _cat(63, 'Eğlence', '#8B5A00'), 'related_account': null}),
  ];
  return TransactionsFeed(
    items: items,
    meta: TransactionMeta.fromJson(const {
      'total_count': 8,
      'page': 1,
      'page_limit': 50,
      'filtered_income_cents': 2050000,
      'filtered_expense_cents': 186725,
    }),
    hasMore: false,
    at: _at,
  );
}

/// Stub notifier: serves a fixed feed and no-ops the initState setFilters().
class _StubTxNotifier extends TransactionsNotifier {
  _StubTxNotifier(this._feed) : super(const TxFilters());
  final TransactionsFeed _feed;

  @override
  Future<TransactionsFeed> build() async => _feed;
  @override
  Future<void> loadMore() async {}
  @override
  Future<void> refresh() async {}
}

/// Build a chain of [statuses.length] days ending today.
List<Map<String, dynamic>> _chain(List<String> statuses) {
  final n = statuses.length;
  return [
    for (var i = 0; i < n; i++)
      {'date': _ymd(_daysAgo(n - 1 - i)), 'status': statuses[i]},
  ];
}

HabitsBundle _habits() => HabitsBundle.fromJson({
      'habits': [
        {'id': 1, 'name': 'Sabah koşusu', 'description': 'Her sabah 3 km', 'frequency': 'daily', 'target_count': 1, 'color': '#6B8E5A', 'goal_id': null, 'current_streak': 12, 'longest_streak': 21, 'completion_rate_30d': 0.86, 'today': {'date': _ymd(_now), 'completed': true, 'count': 1}, 'chain': _chain(['completed', 'completed', 'missed', 'completed', 'completed', 'completed', 'completed', 'missed', 'completed', 'completed', 'completed', 'completed', 'completed', 'completed'])},
        {'id': 2, 'name': '2 litre su iç', 'description': 'Gün içinde 8 bardak', 'frequency': 'daily', 'target_count': 8, 'color': '#6B8FA0', 'goal_id': null, 'current_streak': 6, 'longest_streak': 15, 'completion_rate_30d': 0.70, 'today': {'date': _ymd(_now), 'completed': false, 'count': 5}, 'chain': _chain(['completed', 'missed', 'completed', 'completed', 'completed', 'missed', 'completed', 'completed', 'completed', 'missed', 'completed', 'completed', 'completed', 'today_pending'])},
        {'id': 3, 'name': 'Spor salonu', 'description': 'Haftada 3 gün', 'frequency': 'weekly', 'target_count': 3, 'color': '#B85450', 'goal_id': null, 'current_streak': 4, 'longest_streak': 9, 'completion_rate_30d': 0.60, 'today': {'date': _ymd(_now), 'completed': false, 'count': 0}, 'chain': [{'date': _ymd(_now), 'status': 'today_pending'}], 'period': {'range_start': _ymd(_daysAgo(5)), 'range_end': _ymd(_daysAhead(1)), 'completed_count': 2, 'complete': false}},
        {'id': 4, 'name': 'Meditasyon', 'description': '10 dakika', 'frequency': 'daily', 'target_count': 1, 'color': '#8B5A00', 'goal_id': null, 'current_streak': 20, 'longest_streak': 20, 'completion_rate_30d': 1.0, 'today': {'date': _ymd(_now), 'completed': true, 'count': 1}, 'chain': _chain(List.filled(14, 'completed'))},
        {'id': 5, 'name': 'Almanca çalış', 'description': 'Duolingo', 'frequency': 'daily', 'target_count': 1, 'color': '#B8860B', 'goal_id': null, 'current_streak': 0, 'longest_streak': 11, 'completion_rate_30d': 0.30, 'today': {'date': _ymd(_now), 'completed': false, 'count': 0}, 'chain': _chain(['missed', 'completed', 'missed', 'missed', 'completed', 'missed', 'missed', 'completed', 'missed', 'missed', 'missed', 'completed', 'missed', 'missed'])},
      ],
      'meta': {
        'completed_today': 2,
        'total_active': 5,
        'perfect_day': {
          'chain': _chain(['perfect', 'completed', 'partial', 'perfect', 'missed', 'completed', 'perfect', 'no_habits', 'completed', 'partial', 'perfect', 'completed', 'perfect', 'today_pending']),
          'current_streak': 3,
          'longest_streak': 12,
        },
      },
    });

Map<String, dynamic> _goalJson({
  required int id,
  required String name,
  String targetType = 'custom',
  String status = 'active',
  required String color,
  String unit = '',
  String? deadline,
  required int daysRemaining,
  Map<String, dynamic>? badge,
  required num targetValue,
  required num currentValue,
  required num progress,
}) =>
    {
      'id': id,
      'name': name,
      'description': '',
      'target_type': targetType,
      'status': status,
      'color': color,
      'unit': unit,
      'deadline': deadline,
      'days_remaining': daysRemaining,
      'deadline_badge': badge,
      'target_value': targetValue,
      'current_value': currentValue,
      'progress_percent': progress,
      'related': null,
    };

GoalsBundle _goals() => GoalsBundle.fromJson({
      'active': [
        _goalJson(id: 31, name: '100 günde 100 kitap oku', targetType: 'habit', color: '#6B8E5A', unit: 'kitap', deadline: _ymd(_daysAhead(53)), daysRemaining: 53, badge: {'state': 'far', 'days': 53}, targetValue: 100, currentValue: 20, progress: 20),
        _goalJson(id: 32, name: 'Almanca A2 seviyesine ulaş', targetType: 'custom', color: '#6B8FA0', unit: 'ders', deadline: _ymd(_daysAhead(5)), daysRemaining: 5, badge: {'state': 'soon', 'days': 5}, targetValue: 50, currentValue: 24, progress: 48),
        _goalJson(id: 33, name: 'İlk 5K koşuma hazırlan', targetType: 'habit', color: '#B8860B', unit: 'antrenman', deadline: _ymd(_now), daysRemaining: 0, badge: {'state': 'today', 'days': 0}, targetValue: 40, currentValue: 30, progress: 75),
        _goalJson(id: 34, name: 'Acil vergi ödemesi', targetType: 'financial', color: '#B85450', unit: 'TRY', deadline: _ymd(_daysAgo(3)), daysRemaining: -3, badge: {'state': 'overdue', 'days': 3}, targetValue: 50000, currentValue: 47500, progress: 96),
      ],
      'achieved': [
        _goalJson(id: 30, name: '3 ayda 50.000 ₺ biriktir', targetType: 'financial', status: 'achieved', color: '#B8860B', unit: 'TRY', deadline: null, daysRemaining: 0, badge: null, targetValue: 50000, currentValue: 52000, progress: 100),
      ],
      'abandoned': const [],
    });

JournalBundle _journal() => JournalBundle.fromJson({
      'entries': [
        {'id': 41, 'date': _ymd(_now), 'title': 'Harika bir gün', 'body_plain': 'Sabah yoga ile başladım, öğleden sonra ekiple güzel bir toplantı yaptık. Akşam ailemle yemek yedik — enerjim gün boyu yüksek kaldı.', 'mood': 'great', 'mood_emoji': '😄', 'energy_level': 5, 'weather': 'Güneşli', 'tags': ['spor', 'aile'], 'has_gratitude': true, 'created_at': '${_ymd(_now)}T20:10:00.000Z'},
        {'id': 42, 'date': _ymd(_daysAgo(1)), 'title': 'Sakin bir akşam', 'body_plain': 'Yağmurlu bir gündü. İçeride kalıp uzun süredir okumak istediğim kitabı bitirdim.', 'mood': 'good', 'mood_emoji': '🙂', 'energy_level': 3, 'weather': 'Yağmurlu', 'tags': ['okuma'], 'has_gratitude': false, 'created_at': '${_ymd(_daysAgo(1))}T21:00:00.000Z'},
        {'id': 43, 'date': _ymd(_daysAgo(2)), 'title': null, 'body_plain': 'Kısa bir not aldım, gün nötr geçti.', 'mood': 'neutral', 'mood_emoji': '😐', 'energy_level': 2, 'weather': null, 'tags': const <String>[], 'has_gratitude': false, 'created_at': '${_ymd(_daysAgo(2))}T18:00:00.000Z'},
        {'id': 44, 'date': _ymd(_daysAgo(4)), 'title': 'Yorucu ama verimli', 'body_plain': 'Proje teslimine yetiştirdik. Yorgunum ama başardığımız için mutluyum.', 'mood': 'good', 'mood_emoji': '🙂', 'energy_level': 4, 'weather': 'Parçalı bulutlu', 'tags': ['iş', 'proje'], 'has_gratitude': true, 'created_at': '${_ymd(_daysAgo(4))}T22:30:00.000Z'},
      ],
      'meta': {
        'entries_count': 4,
        'journal_streak': 8,
        'mood_counts': {'great': 1, 'good': 2, 'neutral': 1, 'bad': 0, 'awful': 0},
        'range': '30d',
      },
    });

// --- Harness ------------------------------------------------------------------

Widget _host(Widget home, List<dynamic> overrides) => ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('tr'), Locale('en')],
        home: home,
      ),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340); // 360×780 logical @ 3.0
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _shoot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('images/$name.png'));

// Load a bundled font as ByteData: try the asset bundle, fall back to the file
// system (font assets aren't in flutter_test's rootBundle manifest).
Future<ByteData> _fontData(String path) async {
  try {
    return await rootBundle.load(path);
  } catch (_) {
    final bytes = await File(path).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

/// Load the SDK's MaterialIcons font so `Icon`s render as real glyphs (not
/// tofu). Resolves the Flutter root from FLUTTER_ROOT, else from the Dart
/// executable path (`root/bin/cache/dart-sdk/bin/dart`). Best-effort.
Future<void> _loadMaterialIcons() async {
  final roots = <String>[];
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) roots.add(env);
  try {
    var dir = File(Platform.resolvedExecutable).parent; // …/dart-sdk/bin
    for (var i = 0; i < 4; i++) {
      dir = dir.parent;
    }
    roots.add(dir.path);
  } catch (_) {/* ignore */}

  for (final root in roots) {
    final f = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (f.existsSync()) {
      final bytes = await f.readAsBytes();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      return;
    }
  }
}

late SharedPreferences _prefs;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final fraunces = FontLoader('Fraunces')
      ..addFont(_fontData('assets/fonts/Fraunces-Regular.ttf'))
      ..addFont(_fontData('assets/fonts/Fraunces-SemiBold.ttf'));
    await fraunces.load();

    final inter = FontLoader('Inter')
      ..addFont(_fontData('assets/fonts/Inter-Regular.ttf'))
      ..addFont(_fontData('assets/fonts/Inter-Medium.ttf'))
      ..addFont(_fontData('assets/fonts/Inter-SemiBold.ttf'));
    await inter.load();

    await _loadMaterialIcons();

    await initializeDateFormatting('tr_TR', null);
    await initializeDateFormatting('tr', null);

    SharedPreferences.setMockInitialValues({
      'server_url': 'http://192.168.1.24:3000',
      'theme_mode': 'dark',
    });
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('login.png', (tester) async {
    // A zone-local fake HttpClient makes ServerUrlField's /health ping succeed,
    // so the address field collapses to the "✓ host · Değiştir" success state
    // and the credentials section is at full opacity.
    await HttpOverrides.runZoned<Future<void>>(
      () async {
        _phone(tester);
        await tester.pumpWidget(_host(
          const LoginScreen(),
          [sharedPrefsProvider.overrideWithValue(_prefs)],
        ));
        await tester.pumpAndSettle();
        await _shoot(tester, 'login');
      },
      createHttpClient: (_) => _OkHealthClient(),
    );
  });

  testWidgets('bugun.png', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(
      const BugunScreen(),
      [
        homeProvider.overrideWith((ref) => Fetched(_home(), _at)),
        currentUserProvider.overrideWithValue(_user),
      ],
    ));
    await tester.pumpAndSettle();
    await _shoot(tester, 'bugun');
  });

  testWidgets('para.png', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(
      const ParaScreen(),
      [
        financeDashboardProvider.overrideWith((ref) => Fetched(_dashboard(), _at)),
        accountsProvider.overrideWith((ref) => Fetched(_accounts(), _at)),
      ],
    ));
    await tester.pumpAndSettle();
    await _shoot(tester, 'para');
  });

  testWidgets('islemler.png', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(
      const IslemlerScreen(),
      [
        // ignore: deprecated_member_use
        transactionsProvider.overrideWith(() => _StubTxNotifier(_txFeed())),
        accountsProvider.overrideWith((ref) => Fetched(_accounts(), _at)),
      ],
    ));
    await tester.pumpAndSettle();
    await _shoot(tester, 'islemler');
  });

  testWidgets('aliskanliklar.png', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(
      const AliskanliklarScreen(),
      [habitsProvider.overrideWith((ref) async => Fetched(_habits(), _at))],
    ));
    await tester.pumpAndSettle();
    await _shoot(tester, 'aliskanliklar');
  });

  testWidgets('hedefler.png', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(
      const HedeflerScreen(),
      [goalsProvider.overrideWith((ref) async => Fetched(_goals(), _at))],
    ));
    await tester.pumpAndSettle();
    await _shoot(tester, 'hedefler');
  });

  testWidgets('gunluk.png', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(
      const GunlukScreen(),
      [journalProvider.overrideWith((ref, range) => Fetched(_journal(), _at))],
    ));
    await tester.pumpAndSettle();
    // Let the 650ms stagger-retire timer fire so no timer outlives the tree.
    await tester.pump(const Duration(milliseconds: 700));
    await _shoot(tester, 'gunluk');
  });

  testWidgets('profil.png', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(
      const ProfilScreen(),
      [
        sharedPrefsProvider.overrideWithValue(_prefs),
        currentUserProvider.overrideWithValue(_user),
        apiHealthProvider.overrideWith(
          (ref) async => (ok: true, latencyMs: 12, version: '1.0.0'),
        ),
      ],
    ));
    await tester.pumpAndSettle();
    await _shoot(tester, 'profil');
  });
}

// --- Fake HttpClient for the login /health ping (returns 200 {"ok":true}) -----

class _OkHealthClient implements HttpClient {
  @override
  Duration idleTimeout = const Duration(seconds: 3);
  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _OkHealthRequest();

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OkHealthRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _OkHealthHeaders();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;

  @override
  Future<HttpClientResponse> close() async => _OkHealthResponse();
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OkHealthHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String name, List<String> values) action) {
    action('content-type', const ['application/json; charset=utf-8']);
  }

  @override
  String? value(String name) => name.toLowerCase() == 'content-type'
      ? 'application/json; charset=utf-8'
      : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OkHealthResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _OkHealthResponse._(this._bytes) : super(Stream<List<int>>.value(_bytes));
  factory _OkHealthResponse() =>
      _OkHealthResponse._(utf8.encode('{"ok":true,"version":"1.0.0"}'));

  final List<int> _bytes;

  @override
  int get statusCode => 200;
  @override
  String get reasonPhrase => 'OK';
  @override
  int get contentLength => _bytes.length;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];
  @override
  HttpHeaders get headers => _OkHealthHeaders();
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
