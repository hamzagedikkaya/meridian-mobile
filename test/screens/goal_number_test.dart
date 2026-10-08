/// Goal fields read either decimal mark (a phone's keypad often has only
/// "."), grouping only where it cannot be misread, and the goal labels write
/// numbers the way the fields read them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:meridian_mobile/l10n/app_l10n_en.dart';
import 'package:meridian_mobile/l10n/app_l10n_tr.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_ui.dart';

void main() {
  tearDown(() => Intl.defaultLocale = null);

  for (final locale in ['tr', 'en']) {
    group('in $locale', () {
      setUp(() => Intl.defaultLocale = locale);

      test('a single mark is the decimal mark', () {
        expect(parseGoalNumber('12.5'), 12.5);
        expect(parseGoalNumber('12,5'), 12.5);
        expect(parseGoalNumber('0.5'), 0.5);
        expect(parseGoalNumber('0,5'), 0.5);
        expect(parseGoalNumber('1.5'), 1.5);
        expect(parseGoalNumber('72.5'), 72.5);
        expect(parseGoalNumber('7.50'), 7.5);
        expect(parseGoalNumber('0.125'), 0.125);
        expect(parseGoalNumber(' 42 '), 42);
      });

      test('well-formed grouping with both marks', () {
        expect(parseGoalNumber('1.234,5'), 1234.5);
        expect(parseGoalNumber('1,234.5'), 1234.5);
        expect(parseGoalNumber('1.234.567'), 1234567);
        expect(parseGoalNumber('1,234,567'), 1234567);
        expect(parseGoalNumber('12.345.678,25'), 12345678.25);
      });

      test('malformed numbers are refused', () {
        expect(parseGoalNumber(''), isNull);
        expect(parseGoalNumber('abc'), isNull);
        expect(parseGoalNumber('1.2.3'), isNull);
        expect(parseGoalNumber('12.34,5'), isNull);
        expect(parseGoalNumber('1,2,5.5'), isNull);
        expect(parseGoalNumber('1.234,5,6'), isNull);
        expect(parseGoalNumber('.'), isNull);
      });

      test('labels use the language mark and read back', () {
        final label = formatGoalNumber(7.5);
        expect(label, locale == 'tr' ? '7,50' : '7.50');
        expect(parseGoalNumber(label), 7.5);
        expect(parseGoalNumber(goalNumberInput(1234.5)), 1234.5);
        expect(formatGoalNumber(10), '10');
      });
    });
  }

  test('one grouping-looking mark is ambiguous in the language that groups '
      'with it, and says so', () {
    Intl.defaultLocale = 'tr';
    expect(parseGoalNumber('1.500'), isNull);
    expect(goalNumberIsAmbiguous('1.500'), isTrue);
    // The language's own decimal mark is never ambiguous.
    expect(parseGoalNumber('1,500'), 1.5);
    expect(goalNumberIsAmbiguous('12.5'), isFalse);
    expect(
      goalNumberError(const AppL10nTr(), '1.500', invalid: 'x'),
      contains('“,”'),
    );
    expect(goalNumberError(const AppL10nTr(), 'abc', invalid: 'x'), 'x');

    Intl.defaultLocale = 'en';
    expect(parseGoalNumber('1,500'), isNull);
    expect(goalNumberIsAmbiguous('1,500'), isTrue);
    expect(parseGoalNumber('1.500'), 1.5);
    expect(
      goalNumberError(const AppL10nEn(), '1,500', invalid: 'x'),
      contains('“.”'),
    );
  });
}
