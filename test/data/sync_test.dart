import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/actions.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/data_scope.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/repository.dart';
import 'package:meridian_mobile/data/sync.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/budget.dart';
import 'package:meridian_mobile/models/finance_category.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/models/subscription.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/journal.dart';
import 'package:meridian_mobile/models/todo.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/ui/widgets/sync_hint.dart';

import '../support/fake_api.dart';
import '../support/read_models.dart';

// What each kind of write must refetch, by GET path — read off the server:
// /home folds in transactions, habit logs, todos and goals; the dashboard
// and balances sum transactions; GET /goals and /goals/:id recalculate
// financial goals from balances and habit goals from completed logs.
const _transactionReads = {
  '/transactions',
  '/finance/dashboard',
  '/accounts',
  // An account's detail counts its transactions (can it be deleted?), a
  // category's what its delete would leave uncategorized, a budget sums
  // its category's spending.
  '/accounts/1',
  '/finance_categories/5',
  '/budgets',
  '/home',
  '/goals',
  '/goals/3',
};
const _habitReads = {'/habits', '/habits/7', '/home', '/goals', '/goals/3'};
// An account's detail counts the goals that track it.
const _goalReads = {'/goals', '/goals/3', '/home', '/accounts/1'};
// An account's own data is embedded in transaction rows, the dashboard,
// subscriptions and goals; its opening balance moves balances and goals.
const _accountReads = {
  '/accounts',
  '/accounts/1',
  '/currencies',
  '/transactions',
  '/finance/dashboard',
  '/subscriptions',
  '/goals',
  '/goals/3',
  '/home',
};
// An account opened, archived or restored: only the account lists know.
const _accountListReads = {'/accounts', '/accounts/1', '/currencies'};
// A delete takes the account's subscriptions and unlinks its goals; its own
// detail is not asked for again (that could only answer 404).
const _accountDeleteReads = {
  '/accounts',
  '/currencies',
  '/transactions',
  '/finance/dashboard',
  '/subscriptions',
  '/goals',
  '/goals/3',
  '/home',
  '/finance_categories/5',
};
const _categoryReads = {
  '/finance_categories',
  '/finance_categories/5',
  '/transactions',
  '/finance/dashboard',
  '/budgets',
  '/subscriptions',
};
const _categoryListReads = {
  '/finance_categories',
  '/finance_categories/5',
  '/budgets',
};
const _budgetReads = {'/budgets', '/finance/dashboard', '/finance_categories/5'};
const _subscriptionReads = {
  '/subscriptions',
  '/finance/dashboard',
  '/accounts/1',
  '/finance_categories/5',
};
const _todoReads = {'/todos', '/home'};
const _journalReads = {'/journal_entries', '/journal_entries/20'};
// A deleted entry is not asked for again: that could only answer 404.
const _journalDeleteReads = {'/journal_entries'};

final _txInput = TransactionInput(
  kind: 'expense',
  amountCents: 2500,
  date: DateTime(2026, 10, 4),
  accountId: 1,
);
const _habitInput = HabitInput(
  name: 'Yeni',
  frequency: 'daily',
  targetCount: 1,
  color: '#D4A853',
);
const _goalInput = GoalInput(
  name: 'Yeni',
  targetType: 'custom',
  color: '#6B8E5A',
  targetValue: 10,
);
final _journalInput = JournalInput(date: DateTime(2026, 10, 4), body: 'Not');
const _todoInput = TodoInput(title: 'Süt al');
final _savedTx = Transaction.fromJson(transactionJson());
final _account = Account.fromJson(accountJson());
const _accountInput = AccountInput(
  name: 'Ziraat',
  accountType: 'bank',
  color: '#6B8FA0',
);
final _category = TxCategory.fromJson(categoryJson());
const _categoryInput = CategoryInput(
  name: 'Gıda',
  kind: 'expense',
  color: '#D4915A',
);
final _budget = BudgetStatus.fromJson(budgetJson());
const _budgetInput = BudgetInput(categoryId: 5, monthlyLimitCents: 400000);
final _subscription = Subscription.fromJson(subscriptionJson());
const _subscriptionInput = SubscriptionInput(
  name: 'Netflix',
  accountId: 1,
  amountCents: 24999,
  frequency: 'monthly',
  color: '#B8860B',
);

/// The day the fake server reports as today.
final _day = DateTime(2026, 10, 4);
const _log7 = 'PUT /habits/7/logs/2026-10-04';

