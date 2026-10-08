/// Every refusal the finance endpoints send (contract §1.5, G2) reads in the
/// app's language: by its code, or — for a field that failed validation —
/// the field's name and what is wrong with it. Never the server's sentence.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/l10n/app_l10n_en.dart';
import 'package:meridian_mobile/l10n/app_l10n_tr.dart';

const tr = AppL10nTr();
const en = AppL10nEn();

ApiException _refusal(Map<String, Object?> body) => ApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 422,
          data: body,
        ),
      ),
    );

/// A validation failure of [field] of [type], with the server's own
/// sentence as the message the app must not show.
ApiException _invalid(String field, String type, [Map<String, Object?> args = const {}]) =>
    _refusal({
      'errors': {
        field: ['raw server text'],
      },
      'code': 'validation_failed',
      'details': {
        field: [
          {'error': type, ...args},
        ],
      },
    });

void main() {
  // (field, type, extra keys) the finance endpoints report.
  const failures = <(String, String, Map<String, Object?>)>[
    ('name', 'blank', {}),
    ('name', 'too_long', {'count': 60}),
    ('name', 'taken', {'value': 'market'}),
    ('account_type', 'inclusion', {'value': 'wallet'}),
    ('currency', 'inclusion', {'value': 'XYZ'}),
    ('currency', 'wrong_length', {'count': 3}),
    ('color', 'invalid', {}),
    ('initial_balance_cents', 'not_a_number', {}),
    ('initial_balance', 'not_a_number', {}),
    ('amount_cents', 'greater_than', {'value': 0, 'count': 0}),
    ('amount', 'not_a_number', {}),
    ('date', 'blank', {}),
    ('account', 'blank', {}),
    ('finance_category', 'kind_mismatch', {}),
    ('related_account_id', 'currency_mismatch', {}),
    ('related_account_id', 'same_account', {}),
    ('related_account_id', 'required_for_transfer', {}),
    ('kind', 'inclusion', {'value': 'x'}),
    ('parent_id', 'must_match_kind', {}),
    ('parent_id', 'must_be_root', {}),
    ('parent_id', 'cannot_be_self', {}),
    ('parent_id', 'cannot_have_children', {}),
    ('parent_id', 'has_budget', {}),
    ('finance_category_id', 'must_be_expense', {}),
    ('finance_category_id', 'must_be_root', {}),
    ('finance_category_id', 'taken', {'value': 5}),
    ('monthly_limit_cents', 'greater_than', {'value': 0, 'count': 0}),
    ('monthly_limit', 'not_a_number', {}),
    ('frequency', 'inclusion', {'value': 'daily'}),
    ('end_date', 'before_start_date', {}),
  ];

  for (final (field, type, args) in failures) {
    test('$field $type', () {
      final e = _invalid(field, type, args);
      for (final l in [tr, en]) {
        final sentence = e.localized(l);
        expect(sentence, isNot(contains('raw server text')), reason: l.localeCode);
        expect(sentence, startsWith('${l.fieldLabel(field)}: '));
        expect(e.fieldMessage(l, field), isNot('raw server text'));
      }
    });
  }

  test('an invalid parameter names the field the way the form does', () {
    final e = _refusal({
      'errors': {
        'monthly_limit_cents': ['monthly_limit_cents için geçersiz değer.'],
      },
      'code': 'invalid_parameter',
      'param': 'monthly_limit_cents',
    });
    expect(e.localized(tr), 'Sunucu bir değeri kabul etmedi (Aylık limit)');
    expect(e.localized(en), contains('Monthly limit'));
  });

  test('the finance codes, in both languages', () {
    final codes = <String, Map<String, Object?>>{
      'has_transactions': {'transactions_count': 4, 'incoming_transfers_count': 0},
      'currency_locked': {},
      'kind_locked': {},
      'amount_required': {},
      'not_chargeable': {'reason': 'no_next_charge'},
      'value_out_of_range': {},
    };
    codes.forEach((code, extra) {
      final e = _refusal({
        'errors': {
          'base': ['raw server text'],
        },
        'code': code,
        ...extra,
      });
      expect(e.localized(tr), isNot(contains('raw server text')), reason: code);
      expect(e.localized(en), isNot(contains('raw server text')), reason: code);
      expect(e.localized(tr), isNot(e.localized(en)), reason: code);
    });
  });
}
