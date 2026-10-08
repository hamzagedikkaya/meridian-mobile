import 'package:dio/dio.dart';

import '../l10n/app_l10n.dart';

/// Why a request failed, without saying it in any particular language — the UI
/// turns this into copy through [ApiExceptionCopy.localized].
enum ApiErrorKind {
  /// No response at all: wrong address, wrong Wi-Fi, server down.
  network,

  /// A 401 on a normal request — the token is gone or stale.
  unauthorized,

  /// A 401 on the login request itself.
  invalidCredentials,
  notFound,

  /// A 422: the server refused the request and changed nothing. [ApiException
  /// .code] says why (`validation_failed`, `no_account`, `future_date`, …).
  validation,

  /// A 429: too many sign-in attempts in a short time.
  rateLimited,
  server,
}

/// One machine-readable reason a field was refused, from a 422's `details`:
/// the Rails error type (`blank`, `too_long`, `taken`, …) and its arguments
/// (`count`, `value`, …).
class ApiErrorDetail {
  final String error;
  final Map<String, Object?> args;

  const ApiErrorDetail(this.error, [this.args = const {}]);

  /// The limit a `too_long`, `too_short`, `greater_than`… error names.
  num? get count => switch (args['count']) {
        final num n => n,
        final String s => num.tryParse(s),
        _ => null,
      };

  @override
  String toString() => 'ApiErrorDetail($error, $args)';
}

class ApiException implements Exception {
  final ApiErrorKind kind;
  final int? status;

  /// The server's stable reason (`unauthorized`, `not_found`,
  /// `validation_failed`, `no_account`, `unknown_habit`, …): what the app
  /// branches on. Null for a failure without a response, or from a server
  /// that predates codes.
  final String? code;

  /// The server's messages per field, already in the account's language.
  final Map<String, List<String>> fieldErrors;

  /// What [fieldErrors] say, per field, as error types the app words itself
  /// (`validation_failed` only).
  final Map<String, List<ApiErrorDetail>> details;

  /// The rest of the error body: the keys some codes carry (`param`,
  /// `name`, `reason`, `habit_start`, `transactions_count`, …).
  final Map<String, Object?> extra;

  /// A [ApiErrorKind.network] failure that came from waiting out a timeout
  /// (connect, send or receive), as opposed to a refused or reset connection.
  final bool timedOut;

  /// A [timedOut] failure after the request had started to go out — a send
  /// or receive timeout, not a connect timeout: the server may have received
  /// it and acted on it, only no answer came back in time. A write that is
  /// not safe to repeat (`POST /quick_captures` creates a record each time)
  /// must not simply be sent again.
  final bool mayHaveArrived;

  ApiException(
    this.kind, {
    this.status,
    this.code,
    this.fieldErrors = const {},
    this.details = const {},
    this.extra = const {},
    this.timedOut = false,
    this.mayHaveArrived = false,
  });

  bool get isUnauthorized =>
      kind == ApiErrorKind.unauthorized || kind == ApiErrorKind.invalidCredentials;

  /// The server refused the request (a 422): nothing was written.
  bool get isValidation => kind == ApiErrorKind.validation;
  bool get isNetwork => kind == ApiErrorKind.network;

  /// The parameter an `invalid_parameter`, `invalid_date` or
  /// `invalid_datetime` refusal is about.
  String? get param => _string('param');

  /// The habit name an `unknown_habit` capture was typed with.
  String? get name => _string('name');

  /// Why an amount (`invalid_amount`: `unreadable`, `zero`, `too_precise`,
  /// `too_large`) or a charge (`not_chargeable`) was refused.
  String? get reason => _string('reason');

  /// The day a habit started, for `before_habit_start`.
  DateTime? get habitStart => DateTime.tryParse(_string('habit_start') ?? '');

  /// A number the error body carries ([extra]), e.g. `transactions_count`.
  num? number(String key) => switch (extra[key]) {
        final num n => n,
        final String s => num.tryParse(s),
        _ => null,
      };

  String? _string(String key) => switch (extra[key]) {
        final String s when s.isNotEmpty => s,
        _ => null,
      };

  /// The server's own first validation message, if there is one.
  String? get firstFieldError {
    for (final messages in fieldErrors.values) {
      if (messages.isNotEmpty) return messages.first;
    }
    return null;
  }

