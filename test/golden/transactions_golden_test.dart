@Tags(['golden'])
/// İşlemler (the transactions feed).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-9.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/ui/screens/finance/transactions_screen.dart';

import 'golden_harness.dart';

const _en = <String, String>{
  'Altın': 'Gold',
  'Maaş hesabı': 'Salary account',
  'Kredi kartı': 'Credit card',
  'Cüzdan': 'Wallet',
  'Birikim': 'Savings',
  'Freelance ödemesi': 'Freelance payment',
  'Serbest Gelir': 'Freelance',
  'Öğle yemeği': 'Lunch',
  'Restoran': 'Restaurants',
  'Kahve': 'Coffee',
  'Kafe': 'Cafés',
  'Haftalık market': 'Weekly groceries',
  'Market': 'Groceries',
  'Kira geliri': 'Rental income',
  'Kira Geliri': 'Rental income',
  'Elektrik faturası': 'Electricity bill',
  'Faturalar': 'Bills',
  'Sinema': 'Cinema',
  'Eğlence': 'Entertainment',
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

Transaction _tx(Map<String, dynamic> json) => Transaction.fromJson(json);

/// A rich İşlemler feed spanning Bugün / Dün / older across all kinds.
TransactionsFeed _txFeed() {
  final items = [
    _tx({'id': 901, 'kind': 'income', 'amount_cents': 850000, 'date': ymd(goldenNow), 'description': _fx('Freelance ödemesi'), 'note': null, 'account': _acctRef(2, _fx('Maaş hesabı'), '#6B8FA0'), 'category': _cat(60, _fx('Serbest Gelir'), '#6B8E5A', kind: 'income'), 'related_account': null}),
    _tx({'id': 902, 'kind': 'expense', 'amount_cents': 18500, 'date': ymd(goldenNow), 'description': _fx('Öğle yemeği'), 'note': null, 'account': _acctRef(3, _fx('Kredi kartı'), '#B85450'), 'category': _cat(64, _fx('Restoran'), '#B85450'), 'related_account': null}),
    _tx({'id': 903, 'kind': 'expense', 'amount_cents': 9550, 'date': ymd(goldenNow), 'description': _fx('Kahve'), 'note': null, 'account': _acctRef(4, _fx('Cüzdan'), '#D4A574'), 'category': _cat(65, _fx('Kafe'), '#8B5A00'), 'related_account': null}),
    _tx({'id': 904, 'kind': 'transfer', 'amount_cents': 300000, 'date': ymd(daysAgo(1)), 'description': null, 'note': null, 'account': _acctRef(4, _fx('Cüzdan'), '#D4A574'), 'category': null, 'related_account': _acctRef(5, _fx('Birikim'), '#6B8E5A')}),
    _tx({'id': 905, 'kind': 'expense', 'amount_cents': 45675, 'date': ymd(daysAgo(1)), 'description': _fx('Haftalık market'), 'note': null, 'account': _acctRef(3, _fx('Kredi kartı'), '#B85450'), 'category': _cat(61, _fx('Market'), '#D4915A'), 'related_account': null}),
    _tx({'id': 906, 'kind': 'income', 'amount_cents': 1200000, 'date': ymd(daysAgo(5)), 'description': _fx('Kira geliri'), 'note': null, 'account': _acctRef(2, _fx('Maaş hesabı'), '#6B8FA0'), 'category': _cat(66, _fx('Kira Geliri'), '#6B8E5A', kind: 'income'), 'related_account': null}),
    _tx({'id': 907, 'kind': 'expense', 'amount_cents': 89000, 'date': ymd(daysAgo(5)), 'description': _fx('Elektrik faturası'), 'note': null, 'account': _acctRef(2, _fx('Maaş hesabı'), '#6B8FA0'), 'category': _cat(67, _fx('Faturalar'), '#6B8FA0'), 'related_account': null}),
    _tx({'id': 908, 'kind': 'expense', 'amount_cents': 24000, 'date': ymd(daysAgo(5)), 'description': _fx('Sinema'), 'note': null, 'account': _acctRef(4, _fx('Cüzdan'), '#D4A574'), 'category': _cat(63, _fx('Eğlence'), '#8B5A00'), 'related_account': null}),
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
    at: goldenNow,
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

void main() {
  setUpGoldens();

  goldenScreen('transactions', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const TransactionsScreen(),
      [
        // ignore: deprecated_member_use
        transactionsProvider.overrideWith(() => _StubTxNotifier(_txFeed())),
        accountsProvider.overrideWith((ref) => Fetched(_accounts(), goldenNow)),
        categoriesProvider
            .overrideWith((ref) => Fetched(const <TxCategory>[], goldenNow)),
      ],
    ));
    await tester.pumpAndSettle();
  });
}
