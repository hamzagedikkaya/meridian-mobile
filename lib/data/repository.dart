import 'package:dio/dio.dart';

import '../core/api.dart';
import '../models/account.dart';
import '../models/budget.dart';
import '../models/currency.dart';
import '../models/date_utils.dart';
import '../models/event.dart';
import '../models/finance_category.dart';
import '../models/finance_dashboard.dart';
import '../models/goal.dart';
import '../models/subscription.dart';
import '../models/habit.dart';
import '../models/home.dart';
import '../models/journal.dart';
import '../models/quick_capture.dart';
import '../models/todo.dart';
import '../models/transaction.dart';
import '../models/user.dart';
import 'data_scope.dart';

/// One async method per Meridian endpoint. Every [DioException] is normalized
/// through [ApiException.fromDio]; models never see raw dio errors.
///
/// Every write declares the [DataScope]s it touches and reports itself to
/// [WriteListener] — in the app, `DataSync`, which refreshes every cached
/// screen showing that data. So no screen decides what to refresh after a
/// write, and a write still refreshes everything when the screen that sent it
/// is closed before the answer arrives.
class MeridianRepository {
  MeridianRepository(this._dio, {this._writes});

  final Dio _dio;
  final WriteListener? _writes;

  // --- Me -------------------------------------------------------------------

  /// The two preferences the phone owns: UI language and theme. Sending them
  /// to the server keeps the choice with the account, so the web app and a
  /// reinstall pick it up too. Neither shapes anything the server reports, so
  /// nothing is refetched; the caller adopts the returned user.
  Future<User> updateMe({String? locale, String? themePreference}) => _write(
        'PATCH',
        '/me',
        body: _pruned({
          'locale': locale,
          'theme_preference': themePreference,
        }),
        touches: const {},
        parse: (data) => User.fromJson(_entity(data, 'user')),
      );

  // --- Home -----------------------------------------------------------------

  Future<HomeSummary> fetchHome() =>
      _get('/home', (data) => HomeSummary.fromJson(data));

  // --- Accounts -------------------------------------------------------------

  /// Every account: the active ones by name, then the archived ones — one
  /// list for the carousel and pickers (active only), the archive page and
  /// an archived account's own screen.
  Future<List<Account>> fetchAccounts() => _get(
        '/accounts',
        (data) => _listOf(data['accounts'], Account.fromJson),
        query: {'include_archived': true},
      );

  /// One account with what is recorded on it (whether it can be deleted,
  /// whether its currency can change), archived ones too.
  Future<AccountDetail> fetchAccount(int id) => _get(
        '/accounts/$id',
        (data) => AccountDetail.fromJson(_entity(data, 'account')),
      );

  /// A new account shows in the account lists and nowhere else yet (it has
  /// no transactions); its currency may be new to the currency picker.
  Future<Account> createAccount(AccountInput input) => _write(
        'POST',
        '/accounts',
        body: input.toJson(),
        touches: const {DataScope.accountList},
        parse: (data) => Account.fromJson(_entity(data, 'account')),
      );

  /// Sends only what changed from [before]. Its name, colour and currency
  /// are embedded in transaction rows, the dashboard, subscriptions and
  /// goals; the opening balance moves every balance and the goals that
  /// track it.
  ///
  /// `currency_locked` means the account got a transaction or subscription
  /// since the form learnt it could still change: its detail is refetched.
  Future<Account> updateAccount(Account before, AccountInput input) => _write(
        'PATCH',
        '/accounts/${before.id}',
        body: input.changesFrom(before),
        touches: const {DataScope.accounts},
        staleOn: const {
          'currency_locked': {DataScope.accountList},
        },
        parse: (data) => Account.fromJson(_entity(data, 'account')),
      );

  /// Hides the account from the carousel and the pickers; its transactions
  /// keep counting everywhere. Idempotent.
  Future<Account> archiveAccount(int id) => _write(
        'PATCH',
        '/accounts/$id/archive',
        touches: const {DataScope.accountList},
        parse: (data) => Account.fromJson(_entity(data, 'account')),
      );

