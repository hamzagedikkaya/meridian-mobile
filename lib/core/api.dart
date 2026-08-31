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

  /// 422 with `{errors: {field: [msg]}}`; the messages come from the server
  /// already in the user's language.
  validation,
  server,
}

class ApiException implements Exception {
  final ApiErrorKind kind;
  final int? status;
  final Map<String, List<String>> fieldErrors;

  ApiException(this.kind, {this.status, this.fieldErrors = const {}});

  bool get isUnauthorized =>
      kind == ApiErrorKind.unauthorized || kind == ApiErrorKind.invalidCredentials;
  bool get isValidation => kind == ApiErrorKind.validation;
  bool get isNetwork => kind == ApiErrorKind.network;

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

    if (status == 422 && data is Map && data['errors'] is Map) {
      final errors = <String, List<String>>{};
      (data['errors'] as Map).forEach((key, value) {
        errors['$key'] =
            value is List ? value.map((m) => '$m').toList() : ['$value'];
      });
      return ApiException(
        ApiErrorKind.validation,
        status: status,
        fieldErrors: errors,
      );
    }
    if (status == 401) {
      final error = data is Map ? data['error'] : null;
      return ApiException(
        error == 'invalid_credentials'
            ? ApiErrorKind.invalidCredentials
            : ApiErrorKind.unauthorized,
        status: status,
      );
    }
    if (status == 404) return ApiException(ApiErrorKind.notFound, status: status);
    if (status != null) return ApiException(ApiErrorKind.server, status: status);
    return ApiException(ApiErrorKind.network);
  }

  @override
  String toString() => 'ApiException($kind, status: $status)';
}

extension ApiExceptionCopy on ApiException {
  /// The sentence to show the user, in the active language.
  String localized(AppL10n l) => switch (kind) {
        ApiErrorKind.network => l.errNoConnection,
        ApiErrorKind.unauthorized => l.errSessionExpired,
        ApiErrorKind.invalidCredentials => l.errInvalidCredentials,
        ApiErrorKind.notFound => l.errNotFound,
        ApiErrorKind.validation => firstFieldError ?? l.errInvalidData,
        ApiErrorKind.server => l.errServer(status ?? 500),
      };
}

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
