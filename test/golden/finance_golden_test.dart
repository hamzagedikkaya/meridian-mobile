@Tags(['golden'])
/// Finans (the finance dashboard).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-8.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';

import 'golden_harness.dart';

const _en = <String, String>{
  'Altın': 'Gold',
  'Maaş hesabı': 'Salary account',
  'Kredi kartı': 'Credit card',
  'Cüzdan': 'Wallet',
  'Birikim': 'Savings',
  'Kira': 'Rent',
  'Market': 'Groceries',
  'Restoran': 'Restaurants',
  'Eğlence': 'Entertainment',
  'Ulaşım': 'Transport',
  'Temmuz maaşı': 'July salary',
  'Maaş': 'Salary',
  'Migros alışverişi': 'Supermarket run',
  'Benzin': 'Petrol',
  '5 gr altın alımı': 'Bought 5 g of gold',
};

String _fx(String tr) => fx(tr, _en);

// --- Fixtures -----------------------------------------------------------------

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

List<Account> _accounts() => [
      Account.fromJson({'id': 1, 'name': _fx('Altın'), 'account_type': 'savings', 'currency': 'GAU', 'subunit_to_unit': 1, 'color': '#B8860B', 'initial_balance_cents': 300, 'balance_cents': 412, 'archived': false}),
      Account.fromJson({'id': 2, 'name': _fx('Maaş hesabı'), 'account_type': 'bank', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#6B8FA0', 'initial_balance_cents': 850000, 'balance_cents': 4569050, 'archived': false}),
      Account.fromJson({'id': 3, 'name': _fx('Kredi kartı'), 'account_type': 'credit_card', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#B85450', 'initial_balance_cents': 0, 'balance_cents': -1284730, 'archived': false}),
      Account.fromJson({'id': 4, 'name': _fx('Cüzdan'), 'account_type': 'cash', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#D4A574', 'initial_balance_cents': 50000, 'balance_cents': 325000, 'archived': false}),
      Account.fromJson({'id': 5, 'name': _fx('Birikim'), 'account_type': 'savings', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#6B8E5A', 'initial_balance_cents': 10000000, 'balance_cents': 12840000, 'archived': false}),
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
        {'id': 70, 'name': _fx('Kira'), 'color': '#6B8FA0', 'amount_cents': 1800000, 'breakdown': const []},
        {'id': 61, 'name': _fx('Market'), 'color': '#D4915A', 'amount_cents': 1240000, 'breakdown': [{'id': 61, 'name': _fx('Market'), 'amount_cents': 1240000, 'is_root': true}]},
        {'id': 64, 'name': _fx('Restoran'), 'color': '#6B8E5A', 'amount_cents': 890000, 'breakdown': const []},
        {'id': 63, 'name': _fx('Eğlence'), 'color': '#8B5A00', 'amount_cents': 620000, 'breakdown': const []},
        {'id': 62, 'name': _fx('Ulaşım'), 'color': '#B85450', 'amount_cents': 480000, 'breakdown': const []},
      ],
      'budgets': [
        {'category': {'id': 61, 'name': _fx('Market')}, 'color': '#D4915A', 'limit_cents': 1500000, 'spent_cents': 1240000, 'remaining_cents': 260000, 'percent_used': 82.7, 'pace_percent': 75.0, 'projected_cents': 1650000, 'state': 'warning'},
        {'category': {'id': 64, 'name': _fx('Restoran')}, 'color': '#6B8E5A', 'limit_cents': 800000, 'spent_cents': 890000, 'remaining_cents': -90000, 'percent_used': 111.0, 'pace_percent': 90.0, 'projected_cents': 980000, 'state': 'over'},
        {'category': {'id': 63, 'name': _fx('Eğlence')}, 'color': '#8B5A00', 'limit_cents': 1000000, 'spent_cents': 450000, 'remaining_cents': 550000, 'percent_used': 45.0, 'pace_percent': 60.0, 'projected_cents': 800000, 'state': 'under'},
      ],
      'upcoming_subscriptions': [
        {'id': 81, 'name': 'Netflix', 'amount_cents': 18999, 'frequency': 'monthly', 'next_charge_on': ymd(daysAhead(9)), 'account': _acctRef(2, _fx('Maaş hesabı'), '#6B8FA0')},
        {'id': 82, 'name': 'Spotify', 'amount_cents': 7999, 'frequency': 'monthly', 'next_charge_on': ymd(daysAhead(4)), 'account': _acctRef(2, _fx('Maaş hesabı'), '#6B8FA0')},
      ],
      'recent_transactions': [
        {'id': 501, 'kind': 'income', 'amount_cents': 5780000, 'date': ymd(goldenNow), 'description': _fx('Temmuz maaşı'), 'note': null, 'account': _acctRef(2, _fx('Maaş hesabı'), '#6B8FA0'), 'category': _cat(60, _fx('Maaş'), '#6B8E5A', kind: 'income'), 'related_account': null},
        {'id': 502, 'kind': 'expense', 'amount_cents': 23450, 'date': ymd(goldenNow), 'description': _fx('Migros alışverişi'), 'note': null, 'account': _acctRef(3, _fx('Kredi kartı'), '#B85450'), 'category': _cat(61, _fx('Market'), '#D4915A'), 'related_account': null},
        {'id': 503, 'kind': 'transfer', 'amount_cents': 500000, 'date': ymd(daysAgo(1)), 'description': null, 'note': null, 'account': _acctRef(4, _fx('Cüzdan'), '#D4A574'), 'category': null, 'related_account': _acctRef(5, _fx('Birikim'), '#6B8E5A')},
        {'id': 504, 'kind': 'expense', 'amount_cents': 124000, 'date': ymd(daysAgo(1)), 'description': _fx('Benzin'), 'note': null, 'account': _acctRef(3, _fx('Kredi kartı'), '#B85450'), 'category': _cat(62, _fx('Ulaşım'), '#B85450'), 'related_account': null},
        {'id': 505, 'kind': 'income', 'amount_cents': 5, 'date': ymd(daysAgo(2)), 'description': _fx('5 gr altın alımı'), 'note': null, 'account': _acctRef(1, _fx('Altın'), '#B8860B', currency: 'GAU', subunit: 1), 'category': null, 'related_account': null},
      ],
    });

void main() {
  setUpGoldens();

  // WP-8: switch to `variants: GoldenVariant.withLargeText` once the screen
  // lays out at 200 % text without overflow (§8.3); today it does not.
  goldenScreen('finance', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const FinanceScreen(),
      [
        financeDashboardProvider
            .overrideWith((ref) => Fetched(_dashboard(), goldenNow)),
        accountsProvider.overrideWith((ref) => Fetched(_accounts(), goldenNow)),
      ],
    ));
    await tester.pumpAndSettle();
  });
}