void main() {
  group('readModelsFor (the scope → read model table)', () {
    test('every scope refreshes something and every read model is reachable',
        () {
      final reachable = <ProviderOrFamily>{};
      for (final scope in DataScope.values) {
        final models = readModelsFor(scope);
        expect(models, isNotEmpty, reason: '$scope refreshes nothing');
        reachable.addAll(models);
      }
      expect(reachable, allReadModels);
    });

    test('server aggregates follow every input they fold in', () {
      // /home: month net + 7-day spending, today's habits and their stats,
      // open/overdue/upcoming todos, today's events, the top active goals.
      // Its goal bars are the goals' progress, which follows balances
      // (accounts) as well.
      for (final scope in [
        DataScope.transactions,
        DataScope.accounts,
        DataScope.habits,
        DataScope.habitLogs,
        DataScope.goals,
        DataScope.todos,
        DataScope.events,
      ]) {
        expect(readModelsFor(scope), contains(homeProvider), reason: '$scope');
      }
      // /home has no journal, category, budget or subscription data.
      for (final scope in [
        DataScope.journal,
        DataScope.categories,
        DataScope.budgets,
        DataScope.subscriptions,
      ]) {
        expect(readModelsFor(scope), isNot(contains(homeProvider)),
            reason: '$scope');
      }

      // The finance dashboard sums transactions per category, budget and
      // subscription, and embeds account and category names.
      for (final scope in [
        DataScope.transactions,
        DataScope.accounts,
        DataScope.categories,
        DataScope.budgets,
        DataScope.subscriptions,
      ]) {
        expect(readModelsFor(scope), contains(financeDashboardProvider),
            reason: '$scope');
      }

      // Goals recalculate on read: financial ones from balances and income,
      // habit ones from completed logs.
      for (final scope in [
        DataScope.transactions,
        DataScope.accounts,
        DataScope.habits,
        DataScope.habitLogs,
        DataScope.goals,
      ]) {
        expect(readModelsFor(scope),
            containsAll(<ProviderOrFamily>[goalsProvider, goalDetailProvider]),
            reason: '$scope');
      }

      // Balances are computed from transactions.
      expect(readModelsFor(DataScope.transactions), contains(accountsProvider));
    });

    test('currency and time zone (me) shape every read model', () {
      expect(readModelsFor(DataScope.me), allReadModels);
    });
  });

  group('every write refetches exactly what the server now reports '
      'differently', () {
    late FakeApi api;
    late ProviderContainer container;
    late MeridianRepository repo;

    setUp(() async {
      api = FakeApi();
      container = containerFor(api);
      await showEverything(container, api);
      repo = container.read(repositoryProvider);
    });

    final cases = <String, (Future<Object?> Function(MeridianRepository), Set<String>)>{
      'createTransaction': ((r) => r.createTransaction(_txInput), _transactionReads),
      'updateTransaction': ((r) => r.updateTransaction(_savedTx, _txInput), _transactionReads),
      'deleteTransaction': ((r) => r.deleteTransaction(316), _transactionReads),
      'setHabitLog': ((r) => r.setHabitLog(7, _day, count: 1), _habitReads),
      'createHabit': ((r) => r.createHabit(_habitInput), _habitReads),
      'updateHabit': ((r) => r.updateHabit(7, _habitInput), _habitReads),
      'archiveHabit': ((r) => r.archiveHabit(7), _habitReads),
      'goalUpdateProgress (delta)': ((r) => r.goalUpdateProgress(3, delta: 1), _goalReads),
      'goalUpdateProgress (value)': ((r) => r.goalUpdateProgress(3, currentValue: 50), _goalReads),
      'goalRecalculate': ((r) => r.goalRecalculate(3), _goalReads),
      'createGoal': ((r) => r.createGoal(_goalInput), _goalReads),
      'updateGoal': ((r) => r.updateGoal(3, _goalInput), _goalReads),
      'abandonGoal': ((r) => r.abandonGoal(3), _goalReads),
      'createJournalEntry': ((r) => r.createJournalEntry(_journalInput), _journalReads),
      'updateJournalEntry': ((r) => r.updateJournalEntry(20, _journalInput), _journalReads),
      'deleteJournalEntry': ((r) => r.deleteJournalEntry(20), _journalDeleteReads),
      'setTodoDone': ((r) => r.setTodoDone(39, done: true), _todoReads),
      'createAccount': ((r) => r.createAccount(_accountInput), _accountListReads),
      'updateAccount': ((r) => r.updateAccount(_account, _accountInput), _accountReads),
      'archiveAccount': ((r) => r.archiveAccount(1), _accountListReads),
      'unarchiveAccount': ((r) => r.unarchiveAccount(1), _accountListReads),
      'deleteAccount': ((r) => r.deleteAccount(1), _accountDeleteReads),
      'createCategory': ((r) => r.createCategory(_categoryInput), _categoryListReads),
      'updateCategory': ((r) => r.updateCategory(_category, _categoryInput), _categoryReads),
      'deleteCategory': ((r) => r.deleteCategory(5), _categoryReads.difference({'/finance_categories/5'})),
      'createBudget': ((r) => r.createBudget(_budgetInput), _budgetReads),
      'updateBudget': ((r) => r.updateBudget(_budget, _budgetInput), _budgetReads),
      'deleteBudget': ((r) => r.deleteBudget(2), _budgetReads),
      'createSubscription': ((r) => r.createSubscription(_subscriptionInput), _subscriptionReads),
      'updateSubscription': ((r) => r.updateSubscription(_subscription, _subscriptionInput, accountCurrency: 'TRY'), _subscriptionReads),
      'setSubscriptionActive': ((r) => r.setSubscriptionActive(6, active: false), _subscriptionReads),
      'deleteSubscription': ((r) => r.deleteSubscription(6), _subscriptionReads),
      'chargeSubscription': ((r) => r.chargeSubscription(6), {..._subscriptionReads, ..._transactionReads}),
      'createTodo': ((r) => r.createTodo(_todoInput), _todoReads),
      'updateTodo': ((r) => r.updateTodo(39, _todoInput), _todoReads),
      // Language and theme shape nothing the server reports.
      'updateMe': ((r) => r.updateMe(locale: 'en', themePreference: 'light'), <String>{}),
    };

    for (final MapEntry(key: name, value: (write, expected)) in cases.entries) {
      test(name, () async {
        await write(repo);
        await settle(api);
        expect(api.gets.toSet(), expected);
        // One refetch per read model, however many scopes name it.
        expect(api.gets, hasLength(expected.length));
      });
    }

    group('quickCapture refreshes by what the text became', () {
      final anyOfThem = {..._transactionReads, ..._habitReads, ..._todoReads};
      final byType = <String?, Set<String>>{
        'transaction': _transactionReads,
        'habit_log': _habitReads,
        'todo': _todoReads,
        // An answer that does not say — a type this app does not know yet,
        // or none — may have changed any of the three.
        'reminder': anyOfThem,
        '': anyOfThem,
        null: anyOfThem,
      };
      for (final MapEntry(key: type, value: expected) in byType.entries) {
        test('saved: ${type ?? 'no type'}', () async {
          api.on(
            'POST /quick_captures',
            {'saved': true, 'captured_type': type, 'record_id': 1, 'summary': 'x'},
            status: 201,
          );
          await repo.quickCapture('x');
          await settle(api);
          expect(api.gets.toSet(), expected);
          // One refetch per read model, however many scopes name it.
          expect(api.gets, hasLength(expected.length));
        });
      }

      test('a line that names a day saves nothing: nothing is refetched',
          () async {
        api.on('POST /quick_captures', {
          'saved': false,
          'captured_type': 'event_suggestion',
          'record_id': null,
          'summary': 'yarın 15:00 dişçi',
          'suggestion': {
            'title': 'dişçi',
            'date': '2026-10-05',
            'time': '15:00',
            'start_at': '2026-10-05T15:00:00.000+03:00',
            'all_day': false,
            'keyword': 'yarın',
          },
        });
        final result = await repo.quickCapture('yarın 15:00 dişçi');
        expect(result.saved, isFalse);
        await settle(api);
        expect(api.gets, isEmpty);
      });

      test('saved: false says nothing changed, whatever the type', () async {
        api.on('POST /quick_captures',
            {'saved': false, 'captured_type': 'reminder', 'summary': 'x'});
        await repo.quickCapture('x');
        await settle(api);
        expect(api.gets, isEmpty);
      });

      test('an event suggestion from a server that sends no "saved" is not '
          'taken as saved', () async {
        api.on('POST /quick_captures', {
          'captured_type': 'event_suggestion',
          'record_id': null,
          'summary': 'yarın dişçi',
        });
        final result = await repo.quickCapture('yarın dişçi');
        expect(result.saved, isFalse);
        await settle(api);
        expect(api.gets, isEmpty);
      });

      test('as a task: only todos can change, and the line goes as it is',
          () async {
        await repo.quickCapture('yarın 15:00 dişçi', asTodo: true);
        await settle(api);
        expect(api.gets.toSet(), _todoReads);
        expect(api.bodiesOf('POST /quick_captures').single,
            {'text': 'yarın 15:00 dişçi', 'as': 'todo'});
      });

      test('a refusal (no account, unknown habit, …) refetches nothing',
          () async {
        api.on('POST /quick_captures', {
          'errors': {
            'text': ['İlk hesabını oluştur'],
          },
          'code': 'no_account',
        }, status: 422);
        await expectLater(
          repo.quickCapture('-250 kahve'),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'no_account')),
        );
        await settle(api);
        expect(api.gets, isEmpty);
      });
    });

    group('explicit-state writes say what they want, not "flip"', () {
      test('setHabitLog sends the count for the day the server reported',
          () async {
        await repo.setHabitLog(8, _day, count: 2);
        expect(api.requests, contains('PUT /habits/8/logs/2026-10-04'));
        expect(api.bodiesOf('PUT /habits/8/logs/2026-10-04').single,
            {'count': 2});
      });

      test('setHabitLog never sends a negative count', () async {
        await repo.setHabitLog(8, _day, count: -1);
        expect(api.bodiesOf('PUT /habits/8/logs/2026-10-04').single,
            {'count': 0});
      });

      test('setHabitLog parses the habit, the header and the day set',
          () async {
        final result = await repo.setHabitLog(8, _day, count: 3);
        expect(result.habit.today.count, 3);
        expect(result.habit.today.completed, isTrue);
        expect(result.log!.count, 3);
        expect(result.log!.date, _day);
      });

      test('setTodoDone sends done=true or done=false and reads the todo back',
          () async {
        final done = await repo.setTodoDone(39, done: true);
        expect(done.isDone, isTrue);
        expect(done.title, 'Faturayı öde');
        final open = await repo.setTodoDone(39, done: false);
        expect(open.isDone, isFalse);
        expect(api.bodiesOf('PATCH /todos/39/toggle'), [
          {'done': true},
          {'done': false},
        ]);
      });

      test('setTodoDone reads a pre-G1 answer too', () async {
        api.on('PATCH /todos/39/toggle', {'id': 39, 'status': 'done'});
        expect((await repo.setTodoDone(39, done: true)).isDone, isTrue);
      });
    });

    group('a failed write', () {
      test('rejected (422): nothing changed, nothing refetched', () async {
        api.fail('PATCH /todos/39/toggle', 422);
        await expectLater(
          repo.setTodoDone(39, done: true),
          throwsA(isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.validation)),
        );
        await settle(api);
        expect(api.gets, isEmpty);
      });

      test('a refusal by code (422 future_date): nothing refetched', () async {
        api.on(_log7, {
          'errors': {
            'date': ['Gelecekteki bir gün işaretlenemez.'],
          },
          'code': 'future_date',
        }, status: 422);
        await expectLater(
          repo.setHabitLog(7, _day, count: 1),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'future_date')),
        );
        await settle(api);
        expect(api.gets, isEmpty);
      });

      test('a refusal that proves the screen out of date (422 '
          'habit_archived): nothing changed, but every read model that '
          'lists the habit refetches, so Today and Habits drop it', () async {
        api.on(_log7, {
          'errors': {
            'base': ['Arşivlenmiş alışkanlık işaretlenemez.'],
          },
          'code': 'habit_archived',
        }, status: 422);
        await expectLater(
          repo.setHabitLog(7, _day, count: 1),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'habit_archived')),
        );
        await settle(api);
        expect(api.gets.toSet(), _habitReads);
        expect(api.gets, containsAll(['/home', '/habits']));
      });

      test('not found (404): refetched, so the stale row disappears', () async {
        api.fail('PATCH /todos/39/toggle', 404);
        await expectLater(
            repo.setTodoDone(39, done: true), throwsA(isA<ApiException>()));
        await settle(api);
        expect(api.gets.toSet(), _todoReads);
      });

      test('no answer: the outcome is unknown, so it is refetched', () async {
        api.failNetwork(_log7);
        await expectLater(
          repo.setHabitLog(7, _day, count: 1),
          throwsA(isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.network)),
        );
        await settle(api);
        expect(api.gets.toSet(), _habitReads);
      });

      test('an answer that does not parse: the server did write, so refetch',
          () async {
        api.on(_log7, {
          'habit': {'id': 'not-an-id'},
        });
        await expectLater(
            repo.setHabitLog(7, _day, count: 1), throwsFormatException);
        await settle(api);
        expect(api.gets.toSet(), _habitReads);
      });
    });

    test('refetches wait for every write in flight, then run once', () async {
      api.hold('PATCH /goals/3/update_progress');
      final slow = repo.goalUpdateProgress(3, delta: 1);
      await repo.setTodoDone(39, done: true);
      await settle(api);
      // A refetch now could bring /home back without the goal step.
      expect(api.gets, isEmpty);

      api.release('PATCH /goals/3/update_progress');
      await slow;
      await settle(api);
      expect(api.gets.toSet(), {..._todoReads, ..._goalReads});
      expect(api.gets.where((g) => g == '/home'), hasLength(1));
      expect(container.read(dataSyncProvider).writesInFlight, 0);
    });

    test('markFresh drops the refetch of a model the response already updated',
        () async {
      await repo.setHabitLog(7, _day, count: 1);
      // Right after the write, as HabitActions does after applying the result.
      container.read(dataSyncProvider).markFresh(habitsProvider);
      await settle(api);
      expect(api.gets.toSet(), {..._habitReads}..remove('/habits'));
    });

    test('markFresh withdraws only its own write: a habit created while a '
        'tick was in flight still reaches the Habits list', () async {
      api.hold(_log7);
      final toggle = repo.setHabitLog(7, _day, count: 1);
      await repo.createHabit(_habitInput);
      api.release(_log7);
      await toggle;
      // The toggle's answer is current for the toggle — not for the new habit.
      container.read(dataSyncProvider).markFresh(habitsProvider);
      await settle(api);
      expect(api.gets.toSet(), _habitReads);
      expect(api.gets, hasLength(_habitReads.length));
    });

    test('an explicit refresh does not wait for writes in flight', () async {
      api.hold('PATCH /goals/3/update_progress');
      final slow = repo.goalUpdateProgress(3, delta: 1);
      container.read(dataSyncProvider).refresh([journalProvider]);
      await settle(api);
      expect(api.gets, ['/journal_entries']);
      api.release('PATCH /goals/3/update_progress');
      await slow;
    });

    test('refreshAll refetches every read model on screen', () async {
      container.read(dataSyncProvider).refreshAll();
      await settle(api);
      expect(api.gets.toSet(), readModelsByPath().keys.toSet());
    });
  });

  test('deleting an entry from its screen refreshes the lists once, and '
      'neither asks for the entry again nor flashes the offline banner while '
      'the screen animates out', () async {
    final api = FakeApi();
    final container = containerFor(api);
    // Another entry's screen is open too, under it.
    api.on('GET /journal_entries/21', {'entry': journalEntryJson(id: 21)});
    container.listen(journalEntryProvider(21), (_, _) {});
    await showEverything(container, api);

    // Once deleted, the server answers 404 for it.
    api.fail('GET /journal_entries/20', 404);
    await container.read(repositoryProvider).deleteJournalEntry(20);
    await settle(api);

    expect(api.gets.toSet(), {'/journal_entries', '/journal_entries/21'});
    expect(api.gets.where((p) => p == '/journal_entries'), hasLength(1));
    final leaving = container.read(journalEntryProvider(20));
    expect(leaving.hasValue, isTrue);
    expect(leaving.hasError, isFalse);
  });

  group('a record deleted elsewhere: its detail answers 404, and every list '
      'that may still show it refetches', () {
    final cases = <String, (ProviderOrFamily, String, Set<String>)>{
      // The account detail counts the goals that track it.
      'a goal': (goalDetailProvider, '/goals/3', {'/goals', '/home', '/accounts/1'}),
      'an account': (
        accountDetailProvider,
        '/accounts/1',
        {
          '/accounts',
          '/currencies',
          '/transactions',
          '/finance/dashboard',
          '/subscriptions',
          '/goals',
          '/goals/3',
          '/home',
        },
      ),
      'a category': (
        categoryUsageProvider,
        '/finance_categories/5',
        {
          '/finance_categories',
          '/transactions',
          '/finance/dashboard',
          '/budgets',
          '/subscriptions',
        },
      ),
      'a journal entry': (
        journalEntryProvider,
        '/journal_entries/20',
        {'/journal_entries'},
      ),
      'a habit': (
        habitDetailProvider,
        '/habits/7',
        {'/habits', '/home', '/goals', '/goals/3'},
      ),
    };
    for (final MapEntry(key: name, value: (detail, path, lists))
        in cases.entries) {
      test(name, () async {
        final api = FakeApi();
        final container = containerFor(api);
        await showEverything(container, api);

        api.fail('GET $path', 404);
        container.read(dataSyncProvider).refresh([detail]);
        await settle(api);
        expect(api.gets.toSet(), {path, ...lists});
        // The detail itself is not asked again: it would only 404 again.
        expect(api.gets.where((p) => p == path), hasLength(1));
      });
    }
  });

  group('the signed-in user (GET /me)', () {
    late FakeApi api;
    late ProviderContainer container;

    setUp(() {
      api = FakeApi();
      container = containerFor(
        api,
        overrides: [sessionProvider.overrideWith(_SignedIn.new)],
      );
    });

    test('refreshAll re-reads it: a name changed on the web shows up',
        () async {
      api.on('GET /me', {'user': userJson(name: 'Yeni')});
      container.read(dataSyncProvider).refreshAll();
      await settle(api);
      expect(api.gets, contains('/me'));
      expect(container.read(currentUserProvider)?.displayName, 'Yeni');
    });

    test('a write that changes it (currency, time zone) refetches it and '
        'every read model', () async {
      await showEverything(container, api);
      final sync = container.read(dataSyncProvider);
      sync.writeStarted();
      sync.writeFinished({DataScope.me});
      await settle(api);
      expect(api.gets.toSet(), {...readModelsByPath().keys, '/me'});
    });

    test('other writes leave it alone', () async {
      await showEverything(container, api);
      await container.read(repositoryProvider).setTodoDone(39, done: true);
      await settle(api);
      expect(api.gets, isNot(contains('/me')));
    });
  });

  test('a hidden screen\'s model refetches once, when it is shown again',
      () async {
    final api = FakeApi();
    final container = containerFor(api);
    container.listen(homeProvider, (_, _) {});
    final habitsTab = container.listen(habitsProvider, (_, _) {});
    await settle(api);
    api.clearLog();

    // The Habits tab is hidden: flutter_riverpod pauses its subscription.
    habitsTab.pause();
    await container.read(repositoryProvider).setHabitLog(7, _day, count: 1);
    await settle(api);
    // (The goals are read only to have the server recalculate them for
    // /home's goal bars; no Goals tab was ever opened.)
    expect(api.gets, unorderedEquals(['/goals', '/home']),
        reason: 'only what is visible fetches now');

    api.clearLog();
    habitsTab.resume();
    await settle(api);
    expect(api.gets, ['/habits']);
  });

  test('the read model keeps its data on screen while it refetches', () async {
    final api = FakeApi();
    final container = containerFor(api);
    container.listen(goalsProvider, (_, _) {});
    await settle(api);
    final before = container.read(goalsProvider).value;

    api.hold('GET /goals');
    container.read(dataSyncProvider).refresh([goalsProvider]);
    await settle(api);
    final during = container.read(goalsProvider);
    expect(during.isLoading, isTrue);
    expect(during.value, same(before), reason: 'no skeleton, no blank');

    api.release('GET /goals');
    await settle(api);
    expect(container.read(goalsProvider).isLoading, isFalse);
  });

  group('Today\'s goal bars: /home shows each goal\'s progress as the server '
      'last stored it, and only reading the goals recalculates it', () {
    late FakeApi api;
    late ProviderContainer container;
    // The server: the progress /home reads, and what recalculating the goal
    // (GET /goals) would store now.
    late num stored;
    late num actual;

    num todayBar() => container
        .read(homeProvider)
        .value!
        .data
        .activeGoals
        .single
        .progressPercent;

    num goalsTabRing() => container
        .read(goalsProvider)
        .value!
        .data
        .active
        .single
        .progressPercent;

    int reads(String path) => api.gets.where((p) => p == path).length;

    setUp(() async {
      stored = 40;
      actual = 40;
      api = FakeApi()
        ..onRequest('GET /home', (_) => homeJson(goalProgress: stored))
        ..onRequest('GET /goals', (_) {
          stored = actual;
          return {
            'active': [goalJson(current: stored)],
            'achieved': const [],
            'abandoned': const [],
          };
        })
        // Goal 3 tracks habit 7 — and, say, total income.
        ..onRequest(_log7, (_) {
          actual = 50;
          return logJson();
        })
        ..onRequest('POST /transactions', (_) {
          actual = 50;
          return transactionJson(id: 400);
        });
      container = containerFor(api);
      container.listen(homeProvider, (_, _) {}); // Today is on screen
      await settle(api);
      expect(todayBar(), 40);
      api.clearLog();
    });

    test('a check-in on Today, the Goals tab never opened: the goals are '
        'recalculated, and Today shows the new progress', () async {
      await container.read(habitActionsProvider).setToday(7, 1);
      await settle(api);
      expect(api.gets, unorderedEquals(['/goals', '/home']));
      expect(todayBar(), 50);
    });

    test('an income transaction: /home is asked at once, without waiting for '
        'the goals, and once more when their recalculation moved a goal it '
        'shows', () async {
      api.hold('GET /goals');
      await container.read(repositoryProvider).createTransaction(_txInput);
      await settle(api);
      expect(api.gets, unorderedEquals(['/goals', '/home']),
          reason: '/home does not wait for the goals');
      expect(container.read(homeProvider).isLoading, isFalse);
      expect(todayBar(), 40, reason: 'answered before the recalculation');

      api.release('GET /goals');
      await settle(api);
      expect(reads('/goals'), 1);
      expect(reads('/home'), 2);
      expect(todayBar(), 50);
    });

    test('a recalculation that moves no goal Today shows does not ask /home '
        'again', () async {
      api.hold('GET /goals');
      // A todo and a goal-neutral habit change: nothing moves.
      container.read(dataSyncProvider).refresh([homeProvider, goalsProvider]);
      await settle(api);
      api.release('GET /goals');
      await settle(api);
      expect(api.gets, unorderedEquals(['/goals', '/home']));
      expect(todayBar(), 40);
    });

    test('a goal the recalculation achieves leaves Today\'s bars: /home is '
        'asked again', () async {
      api
        ..hold('GET /goals')
        ..onRequest('GET /goals', (_) => {
              'active': const [],
              'achieved': [
                {...goalJson(current: 100), 'status': 'achieved'},
              ],
              'abandoned': const [],
            });
      container.read(dataSyncProvider).refresh([homeProvider, goalsProvider]);
      await settle(api);
      api.release('GET /goals');
      await settle(api);
      expect(reads('/home'), 2);
    });

    test('a hidden Goals tab: its own refetch is the recalculation, so the '
        'goals are fetched once, and the tab has them when shown', () async {
      final goalsTab = container.listen(goalsProvider, (_, _) {});
      await settle(api);
      goalsTab.pause(); // back on Today
      api.clearLog();

      await container.read(habitActionsProvider).setToday(7, 1);
      await settle(api);
      expect(reads('/goals'), 1);
      expect(todayBar(), 50);

      goalsTab.resume();
      await settle(api);
      expect(reads('/goals'), 1);
      expect(goalsTabRing(), 50);
    });

    test('the Goals tab on screen: its refetch is the recalculation — one '
        'GET /goals — and /home, asked alongside it, is asked again once it '
        'moved a goal', () async {
      container.listen(goalsProvider, (_, _) {});
      await settle(api);
      api.clearLog();

      api.hold('GET /goals');
      await container.read(habitActionsProvider).setToday(7, 1);
      await settle(api);
      expect(api.gets, unorderedEquals(['/goals', '/home']));

      api.release('GET /goals');
      await settle(api);
      expect(reads('/goals'), 1);
      expect(reads('/home'), 2);
      expect(todayBar(), 50);
      expect(goalsTabRing(), 50);
    });

    test('pull-to-refresh, a re-tap or a resume recalculates the goals too: '
        'a transaction added on the web reaches the bars', () async {
      actual = 50;
      api.hold('GET /goals');
      container.read(dataSyncProvider).refreshAll();
      await settle(api);
      expect(todayBar(), 40, reason: '/home answered first');
      api.release('GET /goals');
      await settle(api);
      expect(todayBar(), 50);
    });

    test('the goals cannot be read: /home is fetched anyway', () async {
      api.failNetwork('GET /goals');
      await container.read(habitActionsProvider).setToday(7, 1);
      await settle(api);
      expect(api.gets, unorderedEquals(['/goals', '/home']));
      expect(container.read(homeProvider).hasError, isFalse);
    });

    test('the server cannot be reached: Today shows it as soon as /home '
        'fails, without waiting for the goals', () async {
      api
        ..hold('GET /goals')
        ..failNetwork('GET /home');
      container.read(dataSyncProvider).refresh([homeProvider, goalsProvider]);
      await settle(api);
      final home = container.read(homeProvider);
      expect(home.isLoading, isFalse);
      expect(home.refreshFailed, isTrue);
      api.release('GET /goals');
      await settle(api);
      expect(reads('/home'), 1, reason: 'a failed /home is not asked again');
    });

    test('a write that moves no goal leaves the goals alone', () async {
      await container.read(repositoryProvider).setTodoDone(39, done: true);
      await settle(api);
      expect(api.gets, ['/home']);
    });
  });

  testWidgets('a hidden Goals tab whose read blips: its quick retry runs at '
      'once, not when the tab is shown, and Today is not held up by it',
      (tester) async {
    final api = FakeApi();
    final container = ProviderContainer.test(
      overrides: [dioProvider.overrideWithValue(api.dio)],
      retry: readRetry,
    );
    container.listen(homeProvider, (_, _) {}); // Today on screen
    final goalsTab = container.listen(goalsProvider, (_, _) {});
    await tester.pump(const Duration(milliseconds: 50));
    goalsTab.pause(); // the Goals tab is hidden
    api.clearLog();

    api.blip('GET /goals');
    unawaited(
        container.read(repositoryProvider).setHabitLog(7, _day, count: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.gets, unorderedEquals(['/goals', '/home']),
        reason: 'the retry of /goals is pending');
    expect(container.read(homeProvider).isLoading, isFalse,
        reason: 'Today landed meanwhile');

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.gets.where((p) => p == '/goals'), hasLength(2));
    expect(container.read(homeProvider).hasError, isFalse);

    api.clearLog();
    goalsTab.resume(); // back on Goals: it has the recalculated goals
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.gets, isEmpty);
    final goals = container.read(goalsProvider);
    expect((goals.isLoading, goals.hasError), (false, false));
    container.dispose(); // cancels the midnight timer
  });

  group('readRetry (ProviderScope retry policy)', () {
    test('a refused connection or a 5xx gets one quick retry', () {
      final refused = ApiException(ApiErrorKind.network);
      final server = ApiException(ApiErrorKind.server, status: 502);
      expect(readRetry(0, refused), const Duration(milliseconds: 800));
      expect(readRetry(0, server), const Duration(milliseconds: 800));
      expect(readRetry(0, ApiException(ApiErrorKind.server, status: 500)),
          const Duration(milliseconds: 800));
      expect(readRetry(0, ApiException(ApiErrorKind.server, status: 503)),
          const Duration(milliseconds: 800));
      expect(readRetry(1, refused), isNull);
      expect(readRetry(1, server), isNull);
    });

    test('timeouts, 4xx, parse errors and unknown errors are final', () {
      expect(readRetry(0, ApiException(ApiErrorKind.network, timedOut: true)),
          isNull);
      expect(readRetry(0, ApiException(ApiErrorKind.notFound)), isNull);
      expect(readRetry(0, ApiException(ApiErrorKind.validation)), isNull);
      expect(readRetry(0, ApiException(ApiErrorKind.unauthorized)), isNull);
      expect(readRetry(0, TypeError()), isNull);
      expect(readRetry(0, const FormatException('x')), isNull);
    });

    test('every other 4xx is final too, whatever kind it is filed under',
        () {
      final kinds = {
        400: ApiErrorKind.server,
        403: ApiErrorKind.server,
        409: ApiErrorKind.server,
        422: ApiErrorKind.validation,
        429: ApiErrorKind.rateLimited,
      };
      for (final MapEntry(key: status, value: kind) in kinds.entries) {
        final error = ApiException.fromDio(DioException.badResponse(
          statusCode: status,
          requestOptions: RequestOptions(path: '/home'),
          response: Response(
            requestOptions: RequestOptions(path: '/home'),
            statusCode: status,
            data: {'error': 'nope'},
          ),
        ));
        expect(error.kind, kind, reason: '$status');
        expect(readRetry(0, error), isNull, reason: '$status');
      }
    });
  });

  group('every fetch gets its own quick retry, inside the fetch', () {
    testWidgets('two refreshes in a row that each blip once: neither puts '
        'the offline banner up', (tester) async {
      final api = FakeApi();
      final container = ProviderContainer.test(
        overrides: [dioProvider.overrideWithValue(api.dio)],
        retry: readRetry,
      );
      container.listen(goalsProvider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 50));
      final first = container.read(goalsProvider).value;
      expect(first, isNotNull);

      for (var refresh = 1; refresh <= 2; refresh++) {
        api.blip('GET /goals');
        container.read(dataSyncProvider).refresh([goalsProvider]);
        await tester.pump(const Duration(milliseconds: 50));
        final during = container.read(goalsProvider);
        expect(during.isLoading, isTrue, reason: 'refresh $refresh');
        expect(during.refreshFailed, isFalse, reason: 'refresh $refresh');
        expect(during.hasValue, isTrue, reason: 'kept on screen');

        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 50));
        final after = container.read(goalsProvider);
        expect(after.hasError, isFalse, reason: 'refresh $refresh');
        expect(after.isLoading, isFalse, reason: 'refresh $refresh');
        expect(after.value, isNot(same(first)), reason: 'refresh $refresh');
      }
      expect(api.gets.where((p) => p == '/goals'), hasLength(5));
      container.dispose(); // cancels the midnight timer
    });

    testWidgets('the same when a screen is shown again after a minute',
        (tester) async {
      var now = DateTime(2026, 10, 4, 9);
      final api = FakeApi();
      final container = ProviderContainer.test(
        overrides: [
          dioProvider.overrideWithValue(api.dio),
          clockProvider.overrideWithValue(() => now),
        ],
        retry: readRetry,
      );
      final goalsTab = container.listen(goalsProvider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 50));

      for (var round = 1; round <= 2; round++) {
        goalsTab.pause(); // another tab
        now = now.add(const Duration(minutes: 2));
        api.blip('GET /goals');
        goalsTab.resume(); // back on Goals: refetched, and it blips
        await tester.pump(const Duration(milliseconds: 50));
        final during = container.read(goalsProvider);
        expect(during.isLoading, isTrue, reason: 'round $round');
        expect(during.refreshFailed, isFalse, reason: 'round $round');

        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 50));
        final after = container.read(goalsProvider);
        expect(after.hasError, isFalse, reason: 'round $round');
        expect(after.isLoading, isFalse, reason: 'round $round');
      }
      expect(api.gets.where((p) => p == '/goals'), hasLength(5));
      container.dispose(); // cancels the midnight timer
    });

    testWidgets('a refresh that starts while a retry waits replaces it: the '
        'superseded retry is never sent', (tester) async {
      final api = FakeApi();
      final container = ProviderContainer.test(
        overrides: [dioProvider.overrideWithValue(api.dio)],
        retry: readRetry,
      );
      container.listen(goalsProvider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 50));
      api.clearLog();

      api.blip('GET /goals');
      container.read(dataSyncProvider).refresh([goalsProvider]);
      await tester.pump(const Duration(milliseconds: 50));
      container.read(dataSyncProvider).refresh([goalsProvider]);
      await tester.pump(const Duration(seconds: 2));
      expect(api.gets, ['/goals', '/goals'],
          reason: 'the blip, then the newer refresh — no third request');
      expect(container.read(goalsProvider).hasError, isFalse);
      container.dispose(); // cancels the midnight timer
    });
  });

  test('pull-to-refresh never throws and never hangs', () async {
    await settleRefresh([Future<Object?>.error(StateError('offline'))]);
    final stuck = Completer<Object?>();
    final watch = Stopwatch()..start();
    await settleRefresh([stuck.future],
        timeout: const Duration(milliseconds: 50));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

/// A session that is already signed in, as after the splash gate.
class _SignedIn extends SessionController {
  @override
  SessionState build() => const SessionLoggedIn();
}
