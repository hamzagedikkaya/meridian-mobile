@Tags(['golden'])
/// İşlemler (the transactions feed), the transaction form and the
/// transaction's sheet (design-analysis §7.7).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-9. Every screen here is shot in Turkish and
/// English, dark and light, and at 200 % text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/ui/screens/finance/transaction_form_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/transactions_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/tx_detail_sheet.dart';

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
  'kahve': 'coffee',
  'Kafe': 'Cafés',
  'Haftalık market': 'Weekly groceries',
  'Market': 'Groceries',
  'Kira geliri': 'Rental income',
  'Kira Geliri': 'Rental income',
  'Elektrik faturası': 'Electricity bill',
  'Faturalar': 'Bills',
  'Sinema': 'Cinema',
  'Eğlence': 'Entertainment',
  'Ulaşım': 'Transport',
  'Sağlık': 'Health',
  'Maaş': 'Salary',
  'Kahve çekirdeği, iki paket': 'Coffee beans, two packs',
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
        {String kind = 'expense', int position = 0}) =>
    {
      'id': id,
      'name': name,
      'kind': kind,
      'color': color,
      'parent_id': null,
      'position': position,
    };

List<Account> _accounts() => [
      Account.fromJson({'id': 1, 'name': _fx('Altın'), 'account_type': 'savings', 'currency': 'GAU', 'subunit_to_unit': 1, 'color': '#B8860B', 'initial_balance_cents': 300, 'balance_cents': 412, 'archived': false}),
      Account.fromJson({'id': 2, 'name': _fx('Maaş hesabı'), 'account_type': 'bank', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#6B8FA0', 'initial_balance_cents': 850000, 'balance_cents': 4569050, 'archived': false}),
      Account.fromJson({'id': 3, 'name': _fx('Kredi kartı'), 'account_type': 'credit_card', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#B85450', 'initial_balance_cents': 0, 'balance_cents': -1284730, 'archived': false}),
      Account.fromJson({'id': 4, 'name': _fx('Cüzdan'), 'account_type': 'cash', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#D4A574', 'initial_balance_cents': 50000, 'balance_cents': 325000, 'archived': false}),
      Account.fromJson({'id': 5, 'name': _fx('Birikim'), 'account_type': 'savings', 'currency': 'TRY', 'subunit_to_unit': 100, 'color': '#6B8E5A', 'initial_balance_cents': 10000000, 'balance_cents': 12840000, 'archived': false}),
    ];

/// The categories the form offers, in list order.
List<TxCategory> _categories() => [
      for (final json in [
        _cat(61, _fx('Market'), '#D4915A', position: 1),
        _cat(64, _fx('Restoran'), '#B85450', position: 2),
        _cat(65, _fx('Kafe'), '#8B5A00', position: 3),
        _cat(68, _fx('Ulaşım'), '#6B8FA0', position: 4),
        _cat(67, _fx('Faturalar'), '#7E6BA0', position: 5),
        _cat(63, _fx('Eğlence'), '#A0567E', position: 6),
        _cat(69, _fx('Sağlık'), '#5A8E7E', position: 7),
        _cat(60, _fx('Serbest Gelir'), '#6B8E5A', kind: 'income', position: 1),
        _cat(70, _fx('Maaş'), '#4E7A5A', kind: 'income', position: 2),
      ])
        TxCategory.fromJson(json),
    ];

Transaction _tx(Map<String, dynamic> json) => Transaction.fromJson(json);

/// A rich İşlemler feed spanning Bugün / Dün / older across all kinds.
List<Transaction> _items() => [
      _tx({'id': 901, 'kind': 'income', 'amount_cents': 850000, 'date': ymd(goldenNow), 'description': _fx('Freelance ödemesi'), 'note': null, 'account': _acctRef(2, _fx('Maaş hesabı'), '#6B8FA0'), 'category': _cat(60, _fx('Serbest Gelir'), '#6B8E5A', kind: 'income'), 'related_account': null}),
      _tx({'id': 902, 'kind': 'expense', 'amount_cents': 18500, 'date': ymd(goldenNow), 'description': _fx('Öğle yemeği'), 'note': null, 'account': _acctRef(3, _fx('Kredi kartı'), '#B85450'), 'category': _cat(64, _fx('Restoran'), '#B85450'), 'related_account': null}),
      _tx({'id': 903, 'kind': 'expense', 'amount_cents': 9550, 'date': ymd(goldenNow), 'description': _fx('Kahve'), 'note': _fx('Kahve çekirdeği, iki paket'), 'account': _acctRef(4, _fx('Cüzdan'), '#D4A574'), 'category': _cat(65, _fx('Kafe'), '#8B5A00'), 'related_account': null}),
      _tx({'id': 904, 'kind': 'transfer', 'amount_cents': 300000, 'date': ymd(daysAgo(1)), 'description': null, 'note': null, 'account': _acctRef(4, _fx('Cüzdan'), '#D4A574'), 'category': null, 'related_account': _acctRef(5, _fx('Birikim'), '#6B8E5A')}),
      _tx({'id': 905, 'kind': 'expense', 'amount_cents': 45675, 'date': ymd(daysAgo(1)), 'description': _fx('Haftalık market'), 'note': null, 'account': _acctRef(3, _fx('Kredi kartı'), '#B85450'), 'category': _cat(61, _fx('Market'), '#D4915A'), 'related_account': null}),
      _tx({'id': 906, 'kind': 'income', 'amount_cents': 1200000, 'date': ymd(daysAgo(5)), 'description': _fx('Kira geliri'), 'note': null, 'account': _acctRef(2, _fx('Maaş hesabı'), '#6B8FA0'), 'category': _cat(66, _fx('Kira Geliri'), '#6B8E5A', kind: 'income'), 'related_account': null}),
      _tx({'id': 907, 'kind': 'expense', 'amount_cents': 89000, 'date': ymd(daysAgo(5)), 'description': _fx('Elektrik faturası'), 'note': null, 'account': _acctRef(2, _fx('Maaş hesabı'), '#6B8FA0'), 'category': _cat(67, _fx('Faturalar'), '#6B8FA0'), 'related_account': null}),
      _tx({'id': 908, 'kind': 'expense', 'amount_cents': 24000, 'date': ymd(daysAgo(5)), 'description': _fx('Sinema'), 'note': null, 'account': _acctRef(4, _fx('Cüzdan'), '#D4A574'), 'category': _cat(63, _fx('Eğlence'), '#8B5A00'), 'related_account': null}),
    ];

/// [items] as one page of the feed, with their totals.
TransactionsFeed _feed(List<Transaction> items) {
  var income = 0;
  var expense = 0;
  for (final tx in items) {
    if (tx.kind == 'income') income += tx.amountCents;
    if (tx.kind == 'expense') expense += tx.amountCents;
  }
  return TransactionsFeed(
    items: items,
    meta: TransactionMeta(
      totalCount: items.length,
      page: 1,
      pageLimit: 50,
      filteredIncomeCents: income,
      filteredExpenseCents: expense,
    ),
    hasMore: false,
    at: goldenNow,
  );
}

/// Stub notifier: serves a fixed feed whatever the filters.
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

/// What every screen here reads, the feed being [feed].
List<Override> _overrides(TransactionsFeed feed) => [
      // ignore: deprecated_member_use
      transactionsProvider.overrideWith(() => _StubTxNotifier(feed)),
      accountsProvider.overrideWith((ref) => Fetched(_accounts(), goldenNow)),
      categoriesProvider.overrideWith((ref) => Fetched(_categories(), goldenNow)),
    ];

/// The transaction form, new, on Cüzdan.
Widget _form({String? kind, int? amountCents}) => TransactionFormScreen(
      initialAccountId: 4,
      initialKind: kind,
      initialAmountCents: amountCents,
    );

void main() {
  setUpGoldens();
  const variants = GoldenVariant.withLargeText;

  // --- İşlemler -----------------------------------------------------------------

  goldenScreen('transactions', variants: variants, (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const TransactionsScreen(),
      _overrides(_feed(_items())),
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('transactions_filter_empty', variants: variants,
      (tester, _) async {
    await tester.pumpWidget(goldenHost(
      TransactionsScreen(
        initial: TxFilters(
          kind: 'transfer',
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 10, 31),
        ),
      ),
      _overrides(_feed(const [])),
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('transactions_search', variants: variants, (tester, _) async {
    final query = _fx('kahve');
    await tester.pumpWidget(goldenHost(
      TransactionsScreen(initial: TxFilters(q: query)),
      _overrides(_feed([
        for (final tx in _items())
          if (txMatchesQuery(tx, query)) tx,
      ])),
    ));
    await tester.pumpAndSettle();
    // The field is focused: put the keyboard focus away so the shot does
    // not depend on the caret's blink.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  });

  // --- The form -------------------------------------------------------------------

  goldenScreen('tx_form', variants: variants, (tester, _) async {
    await tester.pumpWidget(goldenHost(
      _form(amountCents: 125050),
      _overrides(_feed(_items())),
    ));
    await tester.pumpAndSettle();
    // One chip: the category.
    await tester.tap(find.text(_fx('Market')));
    await tester.pumpAndSettle();
  });

  goldenScreen('tx_form_transfer', variants: variants, (tester, _) async {
    await tester.pumpWidget(goldenHost(
      _form(kind: 'transfer', amountCents: 50000),
      _overrides(_feed(_items())),
    ));
    await tester.pumpAndSettle();
    final target = find.text(goldenVariant.lang == 'en'
        ? 'Pick a target account'
        : 'Hedef hesap seç');
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(_fx('Birikim')),
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('tx_form_text', variants: variants, (tester, _) async {
    await tester.pumpWidget(goldenHost(
      _form(amountCents: 9550),
      _overrides(_feed(_items())),
    ));
    await tester.pumpAndSettle();
    final chip =
        find.text(goldenVariant.lang == 'en' ? 'Description' : 'Açıklama');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, _fx('Kahve'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  });

  // --- The sheet ------------------------------------------------------------------

  goldenScreen('tx_detail', variants: variants, (tester, _) async {
    final tx = _items()[2];
    late BuildContext host;
    late WidgetRef hostRef;
    await tester.pumpWidget(goldenHost(
      Consumer(builder: (context, ref, _) {
        host = context;
        hostRef = ref;
        return const Scaffold(body: SizedBox.expand());
      }),
      [
        ..._overrides(_feed(_items())),
        transactionDetailProvider.overrideWith(
          (ref, id) => Fetched(TransactionDetail(transaction: tx), goldenNow),
        ),
      ],
    ));
    showTransactionSheet(host, hostRef, tx);
    await tester.pumpAndSettle();
  });
}
