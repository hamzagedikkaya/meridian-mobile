@Tags(['golden'])
/// Giriş (Login).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-14.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/ui/screens/login_screen.dart';

import 'golden_harness.dart';

void main() {
  setUpGoldens();

  goldenScreen('login', (tester, _) async {
    // A zone-local fake HttpClient makes ServerUrlField's /health ping
    // succeed, so the address field collapses to its "host · Değiştir"
    // success state and the credentials section is at full opacity.
    await HttpOverrides.runZoned<Future<void>>(
      () async {
        await tester.pumpWidget(goldenHost(
          const LoginScreen(),
          [sharedPrefsProvider.overrideWithValue(goldenPrefs)],
        ));
        await tester.pumpAndSettle();
      },
      createHttpClient: (_) => _OkHealthClient(),
    );
  });
}

// --- Fake HttpClient for the login /health ping (returns 200 {"ok":true}) -----

class _OkHealthClient implements HttpClient {
  @override
  Duration idleTimeout = const Duration(seconds: 3);
  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _OkHealthRequest();

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OkHealthRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _OkHealthHeaders();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;

  @override
  Future<HttpClientResponse> close() async => _OkHealthResponse();
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OkHealthHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String name, List<String> values) action) {
    action('content-type', const ['application/json; charset=utf-8']);
  }

  @override
  String? value(String name) => name.toLowerCase() == 'content-type'
      ? 'application/json; charset=utf-8'
      : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OkHealthResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _OkHealthResponse._(this._bytes) : super(Stream<List<int>>.value(_bytes));
  factory _OkHealthResponse() =>
      _OkHealthResponse._(utf8.encode('{"ok":true,"version":"1.0.0"}'));

  final List<int> _bytes;

  @override
  int get statusCode => 200;
  @override
  String get reasonPhrase => 'OK';
  @override
  int get contentLength => _bytes.length;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];
  @override
  HttpHeaders get headers => _OkHealthHeaders();
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
