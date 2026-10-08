import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A scripted Meridian API behind a real [Dio], so tests run the real
/// repository, `DataSync` and read models end to end — only the network is
/// fake.
///
/// Every GET read model has a small but complete default payload (habit 7,
/// goal 3, journal entry 20, …); writes answer as the server does. Tests can
/// replace a route ([on]), make it fail ([fail], [failNetwork]) or hold its
/// answer until released ([hold]).
class FakeApi implements HttpClientAdapter {
  FakeApi() {
    dio = Dio(BaseOptions(baseUrl: 'http://meridian.test/api/v1'))
      ..httpClientAdapter = this;
  }

  late final Dio dio;

  /// Every request so far, as "METHOD /path" (no `/api/v1`, no query).
  final requests = <String>[];

  /// The body of every request that had one, as "METHOD /path" → body, in
  /// order (the latest last).
  final bodies = <(String, Object?)>[];

  /// The bodies sent to [key] so far.
  List<Object?> bodiesOf(String key) => [
        for (final (k, body) in bodies)
          if (k == key) body,
      ];

  final _routes = <String, _Route>{};
  final _holds = <String, Completer<void>>{};
  final _blips = <String>{};

  /// The GET paths requested so far, in order.
  List<String> get gets => [
        for (final r in requests)
          if (r.startsWith('GET ')) r.substring(4),
      ];

  void clearLog() => requests.clear();

  /// Answers [key] ("METHOD /path") with [body] and [status].
  void on(String key, Object? body, {int status = 200}) =>
      _routes[key] = _Route(body: body, status: status);

  /// Answers [key] with whatever [respond] builds from the request (its
  /// query parameters, say).
  void onRequest(String key, Object? Function(RequestOptions request) respond) =>
      _routes[key] = _Route(respond: respond);

  /// Answers [key] with an HTTP error status (422 carries field errors).
  void fail(String key, int status) => _routes[key] = _Route(
        status: status,
        body: status == 422
            ? {
                'errors': {
                  'base': ['invalid'],
                },
              }
            : {'error': 'failed'},
      );

  /// Makes [key] fail without a response, like an unreachable server.
  void failNetwork(String key) => _routes[key] = const _Route(network: true);

  /// Makes [key] time out: by default after the request went out (no answer
  /// in time — the server may have acted on it), or, with
  /// [DioExceptionType.connectionTimeout], before it could be sent.
  void timeOut(
    String key, {
    DioExceptionType type = DioExceptionType.receiveTimeout,
  }) =>
      _routes[key] = _Route(timeout: type);

  /// Makes only the next request to [key] fail without a response — a
  /// network blip; the ones after it are answered as before.
  void blip(String key) => _blips.add(key);

  /// Holds the answer to [key] until [release] — a request in flight.
  void hold(String key) => _holds[key] = Completer<void>();

  void release(String key) => _holds.remove(key)?.complete();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api/v1', '');
    final key = '${options.method} $path';
    requests.add(key);
    if (options.data != null) bodies.add((key, _decoded(options.data)));
    final held = _holds[key];
    if (held != null) await held.future;