  factory ApiException.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final body = data is Map ? data : const {};
    final code = switch (body['code']) {
      final String c when c.isNotEmpty => c,
      _ => null,
    };
    final error = body['error'];

    if (status == 422) {
      return ApiException(
        ApiErrorKind.validation,
        status: status,
        code: code,
        fieldErrors: _fieldErrors(body['errors']),
        details: _details(body['details']),
        extra: _extra(body),
      );
    }
    if (status == 401) {
      final login = code == 'invalid_credentials' || error == 'invalid_credentials';
      return ApiException(
        login ? ApiErrorKind.invalidCredentials : ApiErrorKind.unauthorized,
        status: status,
        code: code,
      );
    }
    if (status == 404) {
      return ApiException(ApiErrorKind.notFound, status: status, code: code);
    }
    if (status == 429) {
      return ApiException(ApiErrorKind.rateLimited, status: status, code: code);
    }
    if (status != null) {
      return ApiException(ApiErrorKind.server, status: status, code: code);
    }
    return ApiException(
      ApiErrorKind.network,
      timedOut: switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          true,
        _ => false,
      },
      // A connect timeout never got the request out; these two did.
      mayHaveArrived: switch (e.type) {
        DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout => true,
        _ => false,
      },
    );
  }

  static Map<String, List<String>> _fieldErrors(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        '$key': value is List ? [for (final m in value) '$m'] : ['$value'],
    };
  }

  static Map<String, List<ApiErrorDetail>> _details(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<ApiErrorDetail>>{};
    raw.forEach((field, list) {
      if (list is! List) return;
      final parsed = [
        for (final item in list)
          if (item is Map && item['error'] is String)
            ApiErrorDetail(item['error'] as String, {
              for (final MapEntry(:key, :value) in item.entries)
                if (key != 'error') '$key': value,
            }),
      ];
      if (parsed.isNotEmpty) out['$field'] = parsed;
    });
    return out;
  }

  static Map<String, Object?> _extra(Map<dynamic, dynamic> body) => {
        for (final MapEntry(:key, :value) in body.entries)
          if (key is String &&
              key != 'errors' &&
              key != 'details' &&
              key != 'code' &&
              key != 'error')
            key: value,
      };

  @override
  String toString() => 'ApiException($kind, status: $status, code: $code)';
}

/// How a failed read is retried — set as the app's ProviderScope `retry`.
///
/// Riverpod's default is ten silent attempts backing off from 200 ms to
/// 6.4 s, about 40 s of waiting — 90 s when every attempt sits out the 5 s
/// connect timeout — during which a first load shows a skeleton and a
/// pull-to-refresh spinner never lets go. Here a failure surfaces in seconds:
///
/// * a 4xx is final — a missing record, a bad request, a refused permission,
///   a rate limit or a dead session does not heal by asking again at once;
/// * a timeout has already waited long enough;
/// * a refused or reset connection, or a 5xx, gets one quick second try,
///   which covers a Wi-Fi/VPN handover or a server restart;
/// * anything else — a payload that does not parse, a bug — is shown at once.
///
/// The read models apply it inside each fetch (see `retried` in
/// `data/providers.dart`) rather than through Riverpod's automatic retry,
/// which they turn off: every fetch — a first load, a refresh, a retry — gets
/// its own quick second try, and a screen only ever sees the fetch's outcome.
/// When that fails too, the data on screen stays, under the offline banner,
/// and the next refresh asks again. Other providers get it from Riverpod.
Duration? readRetry(int retryCount, Object error) {
  if (retryCount >= 1 || error is! ApiException) return null;
  return switch (error.kind) {
    ApiErrorKind.network when !error.timedOut =>
      const Duration(milliseconds: 800),
    // [ApiException.fromDio] files every status it has no kind for under
    // server — 400, 403 and 409 included — so only a 5xx (or no status at
    // all) is worth the second try.
    ApiErrorKind.server when (error.status ?? 500) >= 500 =>
      const Duration(milliseconds: 800),
    _ => null,
  };
}

