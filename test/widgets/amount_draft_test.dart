/// The money entry every form shares: digits typed on the keypad, the
/// decimal mark of the language, the currency's decimals, and the limit of
/// what the server can store.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:meridian_mobile/core/formats.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_utils.dart';
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart';

AmountDraft _typed(String keys, {int subunit = 100}) {
  var draft = const AmountDraft();
  for (final key in keys.split('')) {
    draft = key == ','
        ? draft.withDecimalMark(subunit)
        : draft.withDigit(key, subunit);
  }
  return draft;
}

void main() {
  setUp(() => Intl.defaultLocale = 'tr');

  group('AmountDraft', () {
    test('digits and the decimal mark make minor units', () {
      expect(_typed('1250').minorUnits(100), 125000);
      expect(_typed('12,5').minorUnits(100), 1250);
      expect(_typed(',5').text, '0,5');
      expect(_typed('12,50').minorUnits(100), 1250);
    });

    test('no more decimals than the currency has; none for gram gold', () {
      expect(_typed('1,999').text, '1,99');
      expect(_typed('12,5', subunit: 1).text, '125');
      expect(_typed('12,5', subunit: 1).minorUnits(1), 125);
    });

    test('a leading zero is replaced, not followed', () {
      expect(_typed('05').text, '5');
      expect(_typed('0,05').minorUnits(100), 5);
    });

    test('entry stops at what a 4-byte column holds, and says why', () {
      final most = _typed('21474836,47');
      expect(most.minorUnits(100), AmountDraft.maxMinorUnits);
      final almost = _typed('21474836,4');
      expect(almost.wouldPassLimit('8', 100), isTrue);
      expect(almost.withDigit('8', 100), almost);
      expect(almost.wouldPassLimit('7', 100), isFalse);
      // A decimal the currency does not take is refused for that, not the
      // limit.
      expect(most.wouldPassLimit('1', 100), isFalse);
      expect(_typed('2147483647', subunit: 1).wouldPassLimit('0', 1), isTrue);
    });

    test('backspace and back from minor units', () {
      expect(_typed('12,5').backspace().text, '12,');
      expect(const AmountDraft().backspace().text, '');
      expect(AmountDraft.fromMinorUnits(125050, 100).text, '1250,5');
      expect(AmountDraft.fromMinorUnits(-125000, 100).text, '1250');
      expect(AmountDraft.fromMinorUnits(412, 1).text, '412');
      expect(AmountDraft.fromMinorUnits(0, 100).isEmpty, isTrue);
    });

    test('moving to a currency without decimals drops them', () {
      expect(_typed('12,75').forCurrency(1).text, '12');
      expect(_typed('12,75').forCurrency(100).text, '12,75');
      expect(_typed('12').forCurrency(1).text, '12');
    });

    test('shown as money in the language, as far as it is typed', () {
      expect(_typed('1250,5').display('TRY'), '₺1.250,5');
      expect(_typed('12,').display('TRY'), '₺12,');
      expect(const AmountDraft().display('TRY'), '₺0');
      expect(_typed('1234').display('USD', negative: true), '−\$1.234');
      Intl.defaultLocale = 'en';
      expect(_typed('1250,5').display('TRY'), '₺1,250.5');
    });
  });

  group('formats', () {
    test('decimals follow the minor unit', () {
      expect(decimalsFor(100), 2);
      expect(decimalsFor(1), 0);
      expect(decimalsFor(1000), 3);
      expect(formatMoney(1234567, 'KWD', 1000, locale: 'tr'), 'KWD\u00A01.234,567');
    });

    test('the pound has its symbol', () {
      expect(formatMoney(999, 'GBP', 100, locale: 'en'), '£9.99');
    });

    test('the keypad\'s decimal key follows the language', () {
      expect(decimalMark(locale: 'tr'), ',');
      expect(decimalMark(locale: 'en'), '.');
    });
  });

  group('drilling into İşlemler', () {
    test('the filters go into the route and come back out', () {
      final filters = TxFilters(
        kind: 'expense',
        uncategorized: true,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
      );
      final location = transactionsLocation(filters);
      expect(location,
          '/finance/transactions?kind=expense&category=none&from=2026-10-01&to=2026-10-31');
      expect(filtersFromQuery(Uri.parse(location).queryParameters), filters);
      expect(
        filtersFromQuery(Uri.parse(transactionsLocation(
                const TxFilters(categoryId: 5, accountId: 2)))
            .queryParameters),
        const TxFilters(categoryId: 5, accountId: 2),
      );
      expect(transactionsLocation(const TxFilters()), '/finance/transactions');
    });

    test('what cannot be read is left out', () {
      expect(
        filtersFromQuery(const {'kind': 'nope', 'from': '2026-10-01'}),
        const TxFilters(),
        reason: 'an unknown kind; a range needs both ends',
      );
    });
  });
}
