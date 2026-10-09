import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/formats.dart';

/// The money and number table of design-analysis §3.7, verbatim, in both
/// languages.
void main() {
  const nb = ' ';
  const minus = '−';

  group('formatMoney — TRY', () {
    test('a positive amount: symbol first, no space', () {
      expect(formatMoney(123456, 'TRY', 100, locale: 'tr'), '₺1.234,56');
      expect(formatMoney(123456, 'TRY', 100, locale: 'en'), '₺1,234.56');
    });

    test('signed income: + before the symbol', () {
      expect(
        formatMoney(150000, 'TRY', 100, sign: MoneySign.always, locale: 'tr'),
        '+₺1.500,00',
      );
      expect(
        formatMoney(150000, 'TRY', 100, sign: MoneySign.always, locale: 'en'),
        '+₺1,500.00',
      );
    });

    test('an expense: U+2212 before the symbol', () {
      expect(formatMoney(-25000, 'TRY', 100, locale: 'tr'), '−₺250,00');
      expect(formatMoney(-25000, 'TRY', 100, locale: 'en'), '−₺250.00');
      expect(formatMoney(-25000, 'TRY', 100, locale: 'tr').startsWith(minus),
          isTrue);
      expect(
        formatMoney(25000, 'TRY', 100, sign: MoneySign.negative, locale: 'tr'),
        '−₺250,00',
      );
    });

    test('an exact zero is "₺0" in every variant, without a sign', () {
      for (final locale in ['tr', 'en']) {
        for (final sign in MoneySign.values) {
          for (final decimals in MoneyDecimals.values) {
            expect(
              formatMoney(0, 'TRY', 100,
                  sign: sign, decimals: decimals, locale: locale),
              '₺0',
              reason: '$locale $sign $decimals',
            );
          }
        }
        expect(formatMoney(0, 'TRY', 100, signed: true, locale: locale), '₺0');
        expect(
            formatMoney(0, 'TRY', 100, negative: true, locale: locale), '₺0');
      }
    });

    test('automatic decimals drop zero minor units only', () {
      expect(
        formatMoney(4275000, 'TRY', 100,
            decimals: MoneyDecimals.auto, locale: 'tr'),
        '₺42.750',
      );
      expect(
        formatMoney(4275050, 'TRY', 100,
            decimals: MoneyDecimals.auto, locale: 'tr'),
        '₺42.750,50',
      );
      expect(
        formatMoney(4275000, 'TRY', 100,
            decimals: MoneyDecimals.auto, locale: 'en'),
        '₺42,750',
      );
      expect(
        formatMoney(4275050, 'TRY', 100,
            decimals: MoneyDecimals.auto, locale: 'en'),
        '₺42,750.50',
      );
    });

    test('millions group in both languages', () {
      expect(formatMoney(123456789, 'TRY', 100, locale: 'tr'), '₺1.234.567,89');
      expect(formatMoney(123456789, 'TRY', 100, locale: 'en'), '₺1,234,567.89');
      expect(
        formatMoney(123456789, 'TRY', 100,
            sign: MoneySign.always, locale: 'tr'),
        '+₺1.234.567,89',
      );
    });

    test('the older flags still work: signed → always, negative → negative',
        () {
      expect(formatMoney(123456, 'TRY', 100, signed: true, locale: 'tr'),
          '+₺1.234,56');
      expect(formatMoney(5000, 'TRY', 100, negative: true, locale: 'tr'),
          '−₺50,00');
      expect(formatMoney(-5000, 'TRY', 100, signed: true, locale: 'tr'),
          '−₺50,00');
    });

    test('MoneySign.none writes the magnitude', () {
      expect(formatMoney(-5000, 'TRY', 100, sign: MoneySign.none, locale: 'tr'),
          '₺50,00');
    });
  });

  group('formatMoney — USD, GAU and codes without a symbol', () {
    test(r'USD: $ in front, both languages', () {
      expect(formatMoney(123456, 'USD', 100, locale: 'tr'), r'$1.234,56');
      expect(formatMoney(123456, 'USD', 100, locale: 'en'), r'$1,234.56');
      expect(formatMoney(-25000, 'USD', 100, locale: 'en'), '−\$250.00');
      expect(formatMoney(0, 'USD', 100, locale: 'en'), r'$0');
    });

    test('GAU (subunit 1): whole grams, unit after a no-break space', () {
      expect(formatMoney(412, 'GAU', 1, locale: 'tr'), '412${nb}gr');
      expect(formatMoney(412, 'GAU', 1, locale: 'en'), '412${nb}g');
      expect(formatMoney(1500, 'GAU', 1, locale: 'tr'), '1.500${nb}gr');
      expect(formatMoney(412, 'GAU', 1, signed: true, locale: 'tr'),
          '+412${nb}gr');
      expect(formatMoney(0, 'GAU', 1, locale: 'tr'), '0${nb}gr');
    });

    test('a code without a symbol goes first, across a no-break space', () {
      expect(formatMoney(123456, 'CHF', 100, locale: 'tr'), 'CHF${nb}1.234,56');
      expect(formatMoney(123456, 'CHF', 100, locale: 'en'), 'CHF${nb}1,234.56');
      expect(formatMoney(-123456, 'CHF', 100, locale: 'tr'),
          '−CHF${nb}1.234,56');
    });

    test('never a plain space, never U+202F', () {
      for (final s in [
        formatMoney(412, 'GAU', 1, locale: 'tr'),
        formatMoney(123456, 'CHF', 100, locale: 'en'),
        formatMoney(123456, 'TRY', 100, locale: 'tr'),
        formatMoneyCompact(4750000, 'TRY', 100, locale: 'tr'),
      ]) {
        expect(s.contains(' '), isFalse, reason: s);
        expect(s.contains(' '), isFalse, reason: s);
      }
    });

    test('currencySymbol', () {
      expect(currencySymbol('TRY'), '₺');
      expect(currencySymbol('GAU', locale: 'tr'), 'gr');
      expect(currencySymbol('GAU', locale: 'en'), 'g');
      expect(currencySymbol('CHF'), 'CHF');
    });
  });

  group('formatMoneyCompact', () {
    test('the threshold: 9.999 stays whole, 10.000 abbreviates', () {
      expect(formatMoneyCompact(999900, 'TRY', 100, locale: 'tr'), '₺9.999');
      expect(formatMoneyCompact(999950, 'TRY', 100, locale: 'tr'),
          '₺9.999,50');
      expect(formatMoneyCompact(1000000, 'TRY', 100, locale: 'tr'), '₺10B');
      expect(formatMoneyCompact(1000000, 'TRY', 100, locale: 'en'), '₺10K');
    });

    test('one decimal, a trailing zero decimal dropped', () {
      expect(formatMoneyCompact(4750000, 'TRY', 100, locale: 'tr'), '₺47,5B');
      expect(formatMoneyCompact(120000000, 'TRY', 100, locale: 'tr'),
          '₺1,2Mn');
      expect(formatMoneyCompact(340000000000, 'TRY', 100, locale: 'tr'),
          '₺3,4Mr');
      expect(formatMoneyCompact(4750000, 'TRY', 100, locale: 'en'), '₺47.5K');
      expect(formatMoneyCompact(120000000, 'TRY', 100, locale: 'en'), '₺1.2M');
      expect(formatMoneyCompact(340000000000, 'TRY', 100, locale: 'en'),
          '₺3.4B');
      expect(formatMoneyCompact(3300000, 'TRY', 100, locale: 'tr'), '₺33B');
    });

    test('rounding into the next magnitude', () {
      expect(formatMoneyCompact(99999000, 'TRY', 100, locale: 'en'), '₺1M');
    });

    test('signs and other currencies', () {
      expect(
        formatMoneyCompact(-124000000, 'TRY', 100, locale: 'tr'),
        '−₺1,2Mn',
      );
      expect(
        formatMoneyCompact(4750000, 'TRY', 100,
            sign: MoneySign.always, locale: 'tr'),
        '+₺47,5B',
      );
      expect(formatMoneyCompact(0, 'TRY', 100, locale: 'tr'), '₺0');
      expect(formatMoneyCompact(12500, 'GAU', 1, locale: 'tr'), '12,5B${nb}gr');
    });
  });

  group('formatPercent', () {
    test('the sign where the language puts it', () {
      expect(formatPercent(62, locale: 'tr'), '%62');
      expect(formatPercent(62, locale: 'en'), '62%');
      expect(formatPercent(61.6, locale: 'tr'), '%62');
    });
  });

  group('formatTypedAmount', () {
    test('symbol first while typing', () {
      expect(
        formatTypedAmount(
            whole: '1250', fraction: '5', currency: 'TRY', locale: 'tr'),
        '₺1.250,5',
      );
      expect(
        formatTypedAmount(
            whole: '12', fraction: '', currency: 'TRY', locale: 'tr'),
        '₺12,',
      );
      expect(
        formatTypedAmount(
            whole: '12', currency: 'TRY', negative: true, locale: 'tr'),
        '−₺12',
      );
      expect(formatTypedAmount(whole: '0', currency: 'TRY', locale: 'en'),
          '₺0');
      expect(formatTypedAmount(whole: '412', currency: 'GAU', locale: 'tr'),
          '412${nb}gr');
    });
  });
}