extension ApiExceptionCopy on ApiException {
  /// The sentence to show the user, in the active language.
  ///
  /// The server's `code` decides it, so a refusal reads the same whatever
  /// language the account is set to on the server. A field's validation
  /// error is worded here too when its type is one the app knows; only an
  /// unknown one falls back to the server's own message (which Rails words
  /// in the account's language).
  String localized(AppL10n l) {
    final byCode = _byCode(l);
    if (byCode != null) return byCode;
    return switch (kind) {
      ApiErrorKind.network => l.errNoConnection,
      ApiErrorKind.unauthorized => l.errSessionExpired,
      ApiErrorKind.invalidCredentials => l.errInvalidCredentials,
      ApiErrorKind.notFound => l.errNotFound,
      ApiErrorKind.validation => _firstFieldMessage(l) ?? l.errInvalidData,
      ApiErrorKind.rateLimited => l.errTooManyRequests,
      ApiErrorKind.server => l.errServer(status ?? 500),
    };
  }

  /// The message to show under [field] in a form (no field name in it: it
  /// sits under the field), or null when the server said nothing about it.
  String? fieldMessage(AppL10n l, String field) {
    for (final detail in details[field] ?? const <ApiErrorDetail>[]) {
      final worded = l.validationDetail(detail.error, count: detail.count);
      if (worded != null) return worded;
    }
    final messages = fieldErrors[field];
    if (messages != null && messages.isNotEmpty) return messages.first;
    return null;
  }

  /// The first field error as a sentence on its own (for a snackbar): the
  /// field's name, then what is wrong with it.
  String? _firstFieldMessage(AppL10n l) {
    for (final MapEntry(key: field, value: list) in details.entries) {
      for (final detail in list) {
        final worded = l.validationDetail(detail.error, count: detail.count);
        final label = l.fieldLabel(field);
        if (worded != null && label != null) return '$label: $worded';
      }
    }
    return firstFieldError;
  }

  String? _byCode(AppL10n l) => switch (code) {
        'unauthorized' => l.errSessionExpired,
        'invalid_credentials' => l.errInvalidCredentials,
        'too_many_requests' => l.errTooManyRequests,
        'not_found' => l.errNotFound,
        'validation_failed' => _firstFieldMessage(l) ?? l.errInvalidData,
        'invalid_parameter' =>
          l.errInvalidParameter(l.fieldLabel(param ?? '') ?? param ?? '?'),
        'value_out_of_range' => l.errValueOutOfRange,
        'invalid_date' => l.errInvalidDate,
        'invalid_datetime' => l.errInvalidDatetime,
        'future_date' => l.errFutureDate,
        'before_habit_start' => l.errBeforeHabitStart(habitStart),
        'habit_archived' => l.errHabitArchived,
        'empty' => l.errCaptureEmpty,
        'no_account' => l.errNoAccount,
        'unknown_habit' => l.errUnknownHabit(name ?? ''),
        'invalid_amount' => l.errInvalidAmount(reason),
        'has_transactions' => l.errHasTransactions(
            (number('transactions_count') ?? 0).toInt(),
            (number('incoming_transfers_count') ?? 0).toInt(),
          ),
        'currency_locked' => l.errCurrencyLocked,
        'kind_locked' => l.errKindLocked,
        'amount_required' => l.errAmountRequired,
        'not_chargeable' => l.errNotChargeable(reason),
        'target_reached' => l.errTargetReached,
        'target_not_reached' => l.errTargetNotReached,
        'progress_computed' => l.errProgressComputed,
        'body_has_formatting' => l.errBodyHasFormatting,
        _ => null,
      };
}

/// The sentence for an action that failed with [error]: the server's reason
/// when it gave one (a refusal, a record that is gone, a dead session), and
/// otherwise [fallback] — which names what did not happen ("Couldn't update
/// the habit"), more useful than a bare "no connection" when the offline
/// banner already says that.
String failureMessage(Object error, AppL10n l, {required String fallback}) =>
    switch (error) {
      ApiException(kind: ApiErrorKind.network || ApiErrorKind.server) =>
        fallback,
      final ApiException e => e.localized(l),
      _ => fallback,
    };

Dio buildDio({
  required String baseUrl,
  required Future<String?> Function() tokenReader,
  required void Function() onUnauthorized,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: '$baseUrl/api/v1',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokenReader();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        final isLogin = error.requestOptions.path.endsWith('/session');
        if (error.response?.statusCode == 401 && !isLogin) {
          onUnauthorized();
        }
        handler.next(error);
      },
    ),
  );
  return dio;
}