  Future<Account> unarchiveAccount(int id) => _write(
        'PATCH',
        '/accounts/$id/unarchive',
        touches: const {DataScope.accountList},
        parse: (data) => Account.fromJson(_entity(data, 'account')),
      );

  /// Deletes an account no transaction touches. Its subscriptions go with
  /// it and the goals that tracked it are unlinked. `has_transactions` —
  /// a transaction was recorded on it meanwhile — refetches its detail,
  /// which then offers archiving instead.
  Future<void> deleteAccount(int id) => _write(
        'DELETE',
        '/accounts/$id',
        touches: const {
          DataScope.accounts,
          DataScope.subscriptions,
          DataScope.goals,
        },
        deletes: (scope: DataScope.accounts, id: id),
        staleOn: const {
          'has_transactions': {DataScope.accountList},
        },
        parse: (_) {},
      );

  /// The currencies a new account can be opened in, and the default one.
  Future<CurrenciesBundle> fetchCurrencies() =>
      _get('/currencies', (data) => CurrenciesBundle.fromJson(data));

  // --- Finance --------------------------------------------------------------

  Future<FinanceDashboard> fetchFinanceDashboard({String? range}) => _get(
        '/finance/dashboard',
        (data) => FinanceDashboard.fromJson(data),
        query: _pruned({'range': range}),
      );

  /// One page of transactions. [uncategorized] asks for the ones without a
  /// category (`category_id=none`) instead of [categoryId];
  /// [includeIncomingTransfers] adds, to an [accountId] filter, the other
  /// accounts' transfers into it.
  Future<TransactionsPage> fetchTransactions({
    String? kind,
    int? accountId,
    int? categoryId,
    bool uncategorized = false,
    bool includeIncomingTransfers = false,
    DateTime? from,
    DateTime? to,
    int page = 1,
  }) =>
      _get(
        '/transactions',
        (data) => TransactionsPage.fromJson(data),
        query: _pruned({
          'kind': kind,
          'account_id': accountId,
          'include_incoming_transfers':
              accountId != null && includeIncomingTransfers ? true : null,
          'category_id': uncategorized ? 'none' : categoryId,
          'from': from == null ? null : isoDate(from),
          'to': to == null ? null : isoDate(to),
          'page': page,
        }),
      );

  /// One transaction with the other row of its linked pair, if it has one —
  /// which says whether a delete would take that row along (see
  /// [TransactionDetail.deletesLinked]).
  Future<TransactionDetail> fetchTransaction(int id) => _get(
        '/transactions/$id',
        (data) => TransactionDetail.fromJson(_entity(data, 'transaction')),
      );

  Future<Transaction> createTransaction(TransactionInput input) => _write(
        'POST',
        '/transactions',
        body: input.toJson(),
        touches: const {DataScope.transactions},
        parse: (data) => Transaction.fromJson(_entity(data, 'transaction')),
      );

  /// Saves an edit of [before], sending only the fields [input] changes —
  /// so a note or a category the form did not touch stays as it is.
  Future<Transaction> updateTransaction(
    Transaction before,
    TransactionInput input,
  ) =>
      _write(
        'PATCH',
        '/transactions/${before.id}',
        body: input.changesFrom(before),
        touches: const {DataScope.transactions},
        parse: (data) => Transaction.fromJson(_entity(data, 'transaction')),
      );

  /// Deletes the transaction. The parent of a linked pair takes its child
  /// with it ([TransactionDetail.deletesLinked]); a child leaves its parent.
  Future<void> deleteTransaction(int id) => _write(
        'DELETE',
        '/transactions/$id',
        touches: const {DataScope.transactions},
        deletes: (scope: DataScope.transactions, id: id),
        parse: (_) {},
      );

  // --- Finance categories ---------------------------------------------------

  Future<List<TxCategory>> fetchCategories() => _get(
        '/finance_categories',
        (data) => _listOf(data['categories'], TxCategory.fromJson),
      );

