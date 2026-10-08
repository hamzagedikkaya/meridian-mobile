/// One token per account (contract §1.1): a password change replaces it, and
/// any request that left with the old one is refused with a 401. Only a 401
/// for the token still in use means the session is over.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';

import '../support/fake_api.dart';

void main() {
  late FakeApi api;
  late String? token;
  late int signedOut;
  late Dio dio;

  setUp(() {
    api = FakeApi()
      ..on('GET /home', {'error': 'unauthorized', 'code': 'unauthorized'},
          status: 401);
    token = 'old-token';
    signedOut = 0;
    dio = buildDio(
      baseUrl: 'http://meridian.test',
      tokenReader: () async => token,
      onUnauthorized: () => signedOut++,
    )..httpClientAdapter = api;
  });

  Future<void> getHome() async {
    try {
      await dio.get<Object?>('/home');
    } on DioException {
      // Expected: the 401.
    }
  }

  test('a 401 for the token in use signs out', () async {
    await getHome();
    expect(signedOut, 1);
  });

  test('a 401 for a token replaced while the request was out does not',
      () async {
    api.hold('GET /home');
    final request = getHome();
    while (!api.requests.contains('GET /home')) {
      await Future<void>.delayed(Duration.zero);
    }
    token = 'new-token';
    api.release('GET /home');
    await request;
    expect(signedOut, 0);
  });

  test('a request sent without a token still signs out on a 401', () async {
    token = null;
    await getHome();
    expect(signedOut, 1);
  });

  test('DELETE /session handles its own 401: it never signs out by itself',
      () async {
    api.on('DELETE /session', {'error': 'unauthorized', 'code': 'unauthorized'},
        status: 401);
    try {
      await dio.delete<Object?>('/session');
    } on DioException {
      // Expected.
    }
    expect(signedOut, 0);
  });
}
