/// The finance endpoints of contract G2, through the real repository: what
/// each write sends (an edit only the keys it changes), what each read asks
/// for, how the answers parse, and which refusals refetch what they prove
/// out of date. (What each write refreshes is in sync_test.dart.)
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/data/data_scope.dart';
import 'package:meridian_mobile/data/deferred_deletes.dart';
import 'package:meridian_mobile/data/recent_changes.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/repository.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/budget.dart';
import 'package:meridian_mobile/models/finance_category.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/models/subscription.dart';
import 'package:meridian_mobile/models/transaction.dart';

import '../support/fake_api.dart';
import '../support/read_models.dart';

void main() {
  late FakeApi api;
  late ProviderContainer container;
  late MeridianRepository repo;

  /// The query of every GET to [path] so far.
  final queries = <String, List<Map<String, dynamic>>>{};
  void recordQueries(String path, Object? Function(RequestOptions) answer) {
    api.onRequest('GET $path', (request) {
      queries.putIfAbsent(path, () => []).add(request.queryParameters);
      return answer(request);
    });
  }

  setUp(() {
    api = FakeApi();
    container = containerFor(api);
    repo = container.read(repositoryProvider);
    queries.clear();
  });

  group('accounts', () {
    test('the list asks for the archived ones too, and reads their state',
        () async {
      recordQueries('/accounts', (_) => {
            'accounts': [
              accountJson(),
              accountJson(id: 4, name: 'Eski kart', archived: true),
            ],
          });
      final accounts = await repo.fetchAccounts();
      expect(queries['/accounts']!.single, {'include_archived': true});
      expect(accounts.map((a) => a.archived), [false, true]);
      expect(accounts.last.archivedAt, DateTime(2026, 10, 1, 12));
      expect(accounts.first.archivedAt, isNull);
    });

    test('the detail says what is recorded on it', () async {
      api.on('GET /accounts/1', {
        'account': accountDetailJson(transactions: 4, incoming: 1, subscriptions: 2, goals: 1),
      });
      final detail = await repo.fetchAccount(1);
      expect(detail.account.name, 'Cüzdan');
      expect(detail.transactionsCount, 4);
      expect(detail.incomingTransfersCount, 1);
      expect(detail.subscriptionsCount, 2);
      expect(detail.linkedGoalsCount, 1);
      expect(detail.deletable, isFalse);
      expect(detail.currencyEditable, isFalse);
    });

    test('a create sends every field; without a currency the server picks '
        'the user\'s', () async {
      await repo.createAccount(const AccountInput(
        name: 'Kredi kartı',
        accountType: 'credit_card',
        currency: 'TRY',
        initialBalanceCents: -235000,
        color: '#B85450',
      ));
      await repo.createAccount(const AccountInput(
        name: 'Nakit',
        accountType: 'cash',
        color: '#D4A853',
      ));
      expect(api.bodiesOf('POST /accounts'), [
        {
          'name': 'Kredi kartı',
          'account_type': 'credit_card',
          'currency': 'TRY',
          'initial_balance_cents': -235000,
          'color': '#B85450',
        },
        {
          'name': 'Nakit',
          'account_type': 'cash',
          'initial_balance_cents': 0,
          'color': '#D4A853',
        },
      ]);
    });

    test('an edit sends only what changed; a new currency carries the '
        'opening balance with it', () async {
      final before = Account.fromJson(accountJson(initial: 150000));
      await repo.updateAccount(
        before,
        const AccountInput(
          name: 'Ziraat',
          accountType: 'cash',
          currency: 'TRY',
          initialBalanceCents: 150000,
          color: '#d4a574', // the same colour, another letter case
        ),
      );
      await repo.updateAccount(
        before,
        const AccountInput(
          name: 'Cüzdan',
          accountType: 'cash',
          currency: 'USD',
          initialBalanceCents: 150000,
          color: '#D4A574',
        ),
      );
      expect(api.bodiesOf('PATCH /accounts/1'), [
        {'name': 'Ziraat'},
        {'currency': 'USD', 'initial_balance_cents': 150000},
      ]);
    });

    test('archive and restore', () async {
      final archived = await repo.archiveAccount(1);
      final restored = await repo.unarchiveAccount(1);
      expect(archived.archived, isTrue);
      expect(restored.archived, isFalse);
      expect(api.requests, [
        'PATCH /accounts/1/archive',
        'PATCH /accounts/1/unarchive',
      ]);
    });

    test('a delete refused for history says how much, and refetches the '
        'account\'s detail (it now offers archiving)', () async {
      await showEverything(container, api);
      api.on('DELETE /accounts/1', {
        'errors': {'base': ['Bu hesapta işlem olduğu için silinemez.']},
        'code': 'has_transactions',
        'transactions_count': 4,
        'incoming_transfers_count': 1,
      }, status: 422);
      await expectLater(
        repo.deleteAccount(1),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'has_transactions')
            .having((e) => e.number('transactions_count'), 'count', 4)),
      );
      await settle(api);
      expect(api.gets.toSet(), {'/accounts', '/accounts/1', '/currencies'});
    });

    test('a currency change refused because the account is in use refetches '
        'its detail', () async {
      await showEverything(container, api);
      api.on('PATCH /accounts/1', {
        'errors': {'currency': ['x']},
        'code': 'currency_locked',
      }, status: 422);
      await expectLater(
        repo.updateAccount(
          Account.fromJson(accountJson()),
          const AccountInput(
            name: 'Cüzdan',
            accountType: 'cash',
            currency: 'USD',
            color: '#D4A574',
          ),
        ),
        throwsA(isA<ApiException>()),
      );
      await settle(api);
      expect(api.gets, contains('/accounts/1'));
    });

    test('the currencies: the offered ones and the default', () async {
      final bundle = await repo.fetchCurrencies();
      expect(bundle.defaultCurrency, 'TRY');
      expect(bundle.currencies.map((c) => c.code),
          ['TRY', 'USD', 'EUR', 'GBP', 'GAU']);
      expect(bundle.byCode('gau')!.subunitToUnit, 1);
    });
  });

  group('transactions', () {
    test('a transaction created, edited or brought back here is noted, so '
        'its row animates (§4.29, §5.4)', () async {
      final changes = container.read(recentChangesProvider.notifier);
      final saved = await repo.createTransaction(TransactionInput(
        kind: 'expense',
        amountCents: 2500,
        date: DateTime(2026, 10, 4),
        accountId: 1,
      ));
      expect(changes.of(DataScope.transactions, saved.id),
          ChangeKind.inserted);

      final before = Transaction.fromJson(transactionJson());
      await repo.updateTransaction(
        before,
        TransactionInput(
          kind: before.kind,
          amountCents: 999,
          date: before.date,
          accountId: before.account.id,
        ),
      );
      expect(changes.of(DataScope.transactions, 316), ChangeKind.updated);

      const record = (scope: DataScope.transactions, id: 317);
      final deletes = container.read(deferredDeletesProvider.notifier);
      deletes.stage(record, send: () async {});
      deletes.undo(record);
      expect(changes.of(DataScope.transactions, 317), ChangeKind.restored);
    });

    test('uncategorized asks for category_id=none; incoming transfers only '
        'come with an account', () async {
      recordQueries('/transactions', (_) => {
            'transactions': const [],
            'meta': const {'total_count': 0, 'page': 1, 'page_limit': 50},
          });
      await repo.fetchTransactions(uncategorized: true, kind: 'expense');
      await repo.fetchTransactions(accountId: 3, includeIncomingTransfers: true);
      await repo.fetchTransactions(includeIncomingTransfers: true);
      expect(queries['/transactions'], [
        {'kind': 'expense', 'category_id': 'none', 'page': 1},
        {'account_id': 3, 'include_incoming_transfers': true, 'page': 1},
        {'page': 1},
      ]);
    });

    test('a create without a category sends none: an uncategorized row',
        () async {
      await repo.createTransaction(TransactionInput(
        kind: 'expense',
        amountCents: 2500,
        date: DateTime(2026, 10, 4),
        accountId: 1,
      ));
      expect(api.bodiesOf('POST /transactions').single, {
        'kind': 'expense',
        'amount_cents': 2500,
        'date': '2026-10-04',
        'account_id': 1,
      });
    });

    test('an edit sends only what changed — a note it did not touch stays, '
        'a cleared category goes as null', () async {
      final before = Transaction.fromJson({
        ...transactionJson(),
        'note': 'web\'den not',
        'category': categoryJson(),
      });
      await repo.updateTransaction(
        before,
        TransactionInput(
          kind: 'expense',
          amountCents: 15000,
          date: before.date,
          description: 'Kahve',
          note: 'web\'den not',
          accountId: 1,
        ),
      );
      expect(api.bodiesOf('PATCH /transactions/316').single, {
        'amount_cents': 15000,
        'finance_category_id': null,
      });
    });

    test('the detail of a transaction without a pair: no linked row, and a '
        'delete takes nothing along', () async {
      final detail = await repo.fetchTransaction(316);
      expect(api.requests, ['GET /transactions/316']);
      expect(detail.transaction.id, 316);
      expect(detail.transaction.description, 'Kahve');
      expect(detail.parentTransactionId, isNull);
      expect(detail.linked, isNull);
      expect(detail.deletesLinked, isFalse);
    });

    test('the parent of a linked pair: its child is deleted with it',
        () async {
      api.on('GET /transactions/316', {
        'transaction': transactionDetailJson(linked: linkedJson()),
      });
      final detail = await repo.fetchTransaction(316);
      final linked = detail.linked!;
      expect(linked.id, 317);
      expect(linked.kind, 'income');
      expect(linked.amountCents, 2);
      expect(linked.date, DateTime(2026, 10, 2));
      expect(linked.description, 'Altın alımı');
      expect(linked.account.name, 'Altın');
      expect(linked.account.currency, 'GAU');
      expect(linked.account.subunitToUnit, 1);
      expect(linked.isChild, isTrue);
      expect(detail.deletesLinked, isTrue);
    });

    test('the child of a linked pair: its parent stays when it is deleted',
        () async {
      api.on('GET /transactions/316', {
        'transaction': transactionDetailJson(
          parentId: 310,
          linked: linkedJson(
            id: 310,
            kind: 'expense',
            amount: 600000,
            relation: 'parent',
          ),
        ),
      });
      final detail = await repo.fetchTransaction(316);
      expect(detail.parentTransactionId, 310);
      expect(detail.linked!.isChild, isFalse);
      expect(detail.deletesLinked, isFalse);
    });
  });

  group('categories', () {
    group('moving a category\'s transactions', () {
      void twoToMove() => api
        ..on('GET /transactions', {
          'transactions': [transactionJson(), transactionJson(id: 317)],
          'meta': const {
            'total_count': 2,
            'page': 1,
            'page_limit': 50,
            'filtered_income_cents': 0,
            'filtered_expense_cents': 0,
          },
        })
        ..on('PATCH /transactions/316',
            {'error': 'not_found', 'code': 'not_found'}, status: 404);

      test('a transaction deleted meanwhile is skipped', () async {
        twoToMove();
        api
          ..on('PATCH /transactions/317', transactionJson(id: 317))
          ..on('GET /finance_categories/8',
              {'category': categoryUsageJson(id: 8)});
        expect(await repo.moveCategoryTransactions(5, 8), 1);
      });

      test('the category to move to deleted meanwhile stops the move',
          () async {
        twoToMove();
        api
          ..on('PATCH /transactions/317',
              {'error': 'not_found', 'code': 'not_found'}, status: 404)
          ..on('GET /finance_categories/8',
              {'error': 'not_found', 'code': 'not_found'}, status: 404);
        await expectLater(
          repo.moveCategoryTransactions(5, 8),
          throwsA(isA<CategoryMoveFailed>()
              .having((e) => e.moved, 'moved', 0)
              .having((e) => e.total, 'total', 2)),
        );
      });
    });

    test('the detail says what a delete would touch', () async {
      api.on('GET /finance_categories/5', {
        'category': categoryUsageJson(children: 1, transactions: 47, budgets: 1),
      });
      final usage = await repo.fetchCategory(5);
      expect(usage.category.name, 'Market');
      expect(usage.childrenCount, 1);
      expect(usage.transactionsCount, 47);
      expect(usage.budgetsCount, 1);
      expect(usage.budgetId, 2);
      expect(usage.kindEditable, isFalse);
      expect(usage.unused, isFalse);
    });

    test('a create names its parent (null for a top-level one); an edit '
        'sends only what changed', () async {
      await repo.createCategory(const CategoryInput(
        name: 'Atıştırmalık',
        kind: 'expense',
        parentId: 5,
        color: '#C9A227',
      ));
      await repo.updateCategory(
        TxCategory.fromJson(categoryJson()),
        const CategoryInput(
          name: 'Market',
          kind: 'expense',
          color: '#6B8E5A',
        ),
      );
      expect(api.bodiesOf('POST /finance_categories').single, {
        'name': 'Atıştırmalık',
        'kind': 'expense',
        'parent_id': 5,
        'color': '#C9A227',
      });
      expect(api.bodiesOf('PATCH /finance_categories/5').single,
          {'color': '#6B8E5A'});
    });

    test('a type change refused because the category is in use refetches '
        'its detail', () async {
      await showEverything(container, api);
      api.on('PATCH /finance_categories/5', {
        'errors': {'kind': ['x']},
        'code': 'kind_locked',
      }, status: 422);
      await expectLater(
        repo.updateCategory(
          TxCategory.fromJson(categoryJson()),
          const CategoryInput(name: 'Market', kind: 'income', color: '#D4915A'),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'kind_locked')),
      );
      await settle(api);
      expect(api.gets.toSet(),
          {'/finance_categories', '/finance_categories/5', '/budgets'});
    });

    test('the tree: each top-level category followed by its subcategories, '
        'by position then name', () {
      final all = [
        TxCategory.fromJson(categoryJson(id: 2, name: 'Atıştırmalık', parentId: 1)),
        TxCategory.fromJson(categoryJson(id: 3, name: 'Kira', position: 2)),
        TxCategory.fromJson(categoryJson(id: 1, name: 'Market', position: 1)),
        TxCategory.fromJson(categoryJson(id: 4, name: 'Maaş', kind: 'income')),
        TxCategory.fromJson(categoryJson(id: 5, name: 'Ekmek', parentId: 1)),
      ];
      expect(
        [
          for (final entry in categoryTree(all, kind: 'expense'))
            '${entry.child ? '  ' : ''}${entry.category.name}',
        ],
        ['Market', '  Atıştırmalık', '  Ekmek', 'Kira'],
      );
    });
  });

  group('budgets', () {
    test('the list says which categories a new budget can go on', () async {
      api.on('GET /budgets', budgetsJson(budgetable: [10279]));
      final bundle = await repo.fetchBudgets();
      expect(bundle.currency, 'TRY');
      expect(bundle.budgets.single.id, 2);
      expect(bundle.budgets.single.categoryId, 5);
      expect(bundle.budgetableCategoryIds, [10279]);
    });

    test('a create names the category and the limit; an edit only what '
        'changed', () async {
      await repo.createBudget(
          const BudgetInput(categoryId: 5, monthlyLimitCents: 50000));
      await repo.updateBudget(
        BudgetStatus.fromJson(budgetJson()),
        const BudgetInput(categoryId: 5, monthlyLimitCents: 400000),
      );
      expect(api.bodiesOf('POST /budgets').single,
          {'finance_category_id': 5, 'monthly_limit_cents': 50000});
      expect(api.bodiesOf('PATCH /budgets/2').single,
          {'monthly_limit_cents': 400000});
    });

    test('the dashboard\'s budget carries its id, how far it is over and the '
        'bar\'s width', () {
      final over = BudgetStatus.fromJson(budgetJson(limit: 100000, spent: 134000));
      expect(over.id, 2);
      expect(over.overByCents, 34000);
      expect(over.barPercent, 100);
      expect(over.state, 'over');
    });

    test('the pie\'s uncategorized slice is told apart (id 0)', () {
      final slice = PieSlice.fromJson({
        'id': 0,
        'name': 'Kategorisiz',
        'color': '#6E6A64',
        'amount_cents': 625000,
        'breakdown': const [],
        'uncategorized': true,
      });
      expect(slice.uncategorized, isTrue);
      expect(PieSlice.fromJson({'id': 7, 'name': 'Market'}).uncategorized,
          isFalse);
    });
  });

  group('subscriptions', () {
    test('the list: active, paused and the totals per currency', () async {
      api.on('GET /subscriptions', subscriptionsJson(
        inactive: [subscriptionJson(id: 8, name: 'Gazete', active: false)],
      ));
      final bundle = await repo.fetchSubscriptions();
      expect(bundle.active.single.name, 'Netflix');
      expect(bundle.inactive.single.active, isFalse);
      expect(bundle.totals.single.monthlyCents, 22999);
      expect(bundle.all, hasLength(2));
    });

    test('a create leaves the first due date to the server unless one is '
        'picked', () async {
      await repo.createSubscription(const SubscriptionInput(
        name: 'Spotify',
        accountId: 1,
        amountCents: 9999,
        frequency: 'monthly',
        color: '#1DB954',
      ));
      await repo.createSubscription(SubscriptionInput(
        name: 'Kira',
        accountId: 1,
        amountCents: 2500000,
        frequency: 'monthly',
        nextChargeOn: DateTime(2026, 11, 1),
        categoryId: 5,
        color: '#B8860B',
      ));
      expect(api.bodiesOf('POST /subscriptions'), [
        {
          'name': 'Spotify',
          'account_id': 1,
          'amount_cents': 9999,
          'frequency': 'monthly',
          'color': '#1DB954',
        },
        {
          'name': 'Kira',
          'account_id': 1,
          'amount_cents': 2500000,
          'frequency': 'monthly',
          'next_charge_on': '2026-11-01',
          'finance_category_id': 5,
          'color': '#B8860B',
        },
      ]);
    });

    test('an edit sends only what changed; a move to an account in another '
        'currency sends the amount along', () async {
      final before = Subscription.fromJson(subscriptionJson());
      SubscriptionInput input({int accountId = 1, int amount = 22999}) =>
          SubscriptionInput(
            name: 'Netflix',
            accountId: accountId,
            amountCents: amount,
            frequency: 'yearly',
            nextChargeOn: before.nextChargeOn,
            color: '#B8860B',
          );
      await repo.updateSubscription(before, input(), accountCurrency: 'TRY');
      await repo.updateSubscription(before, input(accountId: 3),
          accountCurrency: 'USD');
      expect(api.bodiesOf('PATCH /subscriptions/6'), [
        {'frequency': 'yearly'},
        {'account_id': 3, 'amount_cents': 22999, 'frequency': 'yearly'},
      ]);
    });

    test('pause and resume send the state asked for', () async {
      await repo.setSubscriptionActive(6, active: false);
      await repo.setSubscriptionActive(6, active: true);
      expect(api.bodiesOf('PATCH /subscriptions/6'), [
        {'active': false},
        {'active': true},
      ]);
    });

    test('a payment: the subscription moved on and the expense it recorded',
        () async {
      final charge = await repo.chargeSubscription(6);
      expect(charge.subscription.nextChargeOn, DateTime(2026, 11, 15));
      expect(charge.transaction!.description, 'Netflix');
      await repo.chargeSubscription(6, date: DateTime(2026, 10, 3));
      expect(api.bodiesOf('POST /subscriptions/6/charge'), [
        {'date': '2026-10-03'},
      ]);
    });

    test('a payment refused because it was paused elsewhere refetches the '
        'subscriptions', () async {
      await showEverything(container, api);
      api.on('POST /subscriptions/6/charge', {
        'errors': {'base': ['x']},
        'code': 'not_chargeable',
        'reason': 'inactive',
      }, status: 422);
      await expectLater(
        repo.chargeSubscription(6),
        throwsA(isA<ApiException>()
            .having((e) => e.reason, 'reason', 'inactive')),
      );
      await settle(api);
      expect(api.gets.toSet(), {
        '/subscriptions',
        '/finance/dashboard',
        '/accounts/1',
        '/finance_categories/5',
      });
    });
  });
}