  /// One category with what a delete or a type change would touch.
  Future<CategoryUsage> fetchCategory(int id) => _get(
        '/finance_categories/$id',
        (data) => CategoryUsage.fromJson(_entity(data, 'category')),
      );

  /// A new category shows in the category lists and becomes a place a
  /// budget can go; nothing is filed under it yet.
  Future<TxCategory> createCategory(CategoryInput input) => _write(
        'POST',
        '/finance_categories',
        body: input.toJson(),
        touches: const {DataScope.categoryList},
        parse: (data) => TxCategory.fromJson(_entity(data, 'category')),
      );

  /// Sends only what changed from [before]. `kind_locked` means it got
  /// something filed under it since the form learnt its type could change.
  Future<TxCategory> updateCategory(TxCategory before, CategoryInput input) =>
      _write(
        'PATCH',
        '/finance_categories/${before.id}',
        body: input.changesFrom(before),
        touches: const {DataScope.categories},
        staleOn: const {
          'kind_locked': {DataScope.categoryList},
        },
        parse: (data) => TxCategory.fromJson(_entity(data, 'category')),
      );

  /// Deletes the category and its subcategories; their transactions and
  /// subscriptions stay, without a category, and their budgets go.
  Future<void> deleteCategory(int id) => _write(
        'DELETE',
        '/finance_categories/$id',
        touches: const {DataScope.categories},
        deletes: (scope: DataScope.categories, id: id),
        parse: (_) {},
      );

  // --- Budgets --------------------------------------------------------------

  Future<BudgetsBundle> fetchBudgets() =>
      _get('/budgets', (data) => BudgetsBundle.fromJson(data));

  Future<BudgetStatus> createBudget(BudgetInput input) => _write(
        'POST',
        '/budgets',
        body: input.toJson(),
        touches: const {DataScope.budgets},
        parse: (data) => BudgetStatus.fromJson(_entity(data, 'budget')),
      );

  Future<BudgetStatus> updateBudget(BudgetStatus before, BudgetInput input) =>
      _write(
        'PATCH',
        '/budgets/${before.id}',
        body: input.changesFrom(before),
        touches: const {DataScope.budgets},
        parse: (data) => BudgetStatus.fromJson(_entity(data, 'budget')),
      );

  Future<void> deleteBudget(int id) => _write(
        'DELETE',
        '/budgets/$id',
        touches: const {DataScope.budgets},
        deletes: (scope: DataScope.budgets, id: id),
        parse: (_) {},
      );

  // --- Subscriptions --------------------------------------------------------

  Future<SubscriptionsBundle> fetchSubscriptions() =>
      _get('/subscriptions', (data) => SubscriptionsBundle.fromJson(data));

  Future<Subscription> createSubscription(SubscriptionInput input) => _write(
        'POST',
        '/subscriptions',
        body: input.toJson(),
        touches: const {DataScope.subscriptions},
        parse: (data) => Subscription.fromJson(_entity(data, 'subscription')),
      );

  /// Sends only what changed from [before]; [accountCurrency] is the
  /// currency of the account it is charged to now (a move to another
  /// currency sends the amount along).
  Future<Subscription> updateSubscription(
    Subscription before,
    SubscriptionInput input, {
    required String accountCurrency,
  }) =>
      _write(
        'PATCH',
        '/subscriptions/${before.id}',
        body: input.changesFrom(before, accountCurrency: accountCurrency),
        touches: const {DataScope.subscriptions},
        parse: (data) => Subscription.fromJson(_entity(data, 'subscription')),
      );

  /// Pauses ([active] false) or resumes a subscription: a paused one is
  /// never due and cannot be charged.
  Future<Subscription> setSubscriptionActive(int id, {required bool active}) =>
      _write(
        'PATCH',
        '/subscriptions/$id',
        body: {'active': active},
        touches: const {DataScope.subscriptions},
        parse: (data) => Subscription.fromJson(_entity(data, 'subscription')),
      );

  /// Deletes the subscription; the payments recorded for it stay.
  Future<void> deleteSubscription(int id) => _write(
        'DELETE',
        '/subscriptions/$id',
        touches: const {DataScope.subscriptions},
        deletes: (scope: DataScope.subscriptions, id: id),
        parse: (_) {},
      );

