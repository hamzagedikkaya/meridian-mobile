import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:meridian_mobile/core/turkish_case.dart';

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

  /// Every route answered by default ("METHOD /path"), plus one example of
  /// each patterned route — what the live suite (test/live) holds up
  /// against the real server's answers.
  static Iterable<String> get defaultRoutes => [
        ..._defaults.keys,
        'PUT /habits/7/logs/2026-10-04',
        'PATCH /todos/39/toggle',
      ];

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
      'archived': false,
      'archived_at': null,
      'created_at': '2026-09-01T10:00:00.000+03:00',
      'start_date': '2026-09-01',
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

/// GET /habits/:id: the habit object and what an archive or a delete would
/// touch (contract §5).
Map<String, dynamic> habitDetailJson({
  int id = 7,
  String name = 'Koşu',
  int logged = 12,
  int completedDays = 10,
  List<Map<String, dynamic>> trackedBy = const [],
}) =>
    {
      ...habitJson(id: id, name: name),
      'logged_days_count': logged,
      'completed_days_count': completedDays,
      'tracked_by_goals': trackedBy,
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
      'goal_id': null,
      'todo_list': null,
      'subtask_count': 0,
    };

/// A todo list (contract §8.1).
Map<String, dynamic> todoListJson({
  int id = 5,
  String name = 'Ev',
  String color = '#6B8E5A',
  int open = 1,
  int total = 2,
}) =>
    {
      'id': id,
      'name': name,
      'color': color,
      'position': 0,
      'archived': false,
      'archived_at': null,
      'open_count': open,
      'todos_count': total,
    };

