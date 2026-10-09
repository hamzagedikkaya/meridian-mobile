import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/turkish_case.dart';

void main() {
  test('upper case pairs i with İ and ı with I', () {
    expect(trUpper('istanbul ılık'), 'İSTANBUL ILIK');
    expect(trUpper('çiğdem şükrü öz'), 'ÇİĞDEM ŞÜKRÜ ÖZ');
  });

  test('lower case pairs I with ı and İ with i, without a combining dot', () {
    expect(trLower('IŞIK İZMİR'), 'ışık izmir');
    expect(trLower('İ').length, 1);
  });

  test('capitalize touches only the first character', () {
    expect(trCapitalize('ilker'), 'İlker');
    expect(trCapitalize('ırmak'), 'Irmak');
    expect(trCapitalize(''), '');
    expect(trCapitalize('😀 a'), '😀 a');
  });

  test('fold meets every spelling of the same word', () {
    expect(trFold('IŞIK'), trFold('ışık'));
    expect(trFold('Işık'), trFold('işik'));
    expect(trFold('İstanbul'), trFold('istanbul'));
  });
}