  /// Records one payment: an expense on the subscription's account and
  /// category, dated [date] (by default the due date, or today when paid
  /// early), and the next due date one period on. Not safe to repeat: each
  /// call records one more payment. `not_chargeable` — it was paused or its
  /// date cleared elsewhere — refetches the subscriptions.
  Future<SubscriptionCharge> chargeSubscription(int id, {DateTime? date}) =>
      _write(
        'POST',
        '/subscriptions/$id/charge',
        body: date == null ? null : {'date': isoDate(date)},
        touches: const {DataScope.subscriptions, DataScope.transactions},
        staleOn: const {
          'not_chargeable': {DataScope.subscriptions},
        },
        parse: (data) => SubscriptionCharge.fromJson(data),
      );

  // --- Habits ---------------------------------------------------------------

  Future<HabitsBundle> fetchHabits() =>
      _get('/habits', (data) => HabitsBundle.fromJson(data));

  Future<Habit> fetchHabit(int id, {int days = 84}) => _get(
        '/habits/$id',
        (data) => Habit.fromJson(_entity(data, 'habit')),
        query: {'days': days},
      );

  /// Sets habit [id]'s log for [day] to [count] (`PUT /habits/:id/logs/:date`):
  /// the state the user asked for, not a flip, so the same request twice —
  /// a retry, a double tap, a screen that was out of date — lands on the same
  /// state. 0 clears the day; the server clamps a count above the target,
  /// and a weekly or monthly habit's day is simply done (see `loggedDay`).
  ///
  /// [day] is the date the server reported as today (`habit.today.date`,
  /// `today` of `/home`), never the device's: the two differ when the phone
  /// is in another time zone, or a screen was left open past midnight.
  ///
  /// `habit_archived` changes nothing, but says the habit was archived on
  /// the web or another device while this phone still lists it: every
  /// screen that lists it refetches and drops it, instead of refusing each
  /// tap until the next refresh.
  Future<HabitLogResult> setHabitLog(int id, DateTime day, {required int count}) =>
      _write(
        'PUT',
        '/habits/$id/logs/${isoDate(day)}',
        body: {'count': count < 0 ? 0 : count},
        touches: const {DataScope.habitLogs},
        staleOn: const {
          'habit_archived': {DataScope.habits},
        },
        parse: (data) => HabitLogResult.fromJson(data),
      );

  Future<Habit> createHabit(HabitInput input) => _write(
        'POST',
        '/habits',
        body: input.toJson(),
        touches: const {DataScope.habits},
        parse: (data) => Habit.fromJson(_entity(data, 'habit')),
      );

  Future<Habit> updateHabit(int id, HabitInput input) => _write(
        'PATCH',
        '/habits/$id',
        body: input.toJson(),
        touches: const {DataScope.habits},
        parse: (data) => Habit.fromJson(_entity(data, 'habit')),
      );

  Future<void> archiveHabit(int id) => _write(
        'PATCH',
        '/habits/$id/archive',
        touches: const {DataScope.habits},
        parse: (_) {},
      );

  // --- Goals ----------------------------------------------------------------

  Future<GoalsBundle> fetchGoals() =>
      _get('/goals', (data) => GoalsBundle.fromJson(data));

  Future<Goal> fetchGoal(int id) =>
      _get('/goals/$id', (data) => Goal.fromJson(_entity(data, 'goal')));

  Future<Goal> goalUpdateProgress(int id, {num? currentValue, num? delta}) =>
      _write(
        'PATCH',
        '/goals/$id/update_progress',
        body: _pruned({'current_value': currentValue, 'delta': delta}),
        touches: const {DataScope.goals},
        parse: (data) => Goal.fromJson(_entity(data, 'goal')),
      );

  Future<Goal> goalRecalculate(int id) => _write(
        'PATCH',
        '/goals/$id/recalculate',
        touches: const {DataScope.goals},
        parse: (data) => Goal.fromJson(_entity(data, 'goal')),
      );

