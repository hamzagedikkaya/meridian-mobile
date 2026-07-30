import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/formats.dart';

void main() {
  group('formatMoney', () {
    test('TRY renders Turkish grouping + trailing symbol', () {
      expect(formatMoney(123456, 'TRY', 100), '1.234,56 ₺');
    });

    test('GAU (subunit 1) renders whole grams — never divided by 100', () {
      expect(formatMoney(412, 'GAU', 1), '412 gr');
    });

    test('signed positive gets a + prefix', () {
      expect(formatMoney(123456, 'TRY', 100, signed: true), '+1.234,56 ₺');
    });

    test('negative cents get a − (U+2212) prefix', () {
      expect(formatMoney(-5000, 'TRY', 100), '−50,00 ₺');
    });

    test('explicit negative flag on a positive magnitude', () {
      expect(formatMoney(5000, 'TRY', 100, negative: true), '−50,00 ₺');
    });

    test('zero has no sign', () {
      expect(formatMoney(0, 'TRY', 100), '0,00 ₺');
    });
  });
}
