import 'package:dio/dio.dart';

import '../core/api.dart';
import '../models/account.dart';
import '../models/date_utils.dart';
import '../models/event.dart';
import '../models/finance_dashboard.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/home.dart';
import '../models/journal.dart';
import '../models/quick_capture.dart';
import '../models/todo.dart';
import '../models/transaction.dart';
import '../models/user.dart';

/// One async method per Meridian endpoint. Every [DioException] is normalized
/// through [ApiException.fromDio]; models never see raw dio errors.
class MeridianRepository {
  MeridianRepository(this._dio);

  final Dio _dio;

  // --- Me -------------------------------------------------------------------

  /// The two preferences the phone owns: UI language and theme. Sending them
  /// to the server keeps the choice with the account, so the web app and a
  /// reinstall pick it up too.
  Future<User> updateMe({String? locale, String? themePreference}) => _send(
        'PATCH',
        '/me',
        body: _pruned({
          'locale': locale,
          'theme_preference': themePreference,
        }),
        parse: (data) => User.fromJson(_entity(data, 'user')),
      );

  // --- Home -----------------------------------------------------------------

  Future<HomeSummary> fetchHome() =>
      _get('/home', (data) => HomeSummary.fromJson(data));

  // --- Accounts -------------------------------------------------------------

  Future<List<Account>> fetchAccounts() => _get(
        '/accounts',
        (data) => _listOf(data['accounts'], Account.fromJson),
      );

  // --- Finance --------------------------------------------------------------

  Future<FinanceDashboard> fetchFinanceDashboard({String? range}) => _get(
        '/finance/dashboard',
        (data) => FinanceDashboard.fromJson(data),
        query: _pruned({'range': range}),
      );

  Future<TransactionsPage> fetchTransactions({
    String? kind,
    int? accountId,
    int? categoryId,
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
          'category_id': categoryId,
          'from': from == null ? null : isoDate(from),
          'to': to == null ? null : isoDate(to),
          'page': page,
        }),
      );

  Future<Transaction> createTransaction(TransactionInput input) => _send(
        'POST',
        '/transactions',
        body: input.toJson(),
        parse: (data) => Transaction.fromJson(_entity(data, 'transaction')),
      );

  Future<Transaction> updateTransaction(int id, TransactionInput input) => _send(
        'PATCH',
        '/transactions/$id',
        body: input.toJson(),
        parse: (data) => Transaction.fromJson(_entity(data, 'transaction')),
      );

  Future<void> deleteTransaction(int id) => _delete('/transactions/$id');

  Future<List<TxCategory>> fetchCategories() => _get(
        '/finance_categories',
        (data) => _listOf(data['categories'], TxCategory.fromJson),
      );

  // --- Habits ---------------------------------------------------------------

  Future<HabitsBundle> fetchHabits() =>
      _get('/habits', (data) => HabitsBundle.fromJson(data));

  Future<Habit> fetchHabit(int id, {int days = 84}) => _get(
        '/habits/$id',
        (data) => Habit.fromJson(_entity(data, 'habit')),
        query: {'days': days},
      );

  Future<ToggleResult> toggleHabitToday(int id, {int? delta}) => _send(
        'PATCH',
        '/habits/$id/toggle_today',
        body: _pruned({'delta': delta}),
        parse: (data) => ToggleResult.fromJson(data),
      );

  Future<Habit> createHabit(HabitInput input) => _send(
        'POST',
        '/habits',
        body: input.toJson(),
        parse: (data) => Habit.fromJson(_entity(data, 'habit')),
      );

  Future<Habit> updateHabit(int id, HabitInput input) => _send(
        'PATCH',
        '/habits/$id',
        body: input.toJson(),
        parse: (data) => Habit.fromJson(_entity(data, 'habit')),
      );

  Future<void> archiveHabit(int id) =>
      _send('PATCH', '/habits/$id/archive', parse: (_) {});

  // --- Goals ----------------------------------------------------------------

  Future<GoalsBundle> fetchGoals() =>
      _get('/goals', (data) => GoalsBundle.fromJson(data));

  Future<Goal> fetchGoal(int id) =>
      _get('/goals/$id', (data) => Goal.fromJson(_entity(data, 'goal')));

  Future<Goal> goalUpdateProgress(int id, {num? currentValue, num? delta}) =>
      _send(
        'PATCH',
        '/goals/$id/update_progress',
        body: _pruned({'current_value': currentValue, 'delta': delta}),
        parse: (data) => Goal.fromJson(_entity(data, 'goal')),
      );

  Future<Goal> goalRecalculate(int id) => _send(
        'PATCH',
        '/goals/$id/recalculate',
        parse: (data) => Goal.fromJson(_entity(data, 'goal')),
      );

  Future<Goal> createGoal(GoalInput input) => _send(
        'POST',
        '/goals',
        body: input.toJson(),
        parse: (data) => Goal.fromJson(_entity(data, 'goal')),
      );

  Future<Goal> updateGoal(int id, GoalInput input) => _send(
        'PATCH',
        '/goals/$id',
        body: input.toJson(),
        parse: (data) => Goal.fromJson(_entity(data, 'goal')),
      );

  Future<Goal> abandonGoal(int id) => _send(
        'PATCH',
        '/goals/$id',
        body: {'status': 'abandoned'},
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

  Future<JournalEntry> createJournalEntry(JournalInput input) => _send(
        'POST',
        '/journal_entries',
        body: input.toJson(),
        parse: (data) => JournalEntry.fromJson(_entity(data, 'entry')),
      );

  Future<JournalEntry> updateJournalEntry(int id, JournalInput input) => _send(
        'PATCH',
        '/journal_entries/$id',
        body: input.toJson(),
        parse: (data) => JournalEntry.fromJson(_entity(data, 'entry')),
      );

  Future<void> deleteJournalEntry(int id) => _delete('/journal_entries/$id');

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

  Future<Todo> toggleTodo(int id) => _send(
        'PATCH',
        '/todos/$id/toggle',
        parse: (data) => Todo.fromToggle(_entity(data, 'todo')),
      );

  Future<Todo> createTodo(TodoInput input) => _send(
        'POST',
        '/todos',
        body: input.toJson(),
        parse: (data) => Todo.fromJson(_entity(data, 'todo')),
      );

  Future<Todo> updateTodo(int id, TodoInput input) => _send(
        'PATCH',
        '/todos/$id',
        body: input.toJson(),
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

  Future<QuickCaptureResult> quickCapture(String text) => _send(
        'POST',
        '/quick_captures',
        body: {'text': text},
        parse: (data) => QuickCaptureResult.fromJson(data),
      );

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

  Future<T> _send<T>(
    String method,
    String path, {
    Object? body,
    required T Function(Map<String, dynamic> data) parse,
  }) async {
    try {
      final res = await _dio.request(
        path,
        data: body,
        options: Options(method: method),
      );
      return parse(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> _delete(String path) async {
    try {
      await _dio.delete(path);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
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