  Future<Goal> createGoal(GoalInput input) => _write(
        'POST',
        '/goals',
        body: input.toJson(),
        touches: const {DataScope.goals},
        parse: (data) => Goal.fromJson(_entity(data, 'goal')),
      );

  Future<Goal> updateGoal(int id, GoalInput input) => _write(
        'PATCH',
        '/goals/$id',
        body: input.toJson(),
        touches: const {DataScope.goals},
        parse: (data) => Goal.fromJson(_entity(data, 'goal')),
      );

  Future<Goal> abandonGoal(int id) => _write(
        'PATCH',
        '/goals/$id',
        body: {'status': 'abandoned'},
        touches: const {DataScope.goals},
        parse: (data) => Goal.fromJson(_entity(data, 'goal')),
      );

  // --- Journal --------------------------------------------------------------

  Future<JournalBundle> fetchJournal({String range = '30d'}) => _get(
        '/journal_entries',
        (data) => JournalBundle.fromJson(data),
        query: {'range': range},
      );

  Future<JournalEntry> fetchJournalEntry(int id) => _get(
        '/journal_entries/$id',
        (data) => JournalEntry.fromJson(_entity(data, 'entry')),
      );

  Future<JournalEntry> createJournalEntry(JournalInput input) => _write(
        'POST',
        '/journal_entries',
        body: input.toJson(),
        touches: const {DataScope.journal},
        parse: (data) => JournalEntry.fromJson(_entity(data, 'entry')),
      );

  Future<JournalEntry> updateJournalEntry(int id, JournalInput input) =>
      _write(
        'PATCH',
        '/journal_entries/$id',
        body: input.toJson(),
        touches: const {DataScope.journal},
        parse: (data) => JournalEntry.fromJson(_entity(data, 'entry')),
      );

  Future<void> deleteJournalEntry(int id) => _write(
        'DELETE',
        '/journal_entries/$id',
        touches: const {DataScope.journal},
        deletes: (scope: DataScope.journal, id: id),
        parse: (_) {},
      );

  // --- Todos ----------------------------------------------------------------

  Future<TodosBundle> fetchTodos({
    String? filter,
    int? listId,
    String? priority,
  }) =>
      _get(
        '/todos',
        (data) => TodosBundle.fromJson(data),
        query: _pruned({
          'filter': filter,
          'list_id': listId,
          'priority': priority,
        }),
      );

  /// Marks todo [id] done, or not done (`PATCH /todos/:id/toggle` with an
  /// explicit `done`): the state the user asked for, so a screen that is
  /// out of date can never reopen a finished todo, and a retry is harmless.
  Future<Todo> setTodoDone(int id, {required bool done}) => _write(
        'PATCH',
        '/todos/$id/toggle',
        body: {'done': done},
        touches: const {DataScope.todos},
        parse: (data) => Todo.fromJson(_entity(data, 'todo')),
      );

  Future<Todo> createTodo(TodoInput input) => _write(
        'POST',
        '/todos',
        body: input.toJson(),
        touches: const {DataScope.todos},
        parse: (data) => Todo.fromJson(_entity(data, 'todo')),
      );

  Future<Todo> updateTodo(int id, TodoInput input) => _write(
        'PATCH',
        '/todos/$id',
        body: input.toJson(),
        touches: const {DataScope.todos},
        parse: (data) => Todo.fromJson(_entity(data, 'todo')),
      );

  // --- Events ---------------------------------------------------------------

  Future<List<Event>> fetchEvents({DateTime? from, DateTime? to}) => _get(
        '/events',
        (data) => _listOf(data['events'], Event.fromJson),
        query: _pruned({
          'from': from == null ? null : isoDate(from),
          'to': to == null ? null : isoDate(to),
        }),
      );

  // --- Quick capture --------------------------------------------------------

