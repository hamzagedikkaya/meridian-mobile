/// Edit forms compare text the way they send it — trimmed, a blank field as
/// none — so a value saved elsewhere with whitespace around it (a web
/// textarea that ends in a newline, a name with a trailing space) is not
/// "changed" by a form that left it alone: the form opens clean, and a save
/// does not rewrite it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/finance_category.dart';
import 'package:meridian_mobile/models/form_text.dart';
import 'package:meridian_mobile/models/subscription.dart';
import 'package:meridian_mobile/models/transaction.dart';

import '../support/fake_api.dart';

void main() {
  test('asFormText: trimmed, and a blank one is none', () {
    expect(asFormText('web notu\r\n'), 'web notu');
    expect(asFormText('  Kahve '), 'Kahve');
    expect(asFormText(' \n '), isNull);
    expect(asFormText(''), isNull);
    expect(asFormText(null), isNull);
    expect(formTextChanged('web notu', 'web notu\r\n'), isFalse);
    expect(formTextChanged(null, '  '), isFalse);
    expect(formTextChanged('yeni', 'web notu'), isTrue);
  });

  group('a transaction', () {
    final before = Transaction.fromJson({
      ...transactionJson(),
      'description': ' Kahve ',
      'note': 'web notu\r\n',
    });
    TransactionInput input({String? description, String? note}) =>
        TransactionInput(
          kind: 'expense',
          amountCents: 13874,
          date: DateTime(2026, 10, 4),
          description: description,
          note: note,
          accountId: 1,
        );

    test('left alone, its note and description are no change', () {
      expect(input(description: 'Kahve', note: 'web notu').changesFrom(before),
          isEmpty);
    });

    test('changed, they go trimmed; cleared, as null', () {
      expect(
        input(description: 'Kahve', note: ' yeni not\n').changesFrom(before),
        {'note': 'yeni not'},
      );
      expect(input(note: 'web notu').changesFrom(before),
          {'description': null});
    });
  });

  group('a subscription', () {
    final before = Subscription.fromJson({
      ...subscriptionJson(name: 'Netflix '),
      'vendor': 'Netflix Inc. ',
      'note': 'aile planı\n',
    });
    SubscriptionInput input({
      String name = 'Netflix',
      String? vendor = 'Netflix Inc.',
      String? note = 'aile planı',
    }) =>
        SubscriptionInput(
          name: name,
          accountId: 1,
          amountCents: 22999,
          frequency: 'monthly',
          nextChargeOn: DateTime(2026, 10, 15),
          vendor: vendor,
          note: note,
          color: '#B8860B',
        );

    test('left alone, its name, vendor and note are no change', () {
      expect(input().changesFrom(before, accountCurrency: 'TRY'), isEmpty);
    });

    test('changed, they go trimmed; cleared, as null', () {
      expect(
        input(name: 'Netflix Aile', vendor: null)
            .changesFrom(before, accountCurrency: 'TRY'),
        {'name': 'Netflix Aile', 'vendor': null},
      );
    });
  });

  test('an account\'s name, left alone, is no change', () {
    final before = Account.fromJson(accountJson(name: 'Cüzdan '));
    AccountInput input(String name) => AccountInput(
          name: name,
          accountType: 'cash',
          currency: 'TRY',
          color: '#D4A574',
        );
    expect(input('Cüzdan').changesFrom(before), isEmpty);
    expect(input('Nakit').changesFrom(before), {'name': 'Nakit'});
  });

  test('a category\'s name, left alone, is no change', () {
    final before = TxCategory.fromJson(categoryJson(name: 'Market\t'));
    CategoryInput input(String name) =>
        CategoryInput(name: name, kind: 'expense', color: '#D4915A');
    expect(input('Market').changesFrom(before), isEmpty);
    expect(input('Bakkal').changesFrom(before), {'name': 'Bakkal'});
  });
}
