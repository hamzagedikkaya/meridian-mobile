/// The API's error shape (contract G1.1) and how the app words it: every
/// `code` in both languages, validation details per field, and the rule for
/// an action that failed.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/l10n/app_l10n_en.dart';
import 'package:meridian_mobile/l10n/app_l10n_tr.dart';

const tr = AppL10nTr();
const en = AppL10nEn();

ApiException _from(int? status, Object? body) => ApiException.fromDio(
  status == null
      ? DioException.connectionError(
          requestOptions: RequestOptions(path: '/x'),
          reason: 'refused',
        )
      : DioException.badResponse(
          statusCode: status,
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: status,
            data: body,
          ),
        ),
);

ApiException _refusal(String code, [Map<String, Object?> extra = const {}]) =>
    _from(422, {
      'errors': {
        'text': ['raw server text'],
      },
      'code': code,
      ...extra,
    });

void main() {
  setUpAll(initializeDateFormatting);

  group('a failure without an answer says whether the request went out', () {
    ApiException failed(DioExceptionType type) => ApiException.fromDio(
      DioException(requestOptions: RequestOptions(path: '/x'), type: type),
    );

    test('a send or receive timeout: it may have arrived, and been acted on',
        () {
      for (final type in [
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final error = failed(type);
        expect(error.kind, ApiErrorKind.network, reason: '$type');
        expect(error.timedOut, isTrue, reason: '$type');
        expect(error.mayHaveArrived, isTrue, reason: '$type');
      }
    });

    test('a connect timeout or a refused connection: it never left', () {
      final connect = failed(DioExceptionType.connectionTimeout);
      expect(connect.timedOut, isTrue);
      expect(connect.mayHaveArrived, isFalse);
      final refused = _from(null, null);
      expect(refused.timedOut, isFalse);
      expect(refused.mayHaveArrived, isFalse);
    });
  });

  group('fromDio reads the G1 error shape', () {
    test('401, 404 and 429 by code', () {
      expect(
        _from(401, {'error': 'unauthorized', 'code': 'unauthorized'}).kind,
        ApiErrorKind.unauthorized,
      );
      expect(
        _from(401, {
          'error': 'invalid_credentials',
          'code': 'invalid_credentials',
        }).kind,
        ApiErrorKind.invalidCredentials,
      );
      final gone = _from(404, {'error': 'not_found', 'code': 'not_found'});
      expect(gone.kind, ApiErrorKind.notFound);
      expect(gone.code, 'not_found');
      final limited = _from(429, {
        'error': 'too_many_requests',
        'code': 'too_many_requests',
      });
      expect(limited.kind, ApiErrorKind.rateLimited);
      expect(readRetry(0, limited), isNull);
    });

    test('a 422 keeps its messages, details and extra keys', () {
      final e = _from(422, {
        'errors': {
          'title': ['Başlık çok uzun (en fazla 200 karakter)'],
        },
        'code': 'validation_failed',
        'details': {
          'title': [
            {'error': 'too_long', 'count': 200},
          ],
        },
      });
      expect(e.isValidation, isTrue);
      expect(e.code, 'validation_failed');
      expect(e.fieldErrors['title'], [
        'Başlık çok uzun (en fazla 200 karakter)',
      ]);
      expect(e.details['title']!.single.error, 'too_long');
      expect(e.details['title']!.single.count, 200);
    });

    test('the keys some codes carry', () {
      expect(_refusal('unknown_habit', {'name': 'yoga'}).name, 'yoga');
      expect(_refusal('invalid_amount', {'reason': 'zero'}).reason, 'zero');
      expect(_refusal('invalid_parameter', {'param': 'done'}).param, 'done');
      expect(
        _refusal('before_habit_start', {
          'habit_start': '2026-09-20',
        }).habitStart,
        DateTime(2026, 9, 20),
      );
      expect(
        _refusal('has_transactions', {
          'transactions_count': 47,
        }).number('transactions_count'),
        47,
      );
    });

    test('any 422 is a refusal, also one without an errors map', () {
      expect(_from(422, {'error': 'nope'}).isValidation, isTrue);
      expect(_from(422, null).isValidation, isTrue);
    });

    test('no response is a network failure', () {
      final e = _from(null, null);
      expect(e.isNetwork, isTrue);
      expect(e.code, isNull);
    });
  });

  group('every code is worded by the app, in both languages', () {
    final codes = <String, Map<String, Object?>>{
      'too_many_requests': {},
      'invalid_parameter': {'param': 'count'},
      'value_out_of_range': {},
      'invalid_date': {},
      'invalid_datetime': {'param': 'due_at'},
      'future_date': {},
      'before_habit_start': {'habit_start': '2026-09-20'},
      'habit_archived': {},
      'empty': {},
      'no_account': {},
      'unknown_habit': {'name': 'yoga'},
      'invalid_amount': {'reason': 'unreadable'},
      'has_transactions': {
        'transactions_count': 3,
        'incoming_transfers_count': 1,
      },
      'currency_locked': {},
      'kind_locked': {},
      'amount_required': {},
      'not_chargeable': {'reason': 'inactive'},
      'target_reached': {},
      'target_not_reached': {},
      'progress_computed': {},
      'body_has_formatting': {},
    };
    for (final MapEntry(key: code, value: extra) in codes.entries) {
      test(code, () {
        final e = _refusal(code, extra);
        final inTurkish = e.localized(tr);
        final inEnglish = e.localized(en);
        expect(inTurkish, isNotEmpty);
        expect(inEnglish, isNotEmpty);
        expect(inTurkish, isNot(inEnglish));
        // Never the server's own sentence, whatever language it came in.
        expect(inTurkish, isNot('raw server text'));
        expect(inEnglish, isNot('raw server text'));
      });
    }

    test('the extra keys reach the sentence', () {
      expect(
        _refusal('unknown_habit', {'name': 'yoga'}).localized(tr),
        '“yoga” adında bir alışkanlık yok',
      );
      expect(
        _refusal('unknown_habit', {'name': 'yoga'}).localized(en),
        'There\'s no habit called “yoga”',
      );
      expect(
        _refusal('before_habit_start', {
          'habit_start': '2026-09-20',
        }).localized(tr),
        contains('20 Eylül 2026'),
      );
      expect(
        _refusal('has_transactions', {
          'transactions_count': 47,
          'incoming_transfers_count': 0,
        }).localized(tr),
        contains('47 işlemi'),
      );
    });

    test('invalid_amount says why, by reason', () {
      String say(String reason) =>
          _refusal('invalid_amount', {'reason': reason}).localized(tr);
      expect(say('zero'), 'Tutar sıfırdan büyük olmalı');
      expect(say('too_large'), 'Tutar çok büyük');
      expect(say('too_precise'), contains('ondalık'));
      expect(say('unreadable'), contains('-12,50'));
      expect(
        _refusal('invalid_amount', {'reason': 'unreadable'}).localized(en),
        contains('-12.50'),
      );
    });

    test('401 and 404 by code', () {
      expect(
        _from(401, {'code': 'unauthorized'}).localized(tr),
        'Oturum süresi doldu',
      );
      expect(_from(404, {'code': 'not_found'}).localized(en), 'Not found');
      expect(
        _from(429, {'code': 'too_many_requests'}).localized(tr),
        contains('Çok fazla deneme'),
      );
    });
  });

  group('validation details', () {
    ApiException invalid(
      String field,
      Map<String, Object?> detail, {
      String message = 'is too long (maximum is 200 characters)',
    }) => _from(422, {
      'errors': {
        field: [message],
      },
      'code': 'validation_failed',
      'details': {
        field: [detail],
      },
    });

    test('a known type is worded by the app, with the field\'s name when it '
        'stands alone (a snackbar)', () {
      final e = invalid('title', {'error': 'too_long', 'count': 200});
      expect(e.localized(tr), 'Başlık: En fazla 200 karakter olabilir');
      expect(e.localized(en), 'Title: At most 200 characters');
    });

    test('under a field, without its name', () {
      final e = invalid('name', {'error': 'blank'});
      expect(e.fieldMessage(tr, 'name'), 'Boş bırakılamaz');
      expect(e.fieldMessage(en, 'name'), 'Can\'t be blank');
      expect(
        e.fieldMessage(tr, 'title'),
        isNull,
        reason: 'nothing was said about it',
      );
    });

    test('an unknown type falls back to the server\'s own message', () {
      final e = invalid('name', {'error': 'mystery'}, message: 'Ad garip');
      expect(e.fieldMessage(tr, 'name'), 'Ad garip');
      expect(e.localized(tr), 'Ad garip');
    });

    test('a count with decimals reads in the language\'s notation', () {
      final e = invalid('amount_cents', {
        'error': 'greater_than',
        'count': 0.5,
      });
      expect(
        e.fieldMessage(tr, 'amount_cents'),
        '0,50 değerinden büyük olmalı',
      );
      expect(e.fieldMessage(en, 'amount_cents'), 'Must be greater than 0.50');
    });

    test('a server from before G1 (no code, no details) still shows its '
        'message', () {
      final e = _from(422, {
        'errors': {
          'amount_cents': ['must be greater than 0'],
        },
      });
      expect(e.localized(en), 'must be greater than 0');
    });
  });

  group('failureMessage: why, when the server said why', () {
    test('a refusal, a missing record or a dead session says why', () {
      expect(
        failureMessage(_refusal('habit_archived'), tr, fallback: 'X'),
        'Arşivlenmiş alışkanlık işaretlenemez',
      );
      expect(
        failureMessage(_from(404, {'code': 'not_found'}), tr, fallback: 'X'),
        'Kayıt bulunamadı',
      );
    });

    test('no connection, a 5xx or a bug says what did not happen', () {
      expect(failureMessage(_from(null, null), tr, fallback: 'X'), 'X');
      expect(failureMessage(_from(500, null), tr, fallback: 'X'), 'X');
      expect(failureMessage(StateError('bug'), tr, fallback: 'X'), 'X');
    });
  });
}