  /// One line of free text becomes a transaction, a habit check-in or a todo
  /// — or, for a line that names a day, nothing (an event suggestion, with
  /// `saved: false`). Until the answer says which, any of the three may have
  /// changed; an answer that says nothing was saved changed nothing; and a
  /// saved one that names no type this app knows (none at all, or one added
  /// to the server later) says no more than that, so all three refresh.
  ///
  /// [asTodo] saves the line as it is, as a todo — "save as a task instead"
  /// after an event suggestion — so only todos can change.
  Future<QuickCaptureResult> quickCapture(String text, {bool asTodo = false}) {
    final touches = asTodo ? const {DataScope.todos} : _quickCaptureTouches;
    return _write(
      'POST',
      '/quick_captures',
      body: {'text': text, if (asTodo) 'as': 'todo'},
      touches: touches,
      parse: (data) => QuickCaptureResult.fromJson(data),
      changed: (result) => !result.saved
          ? const <DataScope>{}
          : switch (result.capturedType) {
              'transaction' => const {DataScope.transactions},
              'habit_log' => const {DataScope.habitLogs},
              'todo' => const {DataScope.todos},
              _ => touches,
            },
    );
  }

  static const _quickCaptureTouches = {
    DataScope.transactions,
    DataScope.habitLogs,
    DataScope.todos,
  };

  // --- Plumbing -------------------------------------------------------------

  Future<T> _get<T>(
    String path,
    T Function(Map<String, dynamic> data) parse, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      return parse(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Sends a write and reports it to [_writes].
  ///
  /// [touches] is everything the write may change; [changed] narrows it once
  /// the response says what actually happened. When the outcome is unknown —
  /// no response, a 5xx, a body that does not parse — all of [touches] is
  /// reported, so the screens ask the server instead of trusting a guess. A
  /// 404 is reported too: the record is gone, and whatever still shows it
  /// must drop it. Only a rejected write (422) or a dead session (401)
  /// changed nothing. [deletes] is the record a delete removes, reported
  /// only once the server has confirmed it.
  ///
  /// [staleOn] names the refusals that prove the app's copy out of date, by
  /// their `code` (a habit archived elsewhere, say): nothing changed, but
  /// the scopes given for the code are reported, so every screen showing
  /// that data refetches it.
  Future<T> _write<T>(
    String method,
    String path, {
    Object? body,
    required Set<DataScope> touches,
    DeletedRecord? deletes,
    Map<String, Set<DataScope>> staleOn = const {},
    required T Function(Map<String, dynamic> data) parse,
    Set<DataScope> Function(T result)? changed,
  }) async {
    // A write that touches nothing the app reads (language, theme) is not
    // reported, so it never holds back another write's refresh.
    final writes = touches.isEmpty ? null : _writes;
    writes?.writeStarted();
    var reported = touches;
    DeletedRecord? deleted;
    try {
      final res = await _dio.request<Object?>(
        path,
        data: body,
        options: Options(method: method),
      );
      // A 204 (delete) has no body; every other write answers with a map.
      final data = res.data;
      final result = parse(
          data == null || data == '' ? const <String, dynamic>{} : _asMap(data));
      reported = changed?.call(result) ?? touches;
      deleted = deletes;
      return result;
    } on DioException catch (e) {
      final error = ApiException.fromDio(e);
      if (error.isUnauthorized) {
        reported = const {};
      } else if (error.isValidation) {
        reported = staleOn[error.code] ?? const {};
      }
      throw error;
    } finally {
      writes?.writeFinished(reported, deleted: deleted);
    }
  }

  static Map<String, dynamic> _asMap(Object? data) =>
      data is Map<String, dynamic>
          ? data
          : (data as Map).cast<String, dynamic>();

  /// Unwrap `{entity: {…}}` envelopes, tolerating a bare object.
  static Map<String, dynamic> _entity(Map<String, dynamic> data, String key) =>
      (data[key] as Map<String, dynamic>?) ?? data;

  /// Drop null entries — only non-null query params / body fields are sent.
  static Map<String, dynamic> _pruned(Map<String, Object?> params) {
    final out = <String, dynamic>{};
    params.forEach((key, value) {
      if (value != null) out[key] = value;
    });
    return out;
  }

  static List<T> _listOf<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) =>
      ((raw as List?) ?? const [])
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
}