/// An event (contract §10.1): a one-off by default, or a weekly series
/// ([recurring]); [full] adds what `GET /events/:id` carries.
Map<String, dynamic> eventJson({
  int id = 12,
  String title = 'Yoga',
  String start = '2026-10-04T18:00:00.000+03:00',
  String? end = '2026-10-04T19:00:00.000+03:00',
  bool allDay = false,
  bool recurring = false,
  List<String>? occurrences,
  bool full = false,
}) =>
    {
      'id': id,
      'title': title,
      'start_at': start,
      'end_at': end,
      'all_day': allDay,
      'color': '#6B8E5A',
      'event_type': 'health',
      'location': 'Stüdyo',
      'duration_minutes': end == null ? null : 60,
      'recurring': recurring,
      if (full) 'description': 'Mat getir',
      if (full)
        'recurrence_rule':
            recurring ? 'FREQ=WEEKLY;UNTIL=20261231T205959Z' : null,
      'occurrences': ?occurrences,
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
      'progress_source': 'manual',
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

/// A journal entry as `GET /journal_entries` lists it: `body_plain` is a
/// preview there, and the full entry's keys are absent (contract §7.1).
Map<String, dynamic> journalListItemJson({int id = 20}) => {
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
      'created_at': '2026-10-04T19:00:00.000+03:00',
    };

/// The full journal entry (`GET /journal_entries/:id`, `POST`, `PATCH`):
/// the whole body as plain text and as HTML, and whether it is plain.
Map<String, dynamic> journalEntryJson({int id = 20}) => {
      ...journalListItemJson(id: id),
      'body_html': '<div class="trix-content">\n  <div>Kısa bir not.</div>\n</div>\n',
      'body_text': 'Kısa bir not.',
      'body_format': 'plain',
      'body_formatting': const <String>[],
      'gratitude': null,
      'updated_at': '2026-10-04T19:00:00.000+03:00',
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
      'weekly_review_day': 0,
    };

/// GET /me/options, cut to a few zones: two that read UTC+03:00 now, one
/// that does not, and London (UTC+01:00 in summer).
Map<String, dynamic> meOptionsJson() => {
      'currencies': currenciesJson()['currencies'],
      'timezones': [
        {'value': 'London', 'name': '(GMT+00:00) London', 'iana': 'Europe/London', 'utc_offset': '+01:00'},
        {'value': 'Kyiv', 'name': '(GMT+02:00) Kyiv', 'iana': 'Europe/Kiev', 'utc_offset': '+03:00'},
        {'value': 'Istanbul', 'name': '(GMT+03:00) Istanbul', 'iana': 'Europe/Istanbul', 'utc_offset': '+03:00'},
        {'value': 'Tokyo', 'name': '(GMT+09:00) Tokyo', 'iana': 'Asia/Tokyo', 'utc_offset': '+09:00'},
      ],
      'locales': [
        {'value': 'tr', 'name': 'Türkçe'},
        {'value': 'en', 'name': 'English'},
      ],
      'theme_preferences': [
        {'value': 'dark', 'name': 'Koyu (varsayılan)'},
        {'value': 'light', 'name': 'Açık'},
        {'value': 'system', 'name': 'Sistemi takip et'},
      ],
      'weekly_review_days': [
        for (final (i, name) in const ['Pazar', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi'].indexed)
          {'value': i, 'name': name},
      ],
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

// Payload helpers added by a work package go in its own region below
// (see design-analysis §9.0): edits in different regions merge cleanly.

// region shell (WP-4)
// endregion

// region today (WP-5)
// endregion

// region quick capture (WP-6)
// endregion

// region agenda (WP-7)
// endregion

// region finance (WP-8)
/// GET /finance/dashboard: a quiet month (nothing spent yet), with WP-15's
/// per-currency totals and the cumulative series (4 October: four days of
/// this month, the 30 of September).
Map<String, dynamic> financeDashboardJson() => {
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'month': const {'income_cents': 0, 'expense_cents': 0, 'net_cents': 0},
      'year': const {'income_cents': 0, 'expense_cents': 0},
      'totals_by_currency': const [
        {
          'currency': 'TRY',
          'subunit_to_unit': 100,
          'month': {'income_cents': 0, 'expense_cents': 0, 'net_cents': 0},
          'year': {'income_cents': 0, 'expense_cents': 0},
        },
      ],
      'spend_cumulative_cents': const [0, 0, 0, 0],
      'reference_cumulative_cents': List.filled(30, 0),
      'six_month_series': const {
        'labels': [],
        'income_cents': [],
        'expense_cents': [],
      },
      'pie': const [],
      'budgets': const [],
      'upcoming_subscriptions': const [],
      'recent_transactions': const [],
    };
// endregion

// region transactions (WP-9)
/// GET /transactions answered from [rows], as the server filters them by
/// `q` (contract 13.2): the rows whose description or note contains it, in
/// any case, the four Turkish i's as one letter — with the totals of the
/// rows it keeps. The other filters are not applied.
Object? Function(RequestOptions request) transactionsFeed(
  List<Map<String, dynamic>> rows,
) =>
    (request) {
      final q = request.queryParameters['q'];
      final needle = q is String ? trFold(q.trim()) : '';
      final kept = [
        for (final row in rows)
          if (needle.isEmpty ||
              [row['description'], row['note']]
                  .any((f) => f is String && trFold(f).contains(needle)))
            row,
      ];
      int total(String kind) => kept
          .where((row) => row['kind'] == kind)
          .fold(0, (sum, row) => sum + (row['amount_cents'] as int));
      return {
        'transactions': kept,
        'meta': {
          'total_count': kept.length,
          'page': 1,
          'page_limit': 50,
          'filtered_income_cents': total('income'),
          'filtered_expense_cents': total('expense'),
        },
      };
    };
// endregion

// region categories, budgets, subscriptions (WP-10)
// endregion

// region habits (WP-11)
// endregion

// region goals (WP-12)
// endregion

// region journal (WP-13)
// endregion

// region profile (WP-14)
// endregion

// region search (WP-16)
// endregion

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
  'GET /me/options': _Route(body: meOptionsJson()),
  'GET /home': _Route(body: homeJson()),
  'GET /habits': _Route(body: habitsJson()),
  'GET /habits/7': _Route(body: {'habit': habitDetailJson()}),
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
  'GET /finance_categories': _Route(body: {
    'categories': [categoryJson()],
  }),
  'GET /finance_categories/5': _Route(body: {'category': categoryUsageJson()}),
  'GET /budgets': _Route(body: budgetsJson()),
  'GET /subscriptions': _Route(body: subscriptionsJson()),
  'GET /transactions/316':
      _Route(body: {'transaction': transactionDetailJson()}),
  'GET /todos': _Route(body: {
    'todos': [todoJson()],
    'meta': const {
      'open_count': 1,
      'overdue_count': 1,
      'total_count': 1,
      'counts': {
        'open': 1,
        'today': 1,
        'week': 1,
        'upcoming': 0,
        'overdue': 1,
        'undated': 0,
        'done': 0,
        'cancelled': 0,
        'all': 1,
      },
    },
  }),
  'GET /events': const _Route(body: {'events': []}),
  'GET /events/12': _Route(body: {'event': eventJson(full: true)}),
  'GET /todo_lists': _Route(body: {
    'todo_lists': [todoListJson()],
    'meta': const {'unlisted_open_count': 1},
  }),
  'GET /journal_entries': _Route(body: {
    'entries': [journalListItemJson()],
    'meta': const {
      'entries_count': 1,
      'journal_streak': 1,
      'mood_counts': {'great': 0, 'good': 1, 'neutral': 0, 'bad': 0, 'awful': 0},
      'range': '30d',
    },
  }),
  'GET /journal_entries/20': _Route(body: {'entry': journalEntryJson()}),

  // Default routes added by a work package, reads and writes, go in its
  // own region.

  // region shell (WP-4)
  // endregion

  // region today (WP-5)
  // endregion

  // region quick capture (WP-6)
  // endregion

  // region agenda (WP-7)
  // endregion

  // region finance (WP-8)
  'GET /finance/dashboard': _Route(body: financeDashboardJson()),
  // endregion

  // region transactions (WP-9)
  'GET /transactions': _Route(respond: transactionsFeed([transactionJson()])),
  // endregion

  // region categories, budgets, subscriptions (WP-10)
  // endregion

  // region habits (WP-11)
  // endregion

  // region goals (WP-12)
  // endregion

  // region journal (WP-13)
  // endregion

  // region profile (WP-14)
  // endregion

  // region search (WP-16)
  // endregion

  // Writes.
  'PATCH /me': _Route(body: {'user': userJson()}),
  'PATCH /me/password': _Route(body: {'token': 'new-token', 'user': userJson()}),
  'DELETE /session': const _Route(status: 204),
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
  'PATCH /habits/7/unarchive': _Route(body: {'habit': habitJson()}),
  'DELETE /habits/7': const _Route(status: 204),
  'PATCH /goals/3/update_progress': _Route(body: {'goal': goalJson(current: 41)}),
  'PATCH /goals/3/recalculate': _Route(body: {'goal': goalJson()}),
  'POST /goals': _Route(body: {'goal': goalJson(id: 4)}, status: 201),
  'PATCH /goals/3': _Route(body: {'goal': goalJson()}),
  'DELETE /goals/3': const _Route(status: 204),
  'POST /journal_entries': _Route(body: {'entry': journalEntryJson(id: 21)}, status: 201),
  'PATCH /journal_entries/20': _Route(body: {'entry': journalEntryJson()}),
  'DELETE /journal_entries/20': const _Route(status: 204),
  'POST /todos': _Route(body: {'todo': todoJson(id: 40)}, status: 201),
  'PATCH /todos/39': _Route(body: {'todo': todoJson()}),
  'DELETE /todos/39': const _Route(status: 204),
  'POST /todo_lists': _Route(
      body: {'todo_list': todoListJson(id: 6, name: 'İş', open: 0, total: 0)},
      status: 201),
  'PATCH /todo_lists/5': _Route(body: {'todo_list': todoListJson()}),
  'DELETE /todo_lists/5': const _Route(status: 204),
  'POST /events': _Route(body: {'event': eventJson(id: 13, full: true)}, status: 201),
  'PATCH /events/12': _Route(body: {'event': eventJson(full: true)}),
  'DELETE /events/12': const _Route(status: 204),
  'POST /quick_captures': _Route(body: captureTodoJson(), status: 201),
};