    final route = _routes[key] ?? _defaults[key] ?? _patterned(key);
    if (route == null) {
      return _json({'error': 'not_found'}, 404);
    }
    if (route.network || _blips.remove(key)) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'unreachable',
      );
    }
    if (route.timeout case final type?) {
      throw DioException(requestOptions: options, type: type);
    }
    final respond = route.respond;
    return _json(respond == null ? route.body : respond(options), route.status);
  }

  @override
  void close({bool force = false}) {}

  static Object? _decoded(Object? data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  static ResponseBody _json(Object? body, int status) {
    if (status == 204) return ResponseBody.fromString('', 204);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _Route {
  final Object? body;
  final int status;
  final bool network;
  final DioExceptionType? timeout;
  final Object? Function(RequestOptions request)? respond;

  const _Route({
    this.body,
    this.status = 200,
    this.network = false,
    this.timeout,
    this.respond,
  });
}

// --- Default payloads ----------------------------------------------------------

Map<String, dynamic> habitJson({
  int id = 7,
  String name = 'Koşu',
  int targetCount = 1,
  bool completed = false,
  int count = 0,
  int streak = 2,
}) =>
    {
      'id': id,
      'name': name,
      'description': '',
      'frequency': 'daily',
      'target_count': targetCount,
      'color': '#D4A853',
      'goal_id': null,
      'current_streak': streak,
      'longest_streak': 9,
      'completion_rate_30d': 40.0,
      'today': {'date': '2026-10-04', 'completed': completed, 'count': count},
      'chain': [
        // A partial day of a multi-count habit: the server sends counts.
        {'date': '2026-10-03', 'status': 'partial', 'completed': 1, 'possible': 3},
        {'date': '2026-10-04', 'status': 'today_pending'},
      ],
    };

Map<String, dynamic> habitsMeta({int completedToday = 0, int totalActive = 2}) => {
      'completed_today': completedToday,
      'total_active': totalActive,
      'perfect_day': {
        'chain': [
          {'date': '2026-10-04', 'status': 'missed'},
        ],
        'current_streak': 0,
        'longest_streak': 3,
      },
    };

Map<String, dynamic> habitsJson({bool habit7Done = false}) => {
      'habits': [
        habitJson(completed: habit7Done, count: habit7Done ? 1 : 0),
        habitJson(id: 8, name: 'Su', targetCount: 3, count: 1),
      ],
      'meta': habitsMeta(completedToday: habit7Done ? 1 : 0),
    };

/// The answer to `PUT /habits/:id/logs/:date` for Koşu (7) done or not.
Map<String, dynamic> logJson({bool done = true}) => {
      'habit': habitJson(completed: done, count: done ? 1 : 0, streak: 3),
      'meta': habitsMeta(completedToday: done ? 1 : 0),
      'log': {'date': '2026-10-04', 'count': done ? 1 : 0, 'completed': done},
    };

/// What the server answers `PUT /habits/:id/logs/:date` with for the
/// default habits — Koşu (7, target 1) and Su (8, target 3) — set to the
/// count sent, as `Habit#set_log_count!` stores it.
Map<String, dynamic> logAnswer(int id, String date, int count) {
  final target = id == 8 ? 3 : 1;
  final stored = count.clamp(0, target);
  final done = stored >= target;
  return {
    'habit': {
      ...habitJson(
        id: id,
        name: id == 8 ? 'Su' : 'Koşu',
        targetCount: target,
        completed: done,
        count: stored,
        streak: done ? 3 : 2,
      ),
      'today': {'date': date, 'completed': done, 'count': stored},
    },
    'meta': habitsMeta(completedToday: done ? 1 : 0),
    'log': {'date': date, 'count': stored, 'completed': done},
  };
}

Map<String, dynamic> todoJson({int id = 39, String status = 'pending'}) => {
      'id': id,
      'title': 'Faturayı öde',
      'body': null,
      'status': status,
      'priority': 'high',
      'due_at': '2026-10-04T18:00:00.000+03:00',
      'due_date': '2026-10-04',
      'due_time': '18:00',
      'completed_at': status == 'done' ? '2026-10-04T12:30:00.000+03:00' : null,
      'overdue': status != 'done',
      'position': 1,
      'todo_list': null,
      'subtask_count': 0,
    };

/// The answer to `PATCH /todos/:id/toggle`: the old top-level keys and the
/// whole todo (G1.2).
Map<String, dynamic> todoToggleJson({int id = 39, required bool done}) {
  final todo = todoJson(id: id, status: done ? 'done' : 'pending');
  return {
    'id': id,
    'status': todo['status'],
    'completed_at': todo['completed_at'],
    'todo': todo,
  };
}

Map<String, dynamic> homeJson({
  bool habit7Done = false,
  List<Map<String, dynamic>>? todos,
  num goalProgress = 40.0,
}) =>
    {
      'today': '2026-10-04',
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'month_net_cents': 125000,
      'active_streaks': 1,
      'open_todos': 1,
      'overdue_count': 1,
      'today_events_count': 0,
      'habit_completion_pct': 30,
      'spending_7d': [
        {'date': '2026-10-04', 'cents': 2500},
      ],
      'today_habits': [
        {
          'id': 7,
          'name': 'Koşu',
          'color': '#D4A853',
          'target_count': 1,
          'completed_today': habit7Done,
          'today_count': habit7Done ? 1 : 0,
          'current_streak': 2,
        },
        {
          'id': 8,
          'name': 'Su',
          'color': '#6B8FA0',
          'target_count': 3,
          'completed_today': false,
          'today_count': 1,
          'current_streak': 0,
        },
      ],
      'upcoming_todos': todos ?? [todoJson()],
      'today_events': const [],
      'active_goals': [
        {
          'id': 3,
          'name': 'Kitap',
          'color': '#6B8E5A',
          'progress_percent': goalProgress,
        },
      ],
      'perfect_day': {
        'chain': [
          {'date': '2026-10-04', 'status': 'missed'},
        ],
        'current_streak': 0,
      },
    };

Map<String, dynamic> goalJson({int id = 3, num current = 40}) => {
      'id': id,
      'name': 'Kitap',
      'description': '',
      'target_type': 'custom',
      'status': 'active',
      'color': '#6B8E5A',
      'unit': 'kitap',
      'deadline': null,
      'days_remaining': null,
      'deadline_badge': null,
      'target_value': 100.0,
      'current_value': current,
      'progress_percent': current,
      'related': null,
    };

Map<String, dynamic> transactionJson({int id = 316}) => {
      'id': id,
      'kind': 'expense',
      'amount_cents': 13874,
      'date': '2026-10-04',
      'description': 'Kahve',
      'note': null,
      'account': {
        'id': 1,
        'name': 'Cüzdan',
        'color': '#D4A574',
        'currency': 'TRY',
        'subunit_to_unit': 100,
      },
      'category': null,
      'related_account': null,
    };

/// GET /transactions/:id: the transaction and the other row of its linked
/// pair — none by default.
Map<String, dynamic> transactionDetailJson({
  int id = 316,
  int? parentId,
  Map<String, dynamic>? linked,
}) =>
    {
      ...transactionJson(id: id),
      'parent_transaction_id': parentId,
      'linked': linked,
    };

/// The other row of a linked pair, as GET /transactions/:id embeds it: by
/// default the 2 gr of gold bought with the cash expense, its child.
Map<String, dynamic> linkedJson({
  int id = 317,
  String kind = 'income',
  int amount = 2,
  String relation = 'child',
}) =>
    {
      'id': id,
      'kind': kind,
      'amount_cents': amount,
      'date': '2026-10-02',
      'description': 'Altın alımı',
      'account': {
        'id': 3,
        'name': 'Altın',
        'color': '#B8860B',
        'currency': 'GAU',
        'subunit_to_unit': 1,
      },
      'relation': relation,
    };

/// An account as the server lists it (GET /accounts).
Map<String, dynamic> accountJson({
  int id = 1,
  String name = 'Cüzdan',
  String type = 'cash',
  String currency = 'TRY',
  int subunit = 100,
  int balance = 500000,
  int initial = 0,
  String color = '#D4A574',
  bool archived = false,
}) =>
    {
      'id': id,
      'name': name,
      'account_type': type,
      'currency': currency,
      'subunit_to_unit': subunit,
      'color': color,
      'initial_balance_cents': initial,
      'balance_cents': balance,
      'archived': archived,
      'archived_at': archived ? '2026-10-01T12:00:00.000+03:00' : null,
    };

/// GET /accounts/:id: the account and what is recorded on it.
Map<String, dynamic> accountDetailJson({
  int id = 1,
  String name = 'Cüzdan',
  bool archived = false,
  int transactions = 0,
  int incoming = 0,
  int subscriptions = 0,
  int goals = 0,
}) =>
    {
      ...accountJson(id: id, name: name, archived: archived),
      'transactions_count': transactions,
      'incoming_transfers_count': incoming,
      'subscriptions_count': subscriptions,
      'linked_goals_count': goals,
      'deletable': transactions + incoming == 0,
      'currency_editable': transactions + incoming + subscriptions == 0,
    };

Map<String, dynamic> currenciesJson() => {
      'currencies': [
        {'code': 'TRY', 'name': 'Türk lirası', 'symbol': '₺', 'symbol_first': true, 'subunit_to_unit': 100, 'decimal_places': 2},
        {'code': 'USD', 'name': 'ABD doları', 'symbol': '\$', 'symbol_first': true, 'subunit_to_unit': 100, 'decimal_places': 2},
        {'code': 'EUR', 'name': 'Euro', 'symbol': '€', 'symbol_first': true, 'subunit_to_unit': 100, 'decimal_places': 2},
        {'code': 'GBP', 'name': 'İngiliz sterlini', 'symbol': '£', 'symbol_first': true, 'subunit_to_unit': 100, 'decimal_places': 2},
        {'code': 'GAU', 'name': 'Gram altın', 'symbol': 'gr', 'symbol_first': false, 'subunit_to_unit': 1, 'decimal_places': 0},
      ],
      'default_currency': 'TRY',
    };

/// A finance category (the category object).
Map<String, dynamic> categoryJson({
  int id = 5,
  String name = 'Market',
  String kind = 'expense',
  int? parentId,
  int position = 0,
  String color = '#D4915A',
}) =>
    {
      'id': id,
      'name': name,
      'kind': kind,
      'color': color,
      'parent_id': parentId,
      'position': position,
    };

/// GET /finance_categories/:id: the category and what a delete touches.
Map<String, dynamic> categoryUsageJson({
  int id = 5,
  String name = 'Market',
  String kind = 'expense',
  int children = 0,
  int transactions = 0,
  int subscriptions = 0,
  int budgets = 0,
}) =>
    {
      ...categoryJson(id: id, name: name, kind: kind),
      'children_count': children,
      'transactions_count': transactions,
      'subscriptions_count': subscriptions,
      'budgets_count': budgets,
      'budget_id': budgets > 0 ? 2 : null,
      'kind_editable': children + transactions + subscriptions + budgets == 0,
    };

/// The budget object.
Map<String, dynamic> budgetJson({
  int id = 2,
  int categoryId = 5,
  String categoryName = 'Market',
  int limit = 300000,
  int spent = 66100,
}) =>
    {
      'id': id,
      'finance_category_id': categoryId,
      'category': {'id': categoryId, 'name': categoryName, 'color': '#D4915A'},
      'color': '#D4915A',
      'custom_color': null,
      'limit_cents': limit,
      'spent_cents': spent,
      'remaining_cents': limit - spent,
      'over_by_cents': spent > limit ? spent - limit : 0,
      'percent_used': limit == 0 ? 0 : (spent * 100 / limit).round(),
      'bar_percent': limit == 0 ? 0 : (spent * 100 / limit).round().clamp(0, 100),
      'pace_percent': 13,
      'projected_cents': spent * 7,
      'state': spent > limit ? 'over' : 'under',
    };

Map<String, dynamic> budgetsJson({
  List<Map<String, dynamic>>? budgets,
  List<int> budgetable = const [],
}) =>
    {
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'as_of': '2026-10-04',
      'budgets': budgets ?? [budgetJson()],
      'budgetable_category_ids': budgetable,
    };

/// The subscription object.
Map<String, dynamic> subscriptionJson({
  int id = 6,
  String name = 'Netflix',
  int amount = 22999,
  String frequency = 'monthly',
  String? next = '2026-10-15',
  bool active = true,
  int accountId = 1,
  Map<String, dynamic>? category,
}) =>
    {
      'id': id,
      'name': name,
      'vendor': null,
      'amount_cents': amount,
      'frequency': frequency,
      'next_charge_on': next,
      'start_date': '2026-01-15',
      'end_date': null,
      'active': active,
      'color': '#B8860B',
      'note': null,
      'monthly_amount_cents': amount,
      'yearly_amount_cents': amount * 12,
      'account': {
        'id': accountId,
        'name': 'Cüzdan',
        'color': '#D4A574',
        'currency': 'TRY',
        'subunit_to_unit': 100,
      },
      'category': category,
    };

Map<String, dynamic> subscriptionsJson({
  List<Map<String, dynamic>>? active,
  List<Map<String, dynamic>> inactive = const [],
}) =>
    {
      'active': active ?? [subscriptionJson()],
      'inactive': inactive,
      'totals': [
        {'currency': 'TRY', 'subunit_to_unit': 100, 'monthly_cents': 22999, 'yearly_cents': 275988},
      ],
    };

Map<String, dynamic> journalEntryJson({int id = 20}) => {
      'id': id,
      'date': '2026-10-04',
      'title': 'Sakin bir gün',
      'body_plain': 'Kısa bir not.',
      'mood': 'good',
      'mood_emoji': '🙂',
      'energy_level': 3,
      'weather': null,
      'tags': const [],
      'has_gratitude': false,
      'created_at': '2026-10-04T19:00:00.000Z',
      'body_html': '<p>Kısa bir not.</p>',
      'gratitude': null,
    };

Map<String, dynamic> userJson({String name = 'Demo'}) => {
      'id': 9,
      'name': name,
      'display_name': name,
      'initials': name.substring(0, 1),
      'email': 'demo@meridian.local',
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'locale': 'tr',
      'timezone': 'Istanbul',
      'timezone_iana': 'Europe/Istanbul',
      'utc_offset': '+03:00',
      'theme_preference': 'dark',
    };

/// A quick capture saved as a todo (G1.5).
Map<String, dynamic> captureTodoJson({int id = 40, String title = 'süt al'}) => {
      'saved': true,
      'captured_type': 'todo',
      'record_id': id,
      'summary': title,
      'message': 'Görev olarak yakalandı: $title',
      'record': {...todoJson(id: id), 'title': title, 'due_at': null},
    };

/// Answers for routes with ids or dates in the path that no test set.
_Route? _patterned(String key) {
  final log = RegExp(r'^PUT /habits/(\d+)/logs/(\d{4}-\d{2}-\d{2})$').firstMatch(key);
  if (log != null) {
    final id = int.parse(log.group(1)!);
    if (id != 7 && id != 8) return null;
    return _Route(respond: (request) {
      final body = request.data is String
          ? jsonDecode(request.data as String)
          : request.data;
      final count = (body as Map)['count'] as int? ?? 0;
      return logAnswer(id, log.group(2)!, count);
    });
  }
  final toggle = RegExp(r'^PATCH /todos/(\d+)/toggle$').firstMatch(key);
  if (toggle != null) {
    final id = int.parse(toggle.group(1)!);
    return _Route(respond: (request) {
      final body = request.data is String
          ? jsonDecode(request.data as String)
          : request.data;
      return todoToggleJson(id: id, done: (body as Map)['done'] == true);
    });
  }
  return null;
}

final Map<String, _Route> _defaults = {
  // Reads.
  'GET /me': _Route(body: {'user': userJson()}),
  'GET /home': _Route(body: homeJson()),
  'GET /habits': _Route(body: habitsJson()),
  'GET /habits/7': _Route(body: {'habit': habitJson()}),
  'GET /goals': _Route(body: {
    'active': [goalJson()],
    'achieved': const [],
    'abandoned': const [],
  }),
  'GET /goals/3': _Route(body: {'goal': goalJson()}),
  'GET /accounts': _Route(body: {
    'accounts': [accountJson()],
  }),
  'GET /accounts/1': _Route(body: {'account': accountDetailJson()}),
  'GET /currencies': _Route(body: currenciesJson()),
  'GET /finance/dashboard': const _Route(body: {
    'currency': 'TRY',
    'subunit_to_unit': 100,
    'month': {'income_cents': 0, 'expense_cents': 0, 'net_cents': 0},
    'year': {'income_cents': 0, 'expense_cents': 0},
    'six_month_series': {'labels': [], 'income_cents': [], 'expense_cents': []},
    'pie': [],
    'budgets': [],
    'upcoming_subscriptions': [],
    'recent_transactions': [],
  }),
  'GET /finance_categories': _Route(body: {
    'categories': [categoryJson()],
  }),
  'GET /finance_categories/5': _Route(body: {'category': categoryUsageJson()}),
  'GET /budgets': _Route(body: budgetsJson()),
  'GET /subscriptions': _Route(body: subscriptionsJson()),
  'GET /transactions': _Route(body: {
    'transactions': [transactionJson()],
    'meta': const {
      'total_count': 1,
      'page': 1,
      'page_limit': 50,
      'filtered_income_cents': 0,
      'filtered_expense_cents': 13874,
    },
  }),
  'GET /transactions/316':
      _Route(body: {'transaction': transactionDetailJson()}),
  'GET /todos': _Route(body: {
    'todos': [todoJson()],
    'meta': const {'open_count': 1, 'overdue_count': 1},
  }),
  'GET /events': const _Route(body: {'events': []}),
  'GET /journal_entries': _Route(body: {
    'entries': [journalEntryJson()],
    'meta': const {
      'entries_count': 1,
      'journal_streak': 1,
      'mood_counts': {'great': 0, 'good': 1, 'neutral': 0, 'bad': 0, 'awful': 0},
      'range': '30d',
    },
  }),
  'GET /journal_entries/20': _Route(body: {'entry': journalEntryJson()}),
  // Writes.
  'PATCH /me': _Route(body: {'user': userJson()}),
  'POST /accounts': _Route(
      body: {'account': accountJson(id: 2, name: 'Banka', type: 'bank')},
      status: 201),
  'PATCH /accounts/1': _Route(body: {'account': accountJson()}),
  'PATCH /accounts/1/archive': _Route(body: {'account': accountJson(archived: true)}),
  'PATCH /accounts/1/unarchive': _Route(body: {'account': accountJson()}),
  'DELETE /accounts/1': const _Route(status: 204),
  'POST /finance_categories': _Route(
      body: {'category': categoryJson(id: 9, name: 'Yeni')}, status: 201),
  'PATCH /finance_categories/5': _Route(body: {'category': categoryJson()}),
  'DELETE /finance_categories/5': const _Route(status: 204),
  'POST /budgets': _Route(body: {'budget': budgetJson(id: 3)}, status: 201),
  'PATCH /budgets/2': _Route(body: {'budget': budgetJson()}),
  'DELETE /budgets/2': const _Route(status: 204),
  'POST /subscriptions': _Route(
      body: {'subscription': subscriptionJson(id: 7)}, status: 201),
  'PATCH /subscriptions/6': _Route(body: {'subscription': subscriptionJson()}),
  'DELETE /subscriptions/6': const _Route(status: 204),
  'POST /subscriptions/6/charge': _Route(body: {
    'subscription': subscriptionJson(next: '2026-11-15'),
    'transaction': {...transactionJson(id: 401), 'description': 'Netflix', 'amount_cents': 22999},
  }, status: 201),
  'POST /transactions': _Route(body: transactionJson(id: 400), status: 201),
  'PATCH /transactions/316': _Route(body: transactionJson()),
  'DELETE /transactions/316': const _Route(status: 204),
  'POST /habits': _Route(body: {'habit': habitJson(id: 9, name: 'Yeni')}, status: 201),
  'PATCH /habits/7': _Route(body: {'habit': habitJson()}),
  'PATCH /habits/7/archive': _Route(body: {'habit': habitJson()}),
  'PATCH /goals/3/update_progress': _Route(body: {'goal': goalJson(current: 41)}),
  'PATCH /goals/3/recalculate': _Route(body: {'goal': goalJson()}),
  'POST /goals': _Route(body: {'goal': goalJson(id: 4)}, status: 201),
  'PATCH /goals/3': _Route(body: {'goal': goalJson()}),
  'POST /journal_entries': _Route(body: {'entry': journalEntryJson(id: 21)}, status: 201),
  'PATCH /journal_entries/20': _Route(body: {'entry': journalEntryJson()}),
  'DELETE /journal_entries/20': const _Route(status: 204),
  'POST /todos': _Route(body: {'todo': todoJson(id: 40)}, status: 201),
  'PATCH /todos/39': _Route(body: {'todo': todoJson()}),
  'POST /quick_captures': _Route(body: captureTodoJson(), status: 201),
};
