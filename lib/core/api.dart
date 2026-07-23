import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  final Map<String, List<String>> fieldErrors;

  ApiException(this.message, {this.status, this.fieldErrors = const {}});

  bool get isUnauthorized => status == 401;
  bool get isValidation => status == 422;
  bool get isNetwork => status == null;

  factory ApiException.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;

    if (status == 422 && data is Map && data['errors'] is Map) {
      final errors = <String, List<String>>{};
      (data['errors'] as Map).forEach((key, value) {
        errors['$key'] =
            value is List ? value.map((m) => '$m').toList() : ['$value'];
      });
      final first = errors.values.isEmpty ? 'Geçersiz veri' : errors.values.first.first;
      return ApiException(first, status: status, fieldErrors: errors);
    }
    if (status == 401) {
      final error = data is Map ? data['error'] : null;
      return ApiException(
        error == 'invalid_credentials'
            ? 'E-posta veya şifre hatalı'
            : 'Oturum süresi doldu',
        status: status,
      );
    }
    if (status == 404) return ApiException('Kayıt bulunamadı', status: status);
    if (status != null) {
      return ApiException('Sunucu hatası ($status)', status: status);
    }
    return ApiException(
      'Sunucuya ulaşılamıyor — aynı Wi-Fi ağında olduğundan emin ol',
    );
  }

  @override
  String toString() => message;
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
