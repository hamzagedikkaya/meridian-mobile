@Tags(['golden'])
/// Finans (the finance dashboard), Hesaplar, an account's page and its
/// "Gerçek bakiye" sheet.
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-8.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/models/subscription.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/ui/screens/finance/account_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/accounts_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';
import 'package:meridian_mobile/ui/widgets/app_snackbar.dart';

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
  'Eski kart': 'Old card',
  'Kahve': 'Coffee',
  'Kafe': 'Cafés',
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
      'totals_by_currency': [
        {'currency': 'TRY', 'subunit_to_unit': 100,
          'month': {'income_cents': 5780000, 'expense_cents': 3320000, 'net_cents': 2460000},
          'year': {'income_cents': 68400000, 'expense_cents': 47200000}},
        {'currency': 'GAU', 'subunit_to_unit': 1,
          'month': {'income_cents': 5, 'expense_cents': 0, 'net_cents': 5},
          'year': {'income_cents': 5, 'expense_cents': 0}},
      ],
      // 4 October: four days of this month, the 30 of September.
      'spend_cumulative_cents': [1800000, 2120000, 3196000, 3320000],
      'reference_cumulative_cents': [
        for (var d = 1; d <= 30; d++) 1800000 + (d - 1) * 60000,
      ],
      'six_month_series': {
        'labels': ['2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10'],
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

FinanceDashboard _emptyDashboard() => FinanceDashboard.fromJson({
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'month': {'income_cents': 0, 'expense_cents': 0, 'net_cents': 0},
      'year': {'income_cents': 0, 'expense_cents': 0},
      'totals_by_currency': [
        {'currency': 'TRY', 'subunit_to_unit': 100,
          'month': {'income_cents': 0, 'expense_cents': 0, 'net_cents': 0},
          'year': {'income_cents': 0, 'expense_cents': 0}},
      ],
      'spend_cumulative_cents': [0, 0, 0, 0],
      'reference_cumulative_cents': List.filled(30, 0),
      'six_month_series': {
        'labels': ['2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10'],
        'income_cents': [0, 0, 0, 0, 0, 0],
        'expense_cents': [0, 0, 0, 0, 0, 0],
      },
    });

const _noSubscriptions =
    SubscriptionsBundle(active: [], inactive: [], totals: []);

/// The wallet's history: today and yesterday.
TransactionsFeed _walletFeed() {
  final wallet = _acctRef(4, _fx('Cüzdan'), '#D4A574');
  final items = [
    Transaction.fromJson({'id': 601, 'kind': 'expense', 'amount_cents': 8500, 'date': ymd(goldenNow), 'description': _fx('Kahve'), 'note': null, 'account': wallet, 'category': _cat(65, _fx('Kafe'), '#8B5A00'), 'related_account': null}),
    Transaction.fromJson({'id': 602, 'kind': 'expense', 'amount_cents': 23450, 'date': ymd(goldenNow), 'description': _fx('Migros alışverişi'), 'note': null, 'account': wallet, 'category': _cat(61, _fx('Market'), '#D4915A'), 'related_account': null}),
    Transaction.fromJson({'id': 603, 'kind': 'transfer', 'amount_cents': 500000, 'date': ymd(daysAgo(1)), 'description': null, 'note': null, 'account': _acctRef(2, _fx('Maaş hesabı'), '#6B8FA0'), 'category': null, 'related_account': wallet}),
    Transaction.fromJson({'id': 604, 'kind': 'expense', 'amount_cents': 124000, 'date': ymd(daysAgo(1)), 'description': _fx('Benzin'), 'note': null, 'account': wallet, 'category': _cat(62, _fx('Ulaşım'), '#B85450'), 'related_account': null}),
  ];
  return TransactionsFeed(
    items: items,
    meta: TransactionMeta.fromJson(const {
      'total_count': 4,
      'page': 1,
      'page_limit': 50,
    }),
    hasMore: false,
    at: goldenNow,
  );
}

/// Serves a fixed feed; nothing it is asked to do reaches a server.
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

AccountDetail _walletDetail() => AccountDetail.fromJson({
      'id': 4, 'name': _fx('Cüzdan'), 'account_type': 'cash', 'currency': 'TRY',
      'subunit_to_unit': 100, 'color': '#D4A574',
      'initial_balance_cents': 50000, 'balance_cents': 325000,
      'archived': false, 'transactions_count': 4,
      'incoming_transfers_count': 1, 'subscriptions_count': 0,
      'linked_goals_count': 1,
    });

/// What every screen here reads, fixed.
List<dynamic> _overrides({
  FinanceDashboard? dashboard,
  List<Account>? accounts,
}) =>
    [
      financeDashboardProvider.overrideWith(
          (ref) => Fetched(dashboard ?? _dashboard(), goldenNow)),
      accountsProvider
          .overrideWith((ref) => Fetched(accounts ?? _accounts(), goldenNow)),
      subscriptionsProvider
          .overrideWith((ref) => Fetched(_noSubscriptions, goldenNow)),
      accountDetailProvider
          .overrideWith((ref, id) => Fetched(_walletDetail(), goldenNow)),
      // ignore: deprecated_member_use
      transactionsProvider.overrideWith(() => _StubTxNotifier(_walletFeed())),
    ];

Future<void> _pumpFinance(
  WidgetTester tester, {
  FinanceDashboard? dashboard,
  List<Account>? accounts,
}) async {
  await tester.pumpWidget(goldenHost(
    const FinanceScreen(),
    _overrides(dashboard: dashboard, accounts: accounts).cast(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpGoldens();

  goldenScreen('finance', variants: GoldenVariant.withLargeText,
      (tester, variant) async {
    await _pumpFinance(tester);
    if (variant.textScale == 1.0) {
      // Now first: "Son işlemler" starts within the first 1300 dp
      // (design-analysis §7.5; it was ≈ 2050) — measured on a phone tall
      // enough to lay it all out.
      tester.view.physicalSize = const Size(1080, 3 * 2000);
      await tester.pumpAndSettle();
      final recent = find.byKey(const ValueKey('recent'));
      expect(tester.getTopLeft(recent).dy, lessThan(1300));
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pumpAndSettle();
    }
  });

  goldenScreen('finance_first_run', (tester, _) async {
    await _pumpFinance(
      tester,
      dashboard: _emptyDashboard(),
      accounts: const [],
    );
  });

  goldenScreen('finance_one_account', (tester, _) async {
    await _pumpFinance(
      tester,
      dashboard: _emptyDashboard(),
      accounts: [_accounts()[3]],
    );
  });

  goldenScreen('finance_undo', (tester, variant) async {
    await _pumpFinance(tester);
    final context = tester.element(find.byType(ListView).first);
    final l = AppL10n.forLocale(Locale(variant.lang));
    showAppSnack(
      context,
      l.accountArchived(_fx('Cüzdan')),
      actionLabel: l.actionUndo,
      onAction: () {},
    );
    await tester.pumpAndSettle();
  });

  goldenScreen('accounts', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const AccountsScreen(showArchived: true),
      _overrides(accounts: [
        ..._accounts(),
        Account.fromJson({'id': 9, 'name': _fx('Eski kart'), 'account_type': 'credit_card', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#8B5A00', 'initial_balance_cents': 0, 'balance_cents': 0, 'archived': true}),
      ]).cast(),
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('account_detail', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const AccountDetailScreen(accountId: 4),
      _overrides().cast(),
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('reconcile_sheet', (tester, variant) async {
    await tester.pumpWidget(goldenHost(
      const AccountDetailScreen(accountId: 4),
      _overrides().cast(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(
        variant.lang == 'en' ? 'Reconcile balance' : 'Bakiyeyi eşitle'));
    await tester.pumpAndSettle();
    for (final digit in ['3', '3', '7', '0']) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  });
}
