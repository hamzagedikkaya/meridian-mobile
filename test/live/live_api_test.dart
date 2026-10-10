/// Live conformance: the app's real repository, Dio stack, session and
/// parsing against a running Meridian server — the check the fake API
/// (`test/support/fake_api.dart`) cannot make, since a fake that drifts
/// from the server keeps every unit test green.
///
/// Skipped by default (tag `live`, see dart_test.yaml). It needs the server
/// at [baseUrl] (override with `MERIDIAN_LIVE_URL`) and the throwaway user
/// [email], whose data it creates, edits and deletes:
///
///     flutter test test/live --run-skipped
///
/// Every name carries a per-run suffix, so a rerun never trips over what
/// an earlier (or aborted) run left behind. The steps run in order and
/// share state: each one is a slice of a realistic session.
@Tags(['live'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/profile_actions.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/repository.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/budget.dart';
import 'package:meridian_mobile/models/date_utils.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/finance_category.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/journal.dart';
import 'package:meridian_mobile/models/subscription.dart';
import 'package:meridian_mobile/models/todo.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/fake_stores.dart';
import 'json_shape.dart';

final baseUrl =
    Platform.environment['MERIDIAN_LIVE_URL'] ?? 'http://127.0.0.1:3100';
const email = 'e2e-api@meridian.local';
const password = 'e2e-pass-123';

/// The password while the rotation step runs. An aborted run can leave the
/// account on it; sign-in then puts [password] back.
const rotatedPassword = 'e2e-pass-123-rotated';

/// A per-run suffix of letters only: quick capture reads digits as amounts
/// and times, so the suffix must not look like either.
final run = () {
  var n = DateTime.now().millisecondsSinceEpoch;
  final out = StringBuffer();
  while (n > 0) {
    out.writeCharCode(97 + n % 26);
    n ~/= 26;
  }
  return out.toString();
}();

/// [future] must be refused; the refusal is returned for more checks.
Future<ApiException> refused(
  Future<Object?> future, {
  String? code,
  ApiErrorKind? kind,
}) async {
  try {
    await future;
  } on ApiException catch (e) {
    final why = '$e errors=${e.fieldErrors} details=${e.details} '
        'extra=${e.extra}';
    if (code != null) expect(e.code, code, reason: why);
    if (kind != null) expect(e.kind, kind, reason: why);
    return e;
  }
  fail('expected a refusal${code == null ? '' : ' ($code)'}');
}

/// The `details` error types of [field] in [e].
List<String> detailTypes(ApiException e, String field) =>
    [for (final d in e.details[field] ?? const <ApiErrorDetail>[]) d.error];

DateTime day(DateTime d, [int plus = 0]) =>
    DateTime(d.year, d.month, d.day + plus);

/// [d] one calendar month on, clamped to the month's last day (Rails'
/// `Date#>>`).
DateTime monthOn(DateTime d) {
  final lastDay = DateTime(d.year, d.month + 2, 0).day;
  return DateTime(d.year, d.month + 1, d.day > lastDay ? lastDay : d.day);
}

void main() {
  late SharedPreferences prefs;
  late MemoryTokenStore tokens;
  late ProviderContainer container;

  MeridianRepository repo() => container.read(repositoryProvider);
  SessionController session() => container.read(sessionProvider.notifier);
  ProfileActions profile() => container.read(profileActionsProvider);

  /// A repository that sends [token], whatever the session holds.
  MeridianRepository repoWith(String token) => MeridianRepository(
        buildDio(
          baseUrl: baseUrl,
          tokenReader: () async => token,
          onUnauthorized: () {},
        ),
      );

  // State the steps hand to each other.
  late DateTime today;
  late Account wallet, bank, gold;
  late TxCategory market, snacks, salary, subsCat;
  late Transaction marketTx, snackTx, salaryTx, looseTx, transferTx;
  late BudgetStatus budget;
  late Subscription spotify;
  late Habit water, books, running;
  late Goal trip, reading, waterGoal;
  late TodoList homeList;
  late Todo bill, dentistTodo;
  late Event standup, yoga, holiday, tonight;
  late JournalEntry entry;
  final createdTodoIds = <int>{};
  var passwordRotated = false;

  /// Every JSON answer of the run, by route ([routeTemplate]): what the
  /// last step holds the fake API's canned answers up against.
  final served = <String, JsonShape>{};

  /// Signs in through the app's session. A rate limit is waited out (the
  /// limit is per IP and shared with whatever else talks to this server),
  /// and a password left rotated by an aborted run is put back.
  Future<void> signIn() async {
    for (var attempt = 0;; attempt++) {
      try {
        await session().login(email, password);
        return;
      } on ApiException catch (e) {
        if (e.kind == ApiErrorKind.rateLimited && attempt < 6) {
          await Future<void>.delayed(const Duration(seconds: 60));
          continue;
        }
        if (e.kind == ApiErrorKind.invalidCredentials) {
          await session().login(email, rotatedPassword);
          await profile().changePassword(
            currentPassword: rotatedPassword,
            password: password,
            passwordConfirmation: password,
          );
          return;
        }
        rethrow;
      }
    }
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      PrefKeys.serverUrl: baseUrl,
      PrefKeys.installed: true,
    });
    prefs = await SharedPreferences.getInstance();
    tokens = MemoryTokenStore(token: null);
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(tokens),
        draftStoreProvider.overrideWithValue(MemoryDraftStore()),
      ],
      retry: (_, _) => null,
    );
    container.read(dioProvider).interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          final data = response.data;
          if (data is Map || data is List) {
            final request = response.requestOptions;
            final path = request.uri.path.replaceFirst('/api/v1', '');
            served
                .putIfAbsent(
                    routeTemplate(request.method, path), JsonShape.new)
                .add(data);
          }
          handler.next(response);
        },
      ),
    );
    await signIn();
  });

  tearDownAll(() async {
    // Never leave the account on the rotated password: the next run (and
    // the UI suite) sign in with the real one.
    if (passwordRotated && tokens.token != null) {
      try {
        await profile().changePassword(
          currentPassword: rotatedPassword,
          password: password,
          passwordConfirmation: password,
        );
      } catch (_) {}
    }
    container.dispose();
  });

  // --- Session and options ---------------------------------------------------

  test('login, /me and the profile options', () async {
    final user = container.read(currentUserProvider)!;
    expect(user.email, email);
    expect(user.id, greaterThan(0));
    expect(user.currency, 'TRY');
    expect(user.subunitToUnit, 100);
    expect(user.timezone, 'Istanbul');
    expect(user.timezoneIana, 'Europe/Istanbul');
    expect(user.utcOffset, const Duration(hours: 3));
    expect(user.weeklyReviewDay, inInclusiveRange(0, 6));
    expect(tokens.token, isNotEmpty);
    expect(tokens.origin, baseUrl);

    // GET /me through the session's own probe.
    await session().refreshMe();
    expect(container.read(currentUserProvider)!.id, user.id);

    final options = await repo().fetchMeOptions();
    final codes = {for (final c in options.currencies) c.code: c};
    expect(codes.keys, containsAll(['TRY', 'USD', 'EUR', 'GBP', 'GAU']));
    expect(codes['TRY']!.subunitToUnit, 100);
    expect(codes['TRY']!.symbol, '₺');
    expect(codes['GAU']!.subunitToUnit, 1);
    expect(options.timezones, hasLength(152));
    final istanbul = options.zoneOf(value: 'Istanbul')!;
    expect(istanbul.iana, 'Europe/Istanbul');
    expect(istanbul.utcOffset, const Duration(hours: 3));
    expect(istanbul.name, '(GMT+03:00) Istanbul');
    expect(options.zoneOf(iana: 'Europe/London')!.value, isNotEmpty);

    final currencies = await repo().fetchCurrencies();
    expect(currencies.defaultCurrency, 'TRY');
    expect(currencies.byCode('gau')!.subunitToUnit, 1);

    final home = await repo().fetchHome();
    expect(home.today, isNotNull);
    expect(home.currency, 'TRY');
    expect(home.spending7d, hasLength(7));
    expect(dateOnly(home.spending7d.last.date), dateOnly(home.today!));
    today = day(home.today!);

    // A wrong password is invalid_credentials, and leaves the session be.
    final wrong = await refused(
      session().login(email, 'not-the-password'),
      code: 'invalid_credentials',
      kind: ApiErrorKind.invalidCredentials,
    );
    expect(wrong.status, 401);
    expect(container.read(sessionProvider), isA<SessionLoggedIn>());
  });

  // --- Quick capture without an account ------------------------------------

  test('quick capture: no_account, empty, unreadable amounts', () async {
    // Earlier runs' accounts are archived, so money has nowhere to go —
    // and so this run's first account is the one quick capture uses.
    for (final account in await repo().fetchAccounts()) {
      if (!account.archived) await repo().archiveAccount(account.id);
    }
    await refused(repo().quickCapture('-12,50 kahve'), code: 'no_account');
    await refused(repo().quickCapture('   '), code: 'empty');
    final unreadable = await refused(
      repo().quickCapture('-1.25.0 market'),
      code: 'invalid_amount',
    );
    expect(unreadable.reason, 'unreadable');
    final unknown = await refused(
      repo().quickCapture('alışkanlık: yok $run'),
      code: 'unknown_habit',
    );
    expect(unknown.name, 'yok $run');
  });

  // --- Accounts ---------------------------------------------------------------

  test('accounts: create, edit, archive, unarchive, delete', () async {
    wallet = await repo().createAccount(AccountInput(
      name: 'LT Cüzdan $run',
      accountType: 'cash',
      currency: 'try',
      initialBalanceCents: 150000,
      color: '#D4A574',
    ));
    expect(wallet.name, 'LT Cüzdan $run');
    expect(wallet.accountType, 'cash');
    expect(wallet.currency, 'TRY');
    expect(wallet.subunitToUnit, 100);
    expect(wallet.color.toUpperCase(), '#D4A574');
    expect(wallet.initialBalanceCents, 150000);
    expect(wallet.balanceCents, 150000);
    expect(wallet.archived, isFalse);
    expect(wallet.archivedAt, isNull);

    bank = await repo().createAccount(AccountInput(
      name: 'LT Banka $run',
      accountType: 'bank',
      initialBalanceCents: 0,
      color: '#4A6FA5',
    ));
    expect(bank.currency, 'TRY', reason: "no currency: the user's");
    gold = await repo().createAccount(AccountInput(
      name: 'LT Altın $run',
      accountType: 'savings',
      currency: 'GAU',
      initialBalanceCents: 12,
      color: '#B8860B',
    ));
    expect(gold.currency, 'GAU');
    expect(gold.subunitToUnit, 1);
    expect(gold.balanceCents, 12);

    // A fresh account is deletable and its currency can still change; a
    // currency change carries the opening balance along.
    final spare = await repo().createAccount(AccountInput(
      name: 'LT Yedek $run',
      accountType: 'credit_card',
      currency: 'USD',
      initialBalanceCents: -235000,
      color: '#B85450',
    ));
    expect(spare.initialBalanceCents, -235000);
    final spareDetail = await repo().fetchAccount(spare.id);
    expect(spareDetail.account.name, spare.name);
    expect(spareDetail.deletable, isTrue);
    expect(spareDetail.currencyEditable, isTrue);
    expect(spareDetail.transactionsCount, 0);
    expect(spareDetail.incomingTransfersCount, 0);
    expect(spareDetail.subscriptionsCount, 0);
    expect(spareDetail.linkedGoalsCount, 0);
    final toEur = AccountInput(
      name: 'LT Yedek kart $run',
      accountType: 'credit_card',
      currency: 'EUR',
      initialBalanceCents: -1000,
      color: '#B85450',
    );
    expect(toEur.changesFrom(spare).keys,
        unorderedEquals(['name', 'currency', 'initial_balance_cents']));
    final euro = await repo().updateAccount(spare, toEur);
    expect(euro.name, 'LT Yedek kart $run');
    expect(euro.currency, 'EUR');
    expect(euro.initialBalanceCents, -1000);
    expect(euro.accountType, 'credit_card');

    // Archive is idempotent and keeps its first archived_at.
    final archived = await repo().archiveAccount(euro.id);
    expect(archived.archived, isTrue);
    expect(archived.archivedAt, isNotNull);
    final again = await repo().archiveAccount(euro.id);
    expect(again.archivedAt, archived.archivedAt);
    final listed = await repo().fetchAccounts();
    final ids = [for (final a in listed) a.id];
    expect(ids, containsAll([wallet.id, bank.id, gold.id, euro.id]));
    expect(listed.firstWhere((a) => a.id == euro.id).archived, isTrue);
    // Active ones first, then the archived ones.
    final firstArchived = listed.indexWhere((a) => a.archived);
    expect(listed.skip(firstArchived).every((a) => a.archived), isTrue);
    final unarchived = await repo().unarchiveAccount(euro.id);
    expect(unarchived.archived, isFalse);
    expect(unarchived.archivedAt, isNull);

    await repo().deleteAccount(euro.id);
    await refused(repo().fetchAccount(euro.id), kind: ApiErrorKind.notFound);
    await refused(repo().deleteAccount(euro.id), code: 'not_found');

    final invalid = await refused(
      repo().createAccount(const AccountInput(
        name: '',
        accountType: 'wallet',
        currency: 'XYZ',
        color: 'kırmızı',
      )),
      code: 'validation_failed',
    );
    expect(detailTypes(invalid, 'name'), contains('blank'));
    expect(detailTypes(invalid, 'account_type'), contains('inclusion'));
    expect(detailTypes(invalid, 'currency'), contains('inclusion'));
    expect(detailTypes(invalid, 'color'), contains('invalid'));
  });

  // --- Categories -------------------------------------------------------------

  test('categories: hierarchy rules', () async {
    market = await repo().createCategory(CategoryInput(
      name: 'LT Market $run',
      kind: 'expense',
      color: '#D4915A',
    ));
    expect(market.kind, 'expense');
    expect(market.parentId, isNull);
    expect(market.color.toUpperCase(), '#D4915A');
    snacks = await repo().createCategory(CategoryInput(
      name: 'LT Atıştırmalık $run',
      kind: 'expense',
      parentId: market.id,
      color: '#C9A227',
    ));
    expect(snacks.parentId, market.id);
    salary = await repo().createCategory(CategoryInput(
      name: 'LT Maaş $run',
      kind: 'income',
      color: '#6B8E5A',
    ));
    expect(salary.kind, 'income');
    subsCat = await repo().createCategory(CategoryInput(
      name: 'LT Abonelikler $run',
      kind: 'expense',
      color: '#B8860B',
    ));

    final all = await repo().fetchCategories();
    expect([for (final c in all) c.id],
        containsAll([market.id, snacks.id, salary.id, subsCat.id]));
    final tree = categoryTree(all, kind: 'expense');
    final marketAt = tree.indexWhere((n) => n.category.id == market.id);
    expect(tree[marketAt + 1].category.id, snacks.id);
    expect(tree[marketAt + 1].child, isTrue);

    // Two levels only, one kind per tree, names unique under a parent.
    final deep = await refused(
      repo().createCategory(CategoryInput(
        name: 'LT Derin $run',
        kind: 'expense',
        parentId: snacks.id,
        color: '#A09B8E',
      )),
      code: 'validation_failed',
    );
    expect(detailTypes(deep, 'parent_id'), contains('must_be_root'));
    final mixed = await refused(
      repo().createCategory(CategoryInput(
        name: 'LT Karışık $run',
        kind: 'expense',
        parentId: salary.id,
        color: '#A09B8E',
      )),
      code: 'validation_failed',
    );
    expect(detailTypes(mixed, 'parent_id'), contains('must_match_kind'));
    final taken = await refused(
      repo().createCategory(CategoryInput(
        name: 'lt market $run',
        kind: 'expense',
        color: '#A09B8E',
      )),
      code: 'validation_failed',
    );
    expect(detailTypes(taken, 'name'), contains('taken'));
    await refused(
      repo().createCategory(CategoryInput(
        name: 'LT Yetim $run',
        kind: 'expense',
        parentId: 999999999,
        color: '#A09B8E',
      )),
      kind: ApiErrorKind.notFound,
    );

    // A category with children cannot become one, nor change its kind.
    final nested = await refused(
      repo().updateCategory(
        market,
        CategoryInput(
          name: market.name,
          kind: 'expense',
          parentId: subsCat.id,
          color: market.color,
        ),
      ),
      code: 'validation_failed',
    );
    expect(detailTypes(nested, 'parent_id'), contains('cannot_have_children'));
    await refused(
      repo().updateCategory(
        market,
        CategoryInput(name: market.name, kind: 'income', color: market.color),
      ),
      code: 'kind_locked',
    );
    final self = await refused(
      repo().updateCategory(
        subsCat,
        CategoryInput(
          name: subsCat.name,
          kind: 'expense',
          parentId: subsCat.id,
          color: subsCat.color,
        ),
      ),
      code: 'validation_failed',
    );
    expect(detailTypes(self, 'parent_id'), contains('cannot_be_self'));

    final rename = CategoryInput(
      name: 'LT Market & Gıda $run',
      kind: 'expense',
      color: '#D4915A',
    );
    expect(rename.changesFrom(market).keys, ['name']);
    market = await repo().updateCategory(market, rename);
    expect(market.name, 'LT Market & Gıda $run');
    expect(market.parentId, isNull);

    final usage = await repo().fetchCategory(market.id);
    expect(usage.category.id, market.id);
    expect(usage.childrenCount, 1);
    expect(usage.transactionsCount, 0);
    expect(usage.budgetId, isNull);
    expect(usage.kindEditable, isFalse);
    final leaf = await repo().fetchCategory(subsCat.id);
    expect(leaf.unused, isTrue);
    expect(leaf.kindEditable, isTrue);
  });

  // --- Transactions -----------------------------------------------------------

  test('transactions: categorized, uncategorized, transfers, edit, delete',
      () async {
    marketTx = await repo().createTransaction(TransactionInput(
      kind: 'expense',
      amountCents: 12550,
      date: today,
      description: 'Market',
      note: 'haftalık',
      accountId: wallet.id,
      financeCategoryId: market.id,
    ));
    expect(marketTx.kind, 'expense');
    expect(marketTx.amountCents, 12550);
    expect(dateOnly(marketTx.date), today);
    expect(marketTx.description, 'Market');
    expect(marketTx.note, 'haftalık');
    expect(marketTx.account.id, wallet.id);
    expect(marketTx.account.currency, 'TRY');
    expect(marketTx.account.subunitToUnit, 100);
    expect(marketTx.category!.id, market.id);
    expect(marketTx.category!.kind, 'expense');
    expect(marketTx.relatedAccount, isNull);

    snackTx = await repo().createTransaction(TransactionInput(
      kind: 'expense',
      amountCents: 8550,
      date: today,
      description: 'Cips',
      accountId: wallet.id,
      financeCategoryId: snacks.id,
    ));
    expect(snackTx.category!.parentId, market.id);
    salaryTx = await repo().createTransaction(TransactionInput(
      kind: 'income',
      amountCents: 5000000,
      date: today,
      description: 'Maaş',
      accountId: bank.id,
      financeCategoryId: salary.id,
    ));
    expect(salaryTx.category!.kind, 'income');
    looseTx = await repo().createTransaction(TransactionInput(
      kind: 'expense',
      amountCents: 25000,
      date: today,
      description: 'Kategorisiz $run',
      accountId: wallet.id,
    ));
    expect(looseTx.category, isNull);
    transferTx = await repo().createTransaction(TransactionInput(
      kind: 'transfer',
      amountCents: 100000,
      date: today,
      description: 'Nakit çekim',
      accountId: bank.id,
      relatedAccountId: wallet.id,
    ));
    expect(transferTx.kind, 'transfer');
    expect(transferTx.account.id, bank.id);
    expect(transferTx.relatedAccount!.id, wallet.id);
    expect(transferTx.relatedAccount!.name, wallet.name);
    expect(transferTx.category, isNull);

    // Transfer rules.
    final same = await refused(
      repo().createTransaction(TransactionInput(
        kind: 'transfer',
        amountCents: 100,
        date: today,
        accountId: wallet.id,
        relatedAccountId: wallet.id,
      )),
      code: 'validation_failed',
    );
    expect(detailTypes(same, 'related_account_id'), contains('same_account'));
    final mismatch = await refused(
      repo().createTransaction(TransactionInput(
        kind: 'transfer',
        amountCents: 100,
        date: today,
        accountId: wallet.id,
        relatedAccountId: gold.id,
      )),
      code: 'validation_failed',
    );
    expect(detailTypes(mismatch, 'related_account_id'),
        contains('currency_mismatch'));
    final wrongKind = await refused(
      repo().createTransaction(TransactionInput(
        kind: 'expense',
        amountCents: 100,
        date: today,
        accountId: wallet.id,
        financeCategoryId: salary.id,
      )),
      code: 'validation_failed',
    );
    expect(detailTypes(wrongKind, 'finance_category'), contains('kind_mismatch'));
    await refused(
      repo().createTransaction(TransactionInput(
        kind: 'expense',
        amountCents: 100,
        date: today,
        accountId: 999999999,
      )),
      kind: ApiErrorKind.notFound,
    );

    // Balances: opening + income − expenses ± transfers.
    final accounts = {for (final a in await repo().fetchAccounts()) a.id: a};
    expect(accounts[wallet.id]!.balanceCents,
        150000 - 12550 - 8550 - 25000 + 100000);
    expect(accounts[bank.id]!.balanceCents, 5000000 - 100000);

    // The wallet's history with the transfer into it.
    final history = await repo().fetchTransactions(
      accountId: wallet.id,
      includeIncomingTransfers: true,
    );
    expect([for (final t in history.items) t.id],
        containsAll([marketTx.id, snackTx.id, looseTx.id, transferTx.id]));
    expect(history.meta.totalCount, 4);
    expect(history.meta.page, 1);
    expect(history.meta.pageLimit, 50);
    expect(history.meta.filteredExpenseCents, 12550 + 8550 + 25000);
    expect(history.meta.filteredIncomeCents, 0);
    final own = await repo().fetchTransactions(accountId: wallet.id);
    expect([for (final t in own.items) t.id], isNot(contains(transferTx.id)));

    // A root category matches its subcategories too.
    final byRoot = await repo().fetchTransactions(categoryId: market.id);
    expect([for (final t in byRoot.items) t.id],
        unorderedEquals([marketTx.id, snackTx.id]));
    final bySub = await repo().fetchTransactions(categoryId: snacks.id);
    expect([for (final t in bySub.items) t.id], [snackTx.id]);
    final loose = await repo().fetchTransactions(
      kind: 'expense',
      uncategorized: true,
      from: today,
      to: today,
    );
    final looseIds = [for (final t in loose.items) t.id];
    expect(looseIds, contains(looseTx.id));
    expect(looseIds, isNot(contains(marketTx.id)));
    expect(loose.items.every((t) => t.category == null), isTrue);
    final incomes = await repo().fetchTransactions(kind: 'income');
    expect(incomes.items.every((t) => t.kind == 'income'), isTrue);

    final detail = await repo().fetchTransaction(marketTx.id);
    expect(detail.transaction.id, marketTx.id);
    expect(detail.transaction.note, 'haftalık');
    expect(detail.parentTransactionId, isNull);
    expect(detail.linked, isNull);
    expect(detail.deletesLinked, isFalse);

    // Edit: only what changed goes; a cleared note becomes null.
    final edit = TransactionInput(
      kind: 'expense',
      amountCents: 13000,
      date: today,
      description: 'Market',
      accountId: wallet.id,
      financeCategoryId: market.id,
    );
    expect(edit.changesFrom(marketTx).keys,
        unorderedEquals(['amount_cents', 'note']));
    marketTx = await repo().updateTransaction(marketTx, edit);
    expect(marketTx.amountCents, 13000);
    expect(marketTx.note, isNull);
    expect(marketTx.category!.id, market.id);
    expect(marketTx.description, 'Market');

    // Taking the category off makes it uncategorized; putting it back too.
    final bare = TransactionInput(
      kind: 'expense',
      amountCents: 8550,
      date: today,
      description: 'Cips',
      accountId: wallet.id,
    );
    expect(bare.changesFrom(snackTx), {'finance_category_id': null});
    final uncategorized = await repo().updateTransaction(snackTx, bare);
    expect(uncategorized.category, isNull);
    snackTx = await repo().updateTransaction(
      uncategorized,
      TransactionInput(
        kind: 'expense',
        amountCents: 8550,
        date: today,
        description: 'Cips',
        accountId: wallet.id,
        financeCategoryId: snacks.id,
      ),
    );
    expect(snackTx.category!.id, snacks.id);

    // Delete.
    final doomed = await repo().createTransaction(TransactionInput(
      kind: 'expense',
      amountCents: 100,
      date: today,
      accountId: wallet.id,
    ));
    await repo().deleteTransaction(doomed.id);
    await refused(repo().fetchTransaction(doomed.id),
        kind: ApiErrorKind.notFound);
    await refused(repo().deleteTransaction(doomed.id), code: 'not_found');

    // An account with transactions can only be archived; its currency is
    // locked.
    final walletDetail = await repo().fetchAccount(wallet.id);
    expect(walletDetail.transactionsCount, 3);
    expect(walletDetail.incomingTransfersCount, 1);
    expect(walletDetail.deletable, isFalse);
    expect(walletDetail.currencyEditable, isFalse);
    final blocked = await refused(repo().deleteAccount(wallet.id),
        code: 'has_transactions');
    expect(blocked.number('transactions_count'), 3);
    expect(blocked.number('incoming_transfers_count'), 1);
    await refused(
      repo().updateAccount(
        wallet,
        AccountInput(
          name: wallet.name,
          accountType: wallet.accountType,
          currency: 'USD',
          initialBalanceCents: wallet.initialBalanceCents,
          color: wallet.color,
        ),
      ),
      code: 'currency_locked',
    );
  });

  // --- Budgets ----------------------------------------------------------------

  test('budgets: create, rules, edit', () async {
    final before = await repo().fetchBudgets();
    expect(before.budgetableCategoryIds, containsAll([market.id, subsCat.id]));
    expect(before.budgetableCategoryIds, isNot(contains(snacks.id)));
    expect(before.budgetableCategoryIds, isNot(contains(salary.id)));
    expect(before.currency, 'TRY');
    expect(before.asOf, today);

    budget = await repo().createBudget(
        BudgetInput(categoryId: market.id, monthlyLimitCents: 300000));
    expect(budget.id, greaterThan(0));
    expect(budget.categoryId, market.id);
    expect(budget.categoryName, market.name);
    expect(budget.color.toUpperCase(), '#D4915A');
    expect(budget.customColor, isNull);
    expect(budget.limitCents, 300000);
    // A subcategory's spend counts toward its root's budget.
    expect(budget.spentCents, 13000 + 8550);
    expect(budget.remainingCents, 300000 - 21550);
    expect(budget.overByCents, 0);
    expect(budget.percentUsed, 7);
    expect(budget.barPercent, 7);
    expect(budget.state, isIn(['under', 'warning']));

    final sub = await refused(
      repo().createBudget(
          BudgetInput(categoryId: snacks.id, monthlyLimitCents: 1000)),
      code: 'validation_failed',
    );
    expect(detailTypes(sub, 'finance_category_id'), contains('must_be_root'));
    final income = await refused(
      repo().createBudget(
          BudgetInput(categoryId: salary.id, monthlyLimitCents: 1000)),
      code: 'validation_failed',
    );
    expect(detailTypes(income, 'finance_category_id'),
        contains('must_be_expense'));
    final twice = await refused(
      repo().createBudget(
          BudgetInput(categoryId: market.id, monthlyLimitCents: 1000)),
      code: 'validation_failed',
    );
    expect(detailTypes(twice, 'finance_category_id'), contains('taken'));
    final zero = await refused(
      repo().createBudget(
          BudgetInput(categoryId: subsCat.id, monthlyLimitCents: 0)),
      code: 'validation_failed',
    );
    expect(detailTypes(zero, 'monthly_limit_cents'), contains('greater_than'));

    final raise = BudgetInput(categoryId: market.id, monthlyLimitCents: 10000);
    expect(raise.changesFrom(budget), {'monthly_limit_cents': 10000});
    budget = await repo().updateBudget(budget, raise);
    expect(budget.limitCents, 10000);
    expect(budget.state, 'over');
    expect(budget.overByCents, 21550 - 10000);
    expect(budget.remainingCents, 10000 - 21550);
    expect(budget.percentUsed, 216);
    expect(budget.barPercent, 100);

    final after = await repo().fetchBudgets();
    expect([for (final b in after.budgets) b.id], contains(budget.id));
    expect(after.budgetableCategoryIds, isNot(contains(market.id)));
    final usage = await repo().fetchCategory(market.id);
    expect(usage.budgetId, budget.id);
    expect(usage.budgetsCount, 1);
    expect(usage.transactionsCount, 2);
  });

  // --- Subscriptions ----------------------------------------------------------

  test('subscriptions: create, edit, charge, pause, delete', () async {
    spotify = await repo().createSubscription(SubscriptionInput(
      name: 'LT Spotify $run',
      accountId: wallet.id,
      amountCents: 9999,
      frequency: 'monthly',
      categoryId: subsCat.id,
      vendor: 'Spotify AB',
      color: '#1DB954',
    ));
    expect(spotify.name, 'LT Spotify $run');
    expect(spotify.vendor, 'Spotify AB');
    expect(spotify.amountCents, 9999);
    expect(spotify.frequency, 'monthly');
    expect(spotify.active, isTrue);
    expect(spotify.startDate, today);
    // Without a date the first charge is a period after today.
    expect(spotify.nextChargeOn, monthOn(today));
    expect(spotify.endDate, isNull);
    expect(spotify.monthlyAmountCents, 9999);
    expect(spotify.yearlyAmountCents, 9999 * 12);
    expect(spotify.account.id, wallet.id);
    expect(spotify.category!.id, subsCat.id);
    expect(spotify.color.toUpperCase(), '#1DB954');

    final yearly = await repo().createSubscription(SubscriptionInput(
      name: 'LT Gazete $run',
      accountId: bank.id,
      amountCents: 15000,
      frequency: 'yearly',
      nextChargeOn: day(today, 90),
      color: '#B8860B',
    ));
    expect(yearly.nextChargeOn, day(today, 90));
    expect(yearly.monthlyAmountCents, 15000 ~/ 12);
    expect(yearly.category, isNull);

    final list = await repo().fetchSubscriptions();
    expect([for (final s in list.active) s.id],
        containsAll([spotify.id, yearly.id]));
    final tryTotal = list.totals.firstWhere((t) => t.currency == 'TRY');
    expect(tryTotal.subunitToUnit, 100);
    expect(tryTotal.monthlyCents, greaterThanOrEqualTo(9999 + 1250));

    // Due today, with a note: the charge is recorded on its due date.
    final due = SubscriptionInput(
      name: spotify.name,
      accountId: wallet.id,
      amountCents: 9999,
      frequency: 'monthly',
      nextChargeOn: today,
      categoryId: subsCat.id,
      vendor: 'Spotify AB',
      note: 'aile planı',
      color: '#1DB954',
    );
    expect(due.changesFrom(spotify, accountCurrency: 'TRY').keys,
        unorderedEquals(['next_charge_on', 'note']));
    spotify = await repo().updateSubscription(spotify, due,
        accountCurrency: 'TRY');
    expect(spotify.nextChargeOn, today);
    expect(spotify.note, 'aile planı');
    expect(spotify.vendor, 'Spotify AB');

    final charge = await repo().chargeSubscription(spotify.id);
    expect(charge.subscription.id, spotify.id);
    expect(charge.subscription.nextChargeOn, monthOn(today));
    final payment = charge.transaction!;
    expect(payment.kind, 'expense');
    expect(payment.amountCents, 9999);
    expect(dateOnly(payment.date), today);
    expect(payment.description, spotify.name);
    expect(payment.account.id, wallet.id);
    expect(payment.category!.id, subsCat.id);
    spotify = charge.subscription;

    // Pause: never due, cannot be charged.
    final paused = await repo().setSubscriptionActive(spotify.id, active: false);
    expect(paused.active, isFalse);
    final listed = await repo().fetchSubscriptions();
    expect([for (final s in listed.inactive) s.id], contains(spotify.id));
    expect([for (final s in listed.active) s.id], isNot(contains(spotify.id)));
    final inactive = await refused(repo().chargeSubscription(spotify.id),
        code: 'not_chargeable');
    expect(inactive.reason, 'inactive');
    spotify = await repo().setSubscriptionActive(spotify.id, active: true);
    expect(spotify.active, isTrue);

    // Moving it to an account in another currency carries the amount.
    final toGold = SubscriptionInput(
      name: yearly.name,
      accountId: gold.id,
      amountCents: 1,
      frequency: 'yearly',
      nextChargeOn: day(today, 90),
      color: '#B8860B',
    );
    expect(toGold.changesFrom(yearly, accountCurrency: 'GAU').keys,
        unorderedEquals(['account_id', 'amount_cents']));
    final moved = await repo().updateSubscription(yearly, toGold,
        accountCurrency: 'GAU');
    expect(moved.account.id, gold.id);
    expect(moved.account.currency, 'GAU');
    expect(moved.amountCents, 1);

    // Deleting it keeps the payments.
    await repo().deleteSubscription(moved.id);
    final rest = await repo().fetchSubscriptions();
    expect([for (final s in rest.all) s.id], isNot(contains(moved.id)));
    expect((await repo().fetchTransaction(payment.id)).transaction.id,
        payment.id);
  });

  // --- Dashboard --------------------------------------------------------------

  test('finance dashboard and the uncategorized bucket', () async {
    final dash = await repo().fetchFinanceDashboard();
    expect(dash.currency, 'TRY');
    expect(dash.subunitToUnit, 100);
    expect(dash.month.expenseCents, greaterThanOrEqualTo(13000 + 8550 + 25000));
    expect(dash.month.netCents,
        dash.month.incomeCents - dash.month.expenseCents);
    expect(dash.sixMonthSeries.labels, hasLength(6));
    expect(dash.sixMonthSeries.labels.last,
        '${today.year}-${today.month.toString().padLeft(2, '0')}');
    expect(dash.sixMonthSeries.expenseCents.last, dash.month.expenseCents);

    // WP-15: totals per currency (the user's first) and the cumulative
    // series behind Finance's pace line (contract §13.3).
    final totals = dash.totalsByCurrency;
    expect(totals, isNotNull);
    expect(totals!.first.currency, dash.currency);
    expect(totals.first.month.expenseCents, dash.month.expenseCents);
    final spend = dash.spendCumulativeCents!;
    expect(spend, hasLength(today.day));
    expect(spend.last, dash.month.expenseCents);
    final reference = dash.referenceCumulativeCents!;
    expect(reference, hasLength(DateTime(today.year, today.month, 0).day));
    expect(reference.last, dash.sixMonthSeries.expenseCents[4]);

    // The pie covers the whole month, uncategorized spending included.
    final pieTotal = dash.pie.fold<int>(0, (sum, s) => sum + s.amountCents);
    expect(pieTotal, dash.month.expenseCents);
    final loose = dash.pie.singleWhere((s) => s.uncategorized);
    expect(loose.id, 0);
    expect(loose.name, 'Kategorisiz');
    expect(loose.breakdown, isEmpty);
    final marketSlice = dash.pie.firstWhere((s) => s.id == market.id);
    expect(marketSlice.uncategorized, isFalse);
    expect(marketSlice.amountCents, 13000 + 8550);
    expect(marketSlice.breakdown, hasLength(2));
    final rootPart = marketSlice.breakdown.firstWhere((b) => b.isRoot);
    expect(rootPart.id, market.id);
    expect(rootPart.amountCents, 13000);
    final childPart = marketSlice.breakdown.firstWhere((b) => !b.isRoot);
    expect(childPart.id, snacks.id);
    expect(childPart.amountCents, 8550);
    final subsSlice = dash.pie.firstWhere((s) => s.id == subsCat.id);
    expect(subsSlice.amountCents, 9999);

    // Drilling into the uncategorized slice lists exactly its spending.
    final first = DateTime(today.year, today.month);
    final last = DateTime(today.year, today.month + 1, 0);
    final bucket = await repo().fetchTransactions(
      kind: 'expense',
      uncategorized: true,
      from: first,
      to: last,
    );
    expect(bucket.meta.filteredExpenseCents, loose.amountCents);
    expect([for (final t in bucket.items) t.id], contains(looseTx.id));

    final dashBudget =
        dash.budgets.firstWhere((BudgetStatus b) => b.id == budget.id);
    expect(dashBudget.categoryId, market.id);
    expect(dashBudget.state, 'over');
    expect(dashBudget.spentCents, 21550);
    expect(dash.budgets.first.state, 'over', reason: 'over budgets first');

    // Upcoming: due within 30 days (a month on is 31 days in some months).
    final upcoming = dash.upcomingSubscriptions
        .where((SubscriptionItem s) => s.id == spotify.id);
    final dueIn = monthOn(today).difference(today).inDays;
    expect(upcoming, hasLength(dueIn <= 30 ? 1 : 0));
    for (final item in upcoming) {
      expect(item.nextChargeOn, monthOn(today));
      expect(item.account.id, wallet.id);
      expect(item.amountCents, 9999);
    }
    spotify = await repo().updateSubscription(
      spotify,
      SubscriptionInput(
        name: spotify.name,
        accountId: wallet.id,
        amountCents: 9999,
        frequency: 'monthly',
        nextChargeOn: day(today, 3),
        categoryId: subsCat.id,
        vendor: spotify.vendor,
        note: spotify.note,
        color: spotify.color,
      ),
      accountCurrency: 'TRY',
    );
    final soon = (await repo().fetchFinanceDashboard())
        .upcomingSubscriptions
        .singleWhere((SubscriptionItem s) => s.id == spotify.id);
    expect(soon.nextChargeOn, day(today, 3));
    expect(soon.frequency, 'monthly');
    expect(soon.account.id, wallet.id);
    expect(soon.account.currency, 'TRY');
    expect(dash.recentTransactions, isNotEmpty);
    expect(dash.recentTransactions.length, lessThanOrEqualTo(8));
  });

  // --- Habits -----------------------------------------------------------------

  test('habits: create, edit, log, archive, unarchive', () async {
    water = await repo().createHabit(HabitInput(
      name: 'LT Su $run',
      frequency: 'daily',
      targetCount: 3,
      color: '#4A90D9',
      description: 'Günde 3 bardak',
    ));
    expect(water.name, 'LT Su $run');
    expect(water.description, 'Günde 3 bardak');
    expect(water.frequency, 'daily');
    expect(water.targetCount, 3);
    expect(water.archived, isFalse);
    expect(water.archivedAt, isNull);
    expect(water.goalId, isNull);
    expect(dateOnly(water.today.date), today);
    expect(water.today.count, 0);
    expect(water.today.completed, isFalse);
    expect(water.startDate, today);
    // The chain and the rate start on the start date: a new habit has no
    // "missed" days from before it existed.
    expect(water.chain, hasLength(1));
    expect(dateOnly(water.chain.last.date), today);
    expect(water.chain.last.status, ChainStatus.todayPending);
    expect(water.completionRate30d, 0);
    expect(water.period, isNull);

    books = await repo().createHabit(HabitInput(
      name: 'LT Kitap $run',
      frequency: 'weekly',
      targetCount: 3,
      color: '#6B8E5A',
    ));
    expect(books.frequency, 'weekly');
    expect(books.period, isNotNull);
    expect(books.period!.completedCount, 0);
    running = await repo().createHabit(HabitInput(
      name: 'LT Koşu $run',
      frequency: 'daily',
      targetCount: 3,
      color: '#B85450',
    ));

    final bad = await refused(
      repo().createHabit(const HabitInput(
        name: '',
        frequency: 'hourly',
        targetCount: 0,
        color: 'mavi',
      )),
      code: 'validation_failed',
    );
    expect(detailTypes(bad, 'name'), contains('blank'));
    expect(detailTypes(bad, 'frequency'), contains('inclusion'));
    expect(detailTypes(bad, 'target_count'), contains('greater_than'));
    expect(detailTypes(bad, 'color'), contains('invalid'));

    // Edit: only what changed.
    final edit = HabitInput(
      name: 'LT Su iç $run',
      frequency: 'daily',
      targetCount: 4,
      color: '#4A90D9',
      description: 'Günde 4 bardak',
    );
    expect(edit.changesFrom(water).keys,
        unorderedEquals(['name', 'target_count', 'description']));
    water = await repo().updateHabit(water, edit);
    expect(water.name, 'LT Su iç $run');
    expect(water.targetCount, 4);
    expect(water.description, 'Günde 4 bardak');
    expect(water.color.toUpperCase(), '#4A90D9');

    // Today's count, set (not flipped); a count above the target clamps.
    final two = await repo().setHabitLog(water.id, today, count: 2);
    expect(two.log!.count, 2);
    expect(two.log!.completed, isFalse);
    expect(dateOnly(two.log!.date), today);
    expect(two.habit.today.count, 2);
    expect(two.habit.chain.last.status, ChainStatus.partial);
    expect(two.habit.chain.last.completed, 2);
    expect(two.habit.chain.last.possible, 4);
    expect(two.totalActive, greaterThanOrEqualTo(3));
    final twice = await repo().setHabitLog(water.id, today, count: 2);
    expect(twice.habit.today.count, 2, reason: 'idempotent');
    final full = await repo().setHabitLog(water.id, today, count: 9);
    expect(full.log!.count, 4);
    expect(full.log!.completed, isTrue);
    expect(full.habit.today.completed, isTrue);
    expect(full.habit.chain.last.status, ChainStatus.completed);
    expect(full.habit.currentStreak, 1);
    expect(full.habit.chain, hasLength(1));
    expect(full.habit.completionRate30d, 100,
        reason: 'done on its only day, not 1 of 30');
    expect(water.logFor(9), (completed: true, count: 4));

    // A weekly habit's day is done or not.
    final week = await repo().setHabitLog(books.id, today, count: 1);
    expect(week.log!.count, 3);
    expect(week.log!.completed, isTrue);
    expect(week.habit.period!.completedCount, 1);
    expect(books.logFor(1), (completed: true, count: 3));

    // Days outside start_date … today are refused.
    final early = await refused(
      repo().setHabitLog(water.id, day(today, -1), count: 1),
      code: 'before_habit_start',
    );
    expect(early.habitStart, today);
    await refused(repo().setHabitLog(water.id, day(today, 1), count: 1),
        code: 'future_date');

    // A past day, on a habit kept across runs: once it is older than
    // today, yesterday can be set and shows in its chain.
    final kept = 'LT Kalıcı alışkanlık';
    var keeper = (await repo().fetchHabits())
        .habits
        .where((h) => h.name == kept)
        .firstOrNull;
    keeper ??= await repo().createHabit(const HabitInput(
      name: 'LT Kalıcı alışkanlık',
      frequency: 'daily',
      targetCount: 2,
      color: '#7A5C9E',
    ));
    final yesterday = day(today, -1);
    if (keeper.canLog(yesterday)) {
      final past = await repo().setHabitLog(keeper.id, yesterday, count: 1);
      expect(dateOnly(past.log!.date), yesterday);
      expect(past.log!.count, 1);
      final cell =
          past.habit.chain.firstWhere((c) => dateOnly(c.date) == yesterday);
      expect(cell.status, ChainStatus.partial);
      expect(cell.completed, 1);
      expect(dateOnly(past.habit.today.date), today,
          reason: "today stays the server's today");
      await repo().setHabitLog(keeper.id, yesterday, count: 0);
    } else {
      expect(keeper.startDate, today);
      final refusal = await refused(
        repo().setHabitLog(keeper.id, yesterday, count: 1),
        code: 'before_habit_start',
      );
      expect(refusal.habitStart, keeper.startDate);
    }

    final list = await repo().fetchHabits();
    final ids = [for (final h in list.habits) h.id];
    expect(ids, containsAll([water.id, books.id, running.id]));
    expect(list.totalActive, list.habits.length);
    expect(list.completedToday,
        list.habits.where((h) => h.today.completed).length);
    expect(dateOnly(list.perfectDay.chain.last.date), today);

    final detail = await repo().fetchHabit(water.id, days: 30);
    expect([for (final c in detail.chain) dateOnly(c.date)], [today],
        reason: 'the detail chain starts on the start date too');
    expect(detail.completionRate30d, 100);
    expect(detail.loggedDaysCount, 1);
    expect(detail.completedDaysCount, 1);
    expect(detail.trackedByGoals, isEmpty);

    // Archive: frozen, off the list; idempotent.
    final archived = await repo().archiveHabit(books.id);
    expect(archived.archived, isTrue);
    expect(archived.archivedAt, isNotNull);
    expect((await repo().archiveHabit(books.id)).archivedAt,
        archived.archivedAt);
    await refused(repo().setHabitLog(books.id, today, count: 0),
        code: 'habit_archived');
    expect([for (final h in (await repo().fetchHabits()).habits) h.id],
        isNot(contains(books.id)));
    final archivedList = await repo().fetchArchivedHabits();
    expect([for (final h in archivedList) h.id], contains(books.id));
    expect(archivedList.every((h) => h.archived), isTrue);
    final back = await repo().unarchiveHabit(books.id);
    expect(back.archived, isFalse);
    expect(back.archivedAt, isNull);
    expect(dateOnly(back.chain.last.date), today);
    books = back;
  });

  // --- Goals ------------------------------------------------------------------

  test('goals: create, edit, link, abandon, reopen', () async {
    final bankBalance = (await repo().fetchAccount(bank.id)).account
        .balanceCents;
    trip = await repo().createGoal(GoalInput(
      name: 'LT Tatil $run',
      targetType: 'financial',
      color: '#B8860B',
      targetValue: 100000,
      related: 'Account-${bank.id}',
      deadline: day(today, 240),
    ));
    expect(trip.targetType, 'financial');
    expect(trip.status, 'active');
    expect(trip.progressSource, 'account');
    expect(trip.unit, 'TRY', reason: "a financial goal's unit: the currency");
    expect(trip.targetValue, 100000);
    expect(trip.currentValue, bankBalance / 100);
    expect(trip.progressPercent, 49.0);
    expect(trip.deadline, day(today, 240));
    expect(trip.daysRemaining, 240);
    expect(trip.deadlineBadge!.state, 'far');
    expect(trip.deadlineBadge!.days, 240);
    expect(trip.related!.type, 'Account');
    expect(trip.related!.id, bank.id);
    expect(trip.related!.balanceCents, bankBalance);
    expect(trip.related!.currency, 'TRY');
    expect(trip.relatedRef, 'Account-${bank.id}');
    expect(trip.isManual, isFalse);
    await refused(repo().goalUpdateProgress(trip.id, delta: 1),
        code: 'progress_computed');
    expect((await repo().goalRecalculate(trip.id)).currentValue,
        trip.currentValue);

    reading = await repo().createGoal(GoalInput(
      name: 'LT 10 kitap $run',
      targetType: 'custom',
      color: '#6B8E5A',
      unit: 'kitap',
      targetValue: 10,
      currentValue: 4,
    ));
    expect(reading.progressSource, 'manual');
    expect(reading.unit, 'kitap');
    expect(reading.currentValue, 4);
    expect(reading.progressPercent, 40.0);
    expect(reading.related, isNull);
    expect(reading.deadline, isNull);
    expect(reading.daysRemaining, isNull);

    // Edit: the link and progress stay unless they changed.
    final edit = GoalInput(
      name: 'LT 12 kitap $run',
      targetType: 'custom',
      color: '#6B8E5A',
      unit: 'kitap',
      targetValue: 12,
      currentValue: reading.currentValue,
    );
    expect(edit.changesFrom(reading).keys,
        unorderedEquals(['name', 'target_value']));
    reading = await repo().updateGoal(reading, edit);
    expect(reading.name, 'LT 12 kitap $run');
    expect(reading.targetValue, 12);
    expect(reading.currentValue, 4);
    reading = await repo().goalUpdateProgress(reading.id, delta: 1);
    expect(reading.currentValue, 5);
    reading = await repo().goalUpdateProgress(reading.id, currentValue: 7.5);
    expect(reading.currentValue, 7.5);
    expect(reading.progressPercent, 62.5);

    // Achieved by hand, then reopened (needs a higher target).
    reading = await repo().markGoalAchieved(reading);
    expect(reading.status, 'achieved');
    expect(reading.currentValue, 12);
    final reached = await refused(repo().reopenGoal(reading.id),
        code: 'target_reached');
    expect(reached.number('current_value'), 12);
    expect(reached.number('target_value'), 12);
    reading = await repo().reopenGoal(reading.id, targetValue: 20);
    expect(reading.status, 'active');
    expect(reading.targetValue, 20);

    // Abandon and reopen.
    reading = await repo().abandonGoal(reading.id);
    expect(reading.status, 'abandoned');
    final grouped = await repo().fetchGoals();
    expect([for (final g in grouped.abandoned) g.id], contains(reading.id));
    expect([for (final g in grouped.active) g.id], contains(trip.id));
    reading = await repo().reopenGoal(reading.id);
    expect(reading.status, 'active');

    // A habit goal follows its habit once linked.
    waterGoal = await repo().createGoal(GoalInput(
      name: 'LT 100 gün su $run',
      targetType: 'habit',
      color: '#4A90D9',
      unit: 'gün',
      targetValue: 100,
    ));
    expect(waterGoal.progressSource, 'manual');
    waterGoal = await repo().linkGoal(waterGoal.id, 'Habit-${water.id}');
    expect(waterGoal.progressSource, 'habit');
    expect(waterGoal.related!.type, 'Habit');
    expect(waterGoal.related!.id, water.id);
    expect(waterGoal.related!.completedDays, 1);
    expect(waterGoal.related!.currentStreak, 1);
    expect(waterGoal.currentValue, 1);
    final tracked = await repo().fetchHabit(water.id);
    expect([for (final g in tracked.trackedByGoals!) g.id], [waterGoal.id]);
    expect(tracked.trackedByGoals!.single.status, 'active');

    final misfit = await refused(
      repo().linkGoal(reading.id, 'Account-${bank.id}'),
      code: 'validation_failed',
    );
    expect(detailTypes(misfit, 'related'), contains('must_match_target_type'));
    await refused(repo().linkGoal(trip.id, 'Account-999999999'),
        kind: ApiErrorKind.notFound);
    final malformed = await refused(repo().linkGoal(trip.id, 'Todo-1'),
        code: 'invalid_parameter');
    expect(malformed.param, 'related');

    // A goal fetched alone matches the list.
    final one = await repo().fetchGoal(trip.id);
    expect(one.currentValue, trip.currentValue);
    expect((await repo().fetchAccount(bank.id)).linkedGoalsCount, 1);

    // A habit serves a goal (informational).
    final serving = HabitInput(
      name: books.name,
      frequency: books.frequency,
      targetCount: books.targetCount,
      color: books.color,
      goalId: reading.id,
    );
    expect(serving.changesFrom(books), {'goal_id': reading.id});
    books = await repo().updateHabit(books, serving);
    expect(books.goalId, reading.id);
  });

  // --- Todos and lists --------------------------------------------------------

  test('todos and lists', () async {
    homeList = await repo().createTodoList(
        TodoListInput(name: 'LT Ev $run', color: '#6B8E5A'));
    expect(homeList.name, 'LT Ev $run');
    expect(homeList.archived, isFalse);
    expect(homeList.openCount, 0);
    expect(homeList.todosCount, 0);
    final renamed = TodoListInput(name: 'LT Ev işleri $run', color: '#6B8E5A');
    expect(renamed.changesFrom(homeList), {'name': 'LT Ev işleri $run'});
    homeList = await repo().updateTodoList(homeList, renamed);
    expect(homeList.name, 'LT Ev işleri $run');

    bill = await repo().createTodo(TodoInput(
      title: 'LT Faturayı öde $run',
      body: 'Elektrik ve su',
      priority: 'high',
      dueDate: today,
      listId: homeList.id,
      goalId: reading.id,
    ));
    createdTodoIds.add(bill.id);
    expect(bill.title, 'LT Faturayı öde $run');
    expect(bill.body, 'Elektrik ve su');
    expect(bill.priority, 'high');
    expect(bill.status, 'pending');
    expect(bill.dueDate, today);
    expect(bill.dueTime, isNull);
    expect(bill.isDateOnly, isTrue);
    expect(bill.dueAt, DateTime(today.year, today.month, today.day, 23, 59, 59));
    expect(bill.overdue, isFalse);
    expect(bill.completedAt, isNull);
    expect(bill.goalId, reading.id);
    expect(bill.todoList!.id, homeList.id);
    expect(bill.todoList!.name, homeList.name);

    final tomorrow = day(today, 1);
    dentistTodo = await repo().createTodo(TodoInput(
      title: 'LT Dişçiyi ara $run',
      dueDate: tomorrow,
      dueTime: '09:30',
    ));
    createdTodoIds.add(dentistTodo.id);
    expect(dentistTodo.priority, 'medium');
    expect(dentistTodo.dueDate, tomorrow);
    expect(dentistTodo.dueTime, '09:30');
    expect(dentistTodo.dueAt,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 30));
    expect(dentistTodo.todoList, isNull);
    expect(dentistTodo.goalId, isNull);

    final todayList = await repo().fetchTodos(filter: 'today');
    expect([for (final t in todayList.todos) t.id], contains(bill.id));
    expect(todayList.counts.keys,
        containsAll(['open', 'today', 'week', 'upcoming', 'overdue',
            'undated', 'done', 'cancelled', 'all']));
    expect(todayList.totalCount, todayList.todos.length);
    final upcoming = await repo().fetchTodos(filter: 'upcoming', sort: 'due');
    expect([for (final t in upcoming.todos) t.id], contains(dentistTodo.id));
    expect([for (final t in upcoming.todos) t.id], isNot(contains(bill.id)));
    final inList = await repo().fetchTodos(listId: homeList.id);
    expect([for (final t in inList.todos) t.id], [bill.id]);
    final unlisted = await repo().fetchTodos(unlisted: true);
    expect([for (final t in unlisted.todos) t.id], contains(dentistTodo.id));
    expect([for (final t in unlisted.todos) t.id], isNot(contains(bill.id)));
    final paged = await repo().fetchTodos(filter: 'all', perPage: 1);
    expect(paged.todos, hasLength(1));
    expect(paged.totalCount, greaterThanOrEqualTo(2));
    await refused(repo().fetchTodos(filter: 'someday'),
        code: 'invalid_parameter');
    await refused(repo().fetchTodos(listId: 999999999),
        kind: ApiErrorKind.notFound);

    // Edit: a new time on the same day goes alone; notes stay.
    final timed = TodoInput(
      title: bill.title,
      body: bill.body,
      priority: 'urgent',
      dueDate: today,
      dueTime: '18:00',
      listId: homeList.id,
      goalId: reading.id,
    );
    expect(timed.changesFrom(bill), {'priority': 'urgent', 'due_time': '18:00'});
    bill = await repo().updateTodo(bill, timed);
    expect(bill.priority, 'urgent');
    expect(bill.dueTime, '18:00');
    expect(bill.dueDate, today);
    expect(bill.body, 'Elektrik ve su');
    expect(bill.todoList!.id, homeList.id);
    expect(bill.goalId, reading.id);

    // Complete and reopen: explicit states, safe to repeat.
    final done = await repo().setTodoDone(bill.id, done: true);
    expect(done.status, 'done');
    expect(done.completedAt, isNotNull);
    expect(done.title, bill.title, reason: 'the full todo, not the old keys');
    final doneAgain = await repo().setTodoDone(bill.id, done: true);
    expect(doneAgain.completedAt, done.completedAt);
    final doneList = await repo().fetchTodos(filter: 'done', sort: 'completed');
    expect([for (final t in doneList.todos) t.id], contains(bill.id));
    final reopened = await repo().setTodoDone(bill.id, done: false);
    expect(reopened.status, 'pending');
    expect(reopened.completedAt, isNull);

    // Postpone: a new day, the time of day kept.
    final later = day(today, 5);
    bill = await repo().postponeTodo(bill.id, later);
    expect(bill.dueDate, later);
    expect(bill.dueTime, '18:00');
    final dentistLater = await repo().postponeTodo(dentistTodo.id, later);
    expect(dentistLater.dueTime, '09:30');
    final undated = await repo().createTodo(
        TodoInput(title: 'LT Tarihsiz $run', listId: homeList.id));
    createdTodoIds.add(undated.id);
    final dated = await repo().postponeTodo(undated.id, later);
    expect(dated.dueDate, later);
    expect(dated.dueTime, isNull, reason: 'no due date: becomes date-only');
    // Clearing the day.
    final cleared = await repo().updateTodo(
        dated, TodoInput(title: dated.title, listId: homeList.id));
    expect(cleared.dueDate, isNull);
    expect(cleared.dueAt, isNull);

    final lists = await repo().fetchTodoLists();
    final mine = lists.lists.firstWhere((l) => l.id == homeList.id);
    expect(mine.openCount, 2);
    expect(mine.todosCount, 2);
    expect(lists.unlistedOpenCount, greaterThanOrEqualTo(1));

    // Delete a todo.
    await repo().deleteTodo(undated.id);
    createdTodoIds.remove(undated.id);
    expect([for (final t in (await repo().fetchTodos(filter: 'all')).todos) t.id],
        isNot(contains(undated.id)));
    await refused(repo().deleteTodo(undated.id), code: 'not_found');

    // Deleting a list keeps its todos (in no list) or takes them along.
    await repo().deleteTodoList(homeList.id, keepTodos: true);
    final orphan = (await repo().fetchTodos(unlisted: true, filter: 'all'))
        .todos
        .firstWhere((t) => t.id == bill.id);
    expect(orphan.todoList, isNull);
    final scratch = await repo().createTodoList(
        TodoListInput(name: 'LT Geçici $run', color: '#B8860B'));
    final inScratch = await repo().createTodo(
        TodoInput(title: 'LT Silinecek $run', listId: scratch.id));
    await repo().deleteTodoList(scratch.id, keepTodos: false);
    expect([for (final t in (await repo().fetchTodos(filter: 'all')).todos) t.id],
        isNot(contains(inScratch.id)));
    expect([for (final l in (await repo().fetchTodoLists()).lists) l.id],
        isNot(contains(scratch.id)));
  });

  // --- Events -----------------------------------------------------------------

  test('events: one-off, all-day, recurring, end series, delete', () async {
    final tomorrow = day(today, 1);
    standup = await repo().createEvent(EventInput(
      title: 'LT Standup $run',
      start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
      end: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 15),
      eventType: 'work',
      color: '#6B8FA0',
      location: 'Ofis',
    ));
    expect(standup.title, 'LT Standup $run');
    expect(standup.startAt,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9));
    expect(standup.endAt,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 15));
    expect(standup.durationMinutes, 15);
    expect(standup.allDay, isFalse);
    expect(standup.recurring, isFalse);
    expect(standup.recurrenceRule, isNull);
    expect(standup.eventType, 'work');
    expect(standup.location, 'Ofis');
    expect(standup.description, isNull);

    tonight = await repo().createEvent(EventInput(
      title: 'LT Akşam $run',
      start: DateTime(today.year, today.month, today.day, 23),
      end: DateTime(today.year, today.month, today.day, 23, 30),
    ));
    final home = await repo().fetchHome();
    expect([for (final e in home.todayEvents) e.id], contains(tonight.id));
    final todayOnly = await repo().fetchEvents(from: today, to: today);
    final tonightListed = todayOnly.firstWhere((e) => e.id == tonight.id);
    expect(tonightListed.occurrences, [today]);

    // All-day: whole days, the end inclusive.
    holiday = await repo().createEvent(EventInput(
      title: 'LT Tatil $run',
      allDay: true,
      start: day(today, 24),
      end: day(today, 26),
    ));
    expect(holiday.allDay, isTrue);
    expect(holiday.startAt, day(today, 24));
    final lastDay = day(today, 26);
    expect(holiday.endAt,
        DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59));
    expect(holiday.durationMinutes, 4319);
    expect(holiday.endDay, lastDay);

    // A weekly series on Tuesdays and Thursdays, from the next Tuesday.
    var anchor = tomorrow;
    while (anchor.weekday != DateTime.tuesday) {
      anchor = day(anchor, 1);
    }
    final until = day(anchor, 56);
    final rule =
        'FREQ=WEEKLY;BYDAY=TU,TH;UNTIL=${isoDate(until).replaceAll('-', '')}';
    yoga = await repo().createEvent(EventInput(
      title: 'LT Yoga $run',
      start: DateTime(anchor.year, anchor.month, anchor.day, 18),
      end: DateTime(anchor.year, anchor.month, anchor.day, 19),
      description: 'Mat getir',
      location: 'Stüdyo',
      eventType: 'health',
      color: '#6B8E5A',
      recurrenceRule: rule.toLowerCase().replaceFirst('freq', 'rrule:freq'),
    ));
    expect(yoga.recurring, isTrue);
    expect(yoga.description, 'Mat getir');
    // UNTIL is stored as a UTC instant: 23:59:59 of that day in Istanbul.
    expect(yoga.recurrenceRule,
        'FREQ=WEEKLY;BYDAY=TU,TH;UNTIL=${isoDate(until).replaceAll('-', '')}T205959Z');
    final parsed = Recurrence.parse(yoga.recurrenceRule,
        anchor: anchor, utcOffset: const Duration(hours: 3));
    expect(parsed.until, until);
    expect(parsed.preset, RecurrencePreset.custom);

    final window = await repo().fetchEvents(from: today, to: day(today, 30));
    final series = window.firstWhere((e) => e.id == yoga.id);
    expect(series.recurring, isTrue);
    final expected = [
      for (var d = anchor; !d.isAfter(day(today, 30)); d = day(d, 1))
        if (d.weekday == DateTime.tuesday || d.weekday == DateTime.thursday) d,
    ];
    expect(series.occurrences, expected);
    expect(series.occurrenceStart(expected[1]),
        DateTime(expected[1].year, expected[1].month, expected[1].day, 18));
    expect(window.map((e) => e.id), containsAll([standup.id, holiday.id]));

    final full = await repo().fetchEvent(yoga.id);
    expect(full.recurrenceRule, yoga.recurrenceRule);
    expect(full.description, 'Mat getir');
    expect(full.occurrences, isEmpty);

    // Edit the whole series: new times on the anchor's date.
    final moved = EventInput(
      title: 'LT Akşam yogası $run',
      start: DateTime(anchor.year, anchor.month, anchor.day, 19),
      end: DateTime(anchor.year, anchor.month, anchor.day, 20),
      description: 'Mat getir',
      location: 'Stüdyo',
      eventType: 'health',
      color: '#6B8E5A',
      recurrenceRule: yoga.recurrenceRule,
    );
    expect(moved.changesFrom(full).keys,
        unorderedEquals(['title', 'start_at', 'end_at']));
    yoga = await repo().updateEvent(full, moved);
    expect(yoga.title, 'LT Akşam yogası $run');
    expect(yoga.startAt, DateTime(anchor.year, anchor.month, anchor.day, 19));
    expect(yoga.durationMinutes, 60);
    expect(yoga.recurrenceRule, full.recurrenceRule);

    // This and following: end the series on the second Tuesday.
    final secondTuesday = day(anchor, 7);
    yoga = await repo().endSeries(yoga, secondTuesday);
    expect(
        Recurrence.parse(yoga.recurrenceRule,
                utcOffset: const Duration(hours: 3))
            .until,
        secondTuesday);
    final ended = (await repo().fetchEvents(from: today, to: day(today, 60)))
        .firstWhere((e) => e.id == yoga.id);
    expect(ended.occurrences, [anchor, day(anchor, 2), secondTuesday]);

    // Refusals.
    final backwards = await refused(
      repo().createEvent(EventInput(
        title: 'LT Ters $run',
        start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10),
        end: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
        recurrenceRule: 'FREQ=HOURLY',
      )),
      code: 'validation_failed',
    );
    expect(detailTypes(backwards, 'end_at'), contains('must_be_after_start'));
    expect(detailTypes(backwards, 'recurrence_rule'),
        contains('unsupported_frequency'));

    for (final event in [standup, tonight, holiday, yoga]) {
      await repo().deleteEvent(event.id);
    }
    await refused(repo().fetchEvent(yoga.id), kind: ApiErrorKind.notFound);
    final gone = await repo().fetchEvents(from: today, to: day(today, 60));
    expect(gone.map((e) => e.id),
        isNot(anyOf(contains(standup.id), contains(yoga.id))));
  });

  // --- Journal ----------------------------------------------------------------

  test('journal: a long multi-paragraph body survives create and edit',
      () async {
    final paragraphs = [
      for (var i = 1; i <= 12; i++)
        [
          '$i. paragraf — sabah erken kalktım, çayı demledim; ışık, şemsiye, '
              'ğüşiöç İĞÜŞÖÇ. "Tırnak" & <etiket> değil, <3 kalp.',
          'Aynı paragrafta yeni satır $i: ${'kelime ' * 20}son.',
          '• madde $i',
        ].join('\n'),
    ];
    final body = paragraphs.join('\n\n');
    expect(body.length, greaterThan(3000));

    entry = await repo().createJournalEntry(JournalInput(
      date: today,
      title: 'LT Uzun gün $run',
      bodyText: body,
      mood: 'good',
      energyLevel: 4,
      weather: 'Güneşli',
      gratitude: 'Aile',
      tags: const ['aile', 'yürüyüş'],
    ));
    expect(entry.isFull, isTrue);
    expect(entry.title, 'LT Uzun gün $run');
    expect(dateOnly(entry.date), today);
    expect(entry.bodyText, body);
    expect(entry.bodyText!.length, body.length);
    expect(entry.bodyPlain, body, reason: 'the full entry: the whole text');
    expect(entry.editableBody, body);
    expect(entry.bodyFormat, 'plain');
    expect(entry.bodyFormatting, isEmpty);
    expect(entry.bodyHtml, contains('&lt;3'));
    expect(entry.bodyHtml, contains('<br>'));
    expect(entry.mood, 'good');
    expect(entry.moodEmoji, '🙂');
    expect(entry.energyLevel, 4);
    expect(entry.weather, 'Güneşli');
    expect(entry.gratitude, 'Aile');
    expect(entry.hasGratitude, isTrue);
    expect(entry.tags, ['aile', 'yürüyüş']);
    expect(entry.createdAt, isNotNull);
    expect(entry.updatedAt, isNotNull);

    final fetched = await repo().fetchJournalEntry(entry.id);
    expect(fetched.bodyText, body);
    expect(fetched.bodyPlain, body);

    final list = await repo().fetchJournal(range: '7d');
    expect(list.range, '7d');
    expect(list.entriesCount, greaterThanOrEqualTo(1));
    expect(list.journalStreak, greaterThanOrEqualTo(1));
    expect(list.moodCounts.keys,
        containsAll(['great', 'good', 'neutral', 'bad', 'awful']));
    final item = list.entries.firstWhere((e) => e.id == entry.id);
    expect(item.isFull, isFalse);
    expect(item.bodyPlain!.length, lessThanOrEqualTo(203));
    expect(item.bodyPlain, endsWith('...'));
    expect(body.startsWith(item.bodyPlain!.substring(0, 150)), isTrue);
    expect(item.tags, ['aile', 'yürüyüş']);

    // Edit the body (a paragraph added) and the title.
    final longer = '$body\n\nEklenen son paragraf $run.';
    final edit = JournalInput(
      date: today,
      title: 'LT Çok uzun gün $run',
      bodyText: longer,
      mood: 'good',
      energyLevel: 4,
      weather: 'Güneşli',
      gratitude: 'Aile',
      tags: const ['aile', 'yürüyüş'],
    );
    expect(edit.changesFrom(fetched).keys,
        unorderedEquals(['title', 'body_text']));
    entry = await repo().updateJournalEntry(fetched, edit);
    expect(entry.title, 'LT Çok uzun gün $run');
    expect(entry.bodyText, longer);
    expect((await repo().fetchJournalEntry(entry.id)).bodyText, longer);

    // Edit the mood only: the body is not sent and stays whole.
    final moodOnly = JournalInput(
      date: today,
      title: entry.title,
      bodyText: entry.editableBody,
      mood: 'great',
      energyLevel: 4,
      weather: 'Güneşli',
      gratitude: 'Aile',
      tags: const ['aile'],
    );
    expect(moodOnly.changesFrom(entry).keys, unorderedEquals(['mood', 'tags']));
    entry = await repo().updateJournalEntry(entry, moodOnly);
    expect(entry.mood, 'great');
    expect(entry.moodEmoji, '😄');
    expect(entry.tags, ['aile']);
    expect(entry.bodyText, longer);

    final invalid = await refused(
      repo().createJournalEntry(JournalInput(
        date: today,
        mood: 'happy',
        energyLevel: 9,
      )),
      code: 'validation_failed',
    );
    expect(detailTypes(invalid, 'mood'), contains('inclusion'));
    expect(detailTypes(invalid, 'energy_level'), contains('inclusion'));

    await repo().deleteJournalEntry(entry.id);
    await refused(repo().fetchJournalEntry(entry.id),
        kind: ApiErrorKind.notFound);
  });

  // --- Quick capture ----------------------------------------------------------

  test('quick capture: money, habit, todo, event suggestion, errors',
      () async {
    final spent = await repo().quickCapture('-1.250,50 market $run');
    expect(spent.saved, isTrue);
    expect(spent.capturedType, 'transaction');
    expect(spent.message, isNotEmpty);
    final tx = spent.transaction!;
    expect(spent.recordId, tx.id);
    expect(tx.kind, 'expense');
    expect(tx.amountCents, 125050);
    expect(tx.description, 'market $run');
    expect(tx.account.id, wallet.id, reason: 'the oldest active account');
    expect(tx.category, isNull);
    expect(dateOnly(tx.date), today);

    final earned = await repo().quickCapture('+250 ikramiye $run');
    expect(earned.transaction!.kind, 'income');
    expect(earned.transaction!.amountCents, 25000);

    final habit = await repo().quickCapture('alışkanlık: ${running.name.toLowerCase()}');
    expect(habit.saved, isTrue);
    expect(habit.capturedType, 'habit_log');
    expect(habit.summary, running.name);
    final log = habit.habitLog!;
    expect(log.count, 1, reason: 'a daily habit moves one step');
    expect(log.completed, isFalse);
    expect(dateOnly(log.date), today);
    expect(habit.record!['habit_id'], running.id);
    expect((await repo().fetchHabit(running.id)).today.count, 1);

    final todo = await repo().quickCapture('3 yumurta al $run');
    expect(todo.saved, isTrue);
    expect(todo.capturedType, 'todo');
    expect(todo.todo!.title, '3 yumurta al $run');
    expect(todo.todo!.status, 'pending');
    expect(todo.todo!.dueDate, isNull);
    createdTodoIds.add(todo.todo!.id);

    final event = await repo().quickCapture('yarın 15:00 dişçi $run');
    expect(event.saved, isFalse);
    expect(event.isEventSuggestion, isTrue);
    expect(event.recordId, isNull);
    final suggestion = event.suggestion!;
    final tomorrow = day(today, 1);
    expect(suggestion.title, 'dişçi $run');
    expect(suggestion.date, tomorrow);
    expect(suggestion.time, '15:00');
    expect(suggestion.startAt,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15));
    expect(suggestion.allDay, isFalse);
    expect(suggestion.keyword, 'yarın');
    final allDay = await repo().quickCapture('cuma toplantı $run');
    expect(allDay.saved, isFalse);
    expect(allDay.suggestion!.time, isNull);
    expect(allDay.suggestion!.startAt, isNull);
    expect(allDay.suggestion!.allDay, isTrue);
    expect(allDay.suggestion!.date.weekday, DateTime.friday);

    final asTodo =
        await repo().quickCapture('yarın 15:00 dişçi $run', asTodo: true);
    expect(asTodo.saved, isTrue);
    expect(asTodo.capturedType, 'todo');
    expect(asTodo.todo!.title, 'yarın 15:00 dişçi $run');
    createdTodoIds.add(asTodo.todo!.id);

    await refused(repo().quickCapture(''), code: 'empty');
    final zero = await refused(repo().quickCapture('-0 hiç'),
        code: 'invalid_amount');
    expect(zero.reason, 'zero');
    final unknown = await refused(
        repo().quickCapture('habit: olmayan $run'),
        code: 'unknown_habit');
    expect(unknown.name, 'olmayan $run');
    final tooLong = await refused(repo().quickCapture('a' * 201),
        code: 'validation_failed');
    expect(detailTypes(tooLong, 'title'), contains('too_long'));
    expect(tooLong.details['title']!.first.count, 200);

    for (final id in [spent.recordId!, earned.recordId!]) {
      await repo().deleteTransaction(id);
    }
  });

  // --- Deletes and what they leave behind -----------------------------------

  test('habit and goal deletes unlink what pointed at them', () async {
    // Deleting a tracked habit leaves its goal manual, with the final count.
    await repo().deleteHabit(water.id);
    await refused(repo().fetchHabit(water.id), kind: ApiErrorKind.notFound);
    final orphaned = await repo().fetchGoal(waterGoal.id);
    expect(orphaned.related, isNull);
    expect(orphaned.progressSource, 'manual');
    expect(orphaned.currentValue, 1);

    // Deleting a goal leaves the habit and todo that served it.
    await repo().deleteGoal(reading.id);
    await refused(repo().fetchGoal(reading.id), kind: ApiErrorKind.notFound);
    expect((await repo().fetchHabit(books.id)).goalId, isNull);
    final todo = (await repo().fetchTodos(filter: 'all'))
        .todos
        .firstWhere((t) => t.id == bill.id);
    expect(todo.goalId, isNull);

    for (final goal in [trip, waterGoal]) {
      await repo().deleteGoal(goal.id);
    }
    for (final habit in [books, running]) {
      await repo().deleteHabit(habit.id);
    }
    for (final id in createdTodoIds) {
      await repo().deleteTodo(id);
    }
    final archived = await repo().fetchArchivedHabits();
    expect(archived.map((h) => h.id), isNot(contains(books.id)));
  });

  test('categories: a delete takes subcategories and budgets, keeps rows',
      () async {
    final usage = await repo().fetchCategory(market.id);
    expect(usage.childrenCount, 1);
    expect(usage.transactionsCount, 2);
    expect(usage.budgetsCount, 1);
    await repo().deleteCategory(market.id);
    await refused(repo().fetchCategory(market.id),
        kind: ApiErrorKind.notFound);
    await refused(repo().fetchCategory(snacks.id),
        kind: ApiErrorKind.notFound);
    final kept = await repo().fetchTransaction(snackTx.id);
    expect(kept.transaction.category, isNull);
    expect((await repo().fetchTransaction(marketTx.id)).transaction.category,
        isNull);
    final budgets = await repo().fetchBudgets();
    expect(budgets.budgets.map((b) => b.id), isNot(contains(budget.id)));
    await refused(repo().deleteBudget(budget.id), code: 'not_found');

    // A budget deleted on its own.
    final other = await repo().createBudget(
        BudgetInput(categoryId: subsCat.id, monthlyLimitCents: 50000));
    expect(other.spentCents, 9999);
    await repo().deleteBudget(other.id);
    expect((await repo().fetchBudgets()).budgets.map((b) => b.id),
        isNot(contains(other.id)));
  });

  test('accounts: deletable once no transaction touches them', () async {
    await repo().deleteSubscription(spotify.id);
    for (final account in [wallet, bank, gold]) {
      final page = await repo().fetchTransactions(accountId: account.id);
      for (final tx in page.items) {
        await repo().deleteTransaction(tx.id);
      }
    }
    for (final account in [wallet, bank, gold]) {
      final detail = await repo().fetchAccount(account.id);
      expect(detail.deletable, isTrue, reason: account.name);
      await repo().deleteAccount(account.id);
      await refused(repo().fetchAccount(account.id),
          kind: ApiErrorKind.notFound);
    }
    for (final category in [salary, subsCat]) {
      await repo().deleteCategory(category.id);
    }
  });

  // --- Profile ----------------------------------------------------------------

  test('profile: name, currency, time zone', () async {
    final before = container.read(currentUserProvider)!;
    final named = await profile().update(name: 'LT Profil $run');
    expect(named.displayName, 'LT Profil $run');
    expect(named.initials, 'LP');
    expect(container.read(currentUserProvider)!.displayName, 'LT Profil $run');

    final dollars = await profile().update(currency: ' usd ');
    expect(dollars.currency, 'USD');
    expect((await repo().fetchHome()).currency, 'USD');
    expect((await repo().fetchBudgets()).currency, 'USD');

    final london = await profile().update(timezone: 'Europe/London');
    expect(london.timezone, 'London');
    expect(london.timezoneIana, 'Europe/London');
    final options = await repo().fetchMeOptions();
    expect(london.utcOffset, options.zoneOf(value: 'London')!.utcOffset);

    final weekly = await profile().update(weeklyReviewDay: 1);
    expect(weekly.weeklyReviewDay, 1);

    final refusal = await refused(
      profile().update(name: '', timezone: 'Mars/Olympus', currency: 'xyz'),
      code: 'validation_failed',
    );
    expect(detailTypes(refusal, 'name'), contains('blank'));
    expect(detailTypes(refusal, 'timezone'), contains('inclusion'));
    expect(detailTypes(refusal, 'currency'), contains('inclusion'));
    await refused(
      profile().update(email: 'baska-$run@meridian.local'),
      code: 'current_password_required',
    );

    final restored = await profile().update(
      name: before.displayName,
      currency: before.currency,
      timezone: before.timezone,
      weeklyReviewDay: before.weeklyReviewDay,
    );
    expect(restored.displayName, before.displayName);
    expect(restored.currency, 'TRY');
    expect(restored.timezone, 'Istanbul');
    expect(restored.utcOffset, const Duration(hours: 3));
    expect(restored.weeklyReviewDay, before.weeklyReviewDay);
  });

  test('password change rotates the token and keeps the session', () async {
    final oldToken = tokens.token!;
    final wrong = await refused(
      profile().changePassword(
        currentPassword: 'yanlış-şifre',
        password: rotatedPassword,
        passwordConfirmation: rotatedPassword,
      ),
      code: 'invalid_current_password',
    );
    expect(detailTypes(wrong, 'current_password'), contains('invalid'));
    expect(tokens.token, oldToken, reason: 'nothing changes on an error');

    passwordRotated = true;
    final user = await profile().changePassword(
      currentPassword: password,
      password: rotatedPassword,
      passwordConfirmation: rotatedPassword,
    );
    expect(user.email, email);
    final newToken = tokens.token!;
    expect(newToken, isNot(oldToken));
    expect(container.read(sessionProvider), isA<SessionLoggedIn>());
    // The session goes on with the new token; the old one is dead.
    expect((await repo().fetchHome()).today, isNotNull);
    await refused(repoWith(oldToken).fetchHome(),
        code: 'unauthorized', kind: ApiErrorKind.unauthorized);

    await profile().changePassword(
      currentPassword: rotatedPassword,
      password: password,
      passwordConfirmation: password,
    );
    passwordRotated = false;
    expect(tokens.token, isNot(newToken));
    expect((await repo().fetchHome()).today, isNotNull);
  });

  test('sign out revokes the token', () async {
    final token = tokens.token!;
    await profile().signOut();
    final state = container.read(sessionProvider);
    expect(state, isA<SessionLoggedOut>());
    expect((state as SessionLoggedOut).revokeFailed, isFalse);
    expect(tokens.token, isNull);
    expect(prefs.getString(PrefKeys.serverUrl), baseUrl);
    await refused(repoWith(token).fetchHome(),
        code: 'unauthorized', kind: ApiErrorKind.unauthorized);
    // Revoking again with the dead token is "already signed out".
    await refused(repoWith(token).revokeSession(),
        kind: ApiErrorKind.unauthorized);
  });

  // --- The fake API -----------------------------------------------------------

  test("the fake API's canned answers have the server's shape", () async {
    final fake = FakeApi();
    final departures = <String>[];
    var compared = 0;
    for (final key in FakeApi.defaultRoutes) {
      final [method, path] = key.split(' ');
      final real = served[routeTemplate(method, path)];
      if (real == null) continue;
      final response = await fake.dio.request<Object?>(
        path,
        data: switch (method) {
          'PUT' => {'count': 1},
          'PATCH' when path.endsWith('/toggle') => {'done': true},
          _ => null,
        },
        options: Options(method: method),
      );
      if (response.data is! Map && response.data is! List) continue;
      compared++;
      departures.addAll(real.departures(
        JsonShape()..add(response.data),
        key,
        // Present only for some records (contract §5.1).
        conditional: const {
          'chain[].completed',
          'chain[].possible',
          '.period',
        },
      ));
    }
    expect(compared, greaterThan(50), reason: 'routes compared');
    expect(departures, isEmpty, reason: departures.join('\n'));
  });
}
