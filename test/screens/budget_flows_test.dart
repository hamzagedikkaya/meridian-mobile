/// Budgets from the dashboard's card (contract G2.5): only an expense
/// top-level category without a budget, a limit above zero on the keypad,
/// spent against the limit, edit and remove with "Geri al".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';

import '../support/fake_api.dart';
import '../support/finance_harness.dart';

Map<String, dynamic> _dashboard({List<Map<String, dynamic>> budgets = const []}) => {
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'month': {'income_cents': 0, 'expense_cents': 66100, 'net_cents': -66100},
      'year': {'income_cents': 0, 'expense_cents': 66100},
      'six_month_series': {'labels': [], 'income_cents': [], 'expense_cents': []},
      'pie': [],
      'budgets': budgets,
      'upcoming_subscriptions': [],
      'recent_transactions': [transactionJson()],
    };

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

Future<void> _toBudgets(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.text('Bütçeler'),
    find.byType(ListView).first,
    const Offset(0, -300),
  );
  await settleFrames(tester);
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(_inSheet(find.text(digit)).last);
    await tester.pump();
  }
}

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('a new budget: only the categories that can take one, a limit '
      'on the keypad', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance/dashboard', _dashboard())
      ..on('GET /finance_categories', {
        'categories': [
          categoryJson(),
          categoryJson(id: 6, name: 'Kira'),
          categoryJson(id: 7, name: 'Maaş', kind: 'income'),
        ],
      })
      ..on('GET /budgets', budgetsJson(budgets: const [], budgetable: [5]));
    await pumpFinance(tester, api, const FinanceScreen());
    await _toBudgets(tester);
    expect(
      find.text('Bir kategoriye aylık sınır koy, ay sonunu önceden gör.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Ekle'));
    await settleFrames(tester);
    expect(_inSheet(find.text('Yeni bütçe')), findsOneWidget);
    expect(_inSheet(find.text('Market')), findsOneWidget);
    expect(_inSheet(find.text('Kira')), findsNothing, reason: 'not budgetable');
    expect(_inSheet(find.text('Maaş')), findsNothing, reason: 'income');

    // Neither a category nor a limit yet.
    await tester.tap(_inSheet(find.text('Kaydet')));
    await settleFrames(tester);
    expect(_inSheet(find.text('Bir kategori seç')), findsOneWidget);
    expect(_inSheet(find.text('Sıfırdan büyük bir limit gir')), findsOneWidget);
    expect(api.bodiesOf('POST /budgets'), isEmpty);

    await tester.tap(_inSheet(find.text('Market')));
    await tester.pump();
    await _type(tester, '3000');
    await tester.tap(_inSheet(find.text('Kaydet')));
    await settleFrames(tester);
    expect(api.bodiesOf('POST /budgets').single,
        {'finance_category_id': 5, 'monthly_limit_cents': 300000});
    expect(find.text('Bütçe eklendi'), findsOneWidget);
  });

  testWidgets('the card says spent against the limit; a tap changes the '
      'limit', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance/dashboard', _dashboard(budgets: [budgetJson()]));
    await pumpFinance(tester, api, const FinanceScreen());
    await _toBudgets(tester);
    expect(find.text('₺661,00 / ₺3.000,00'), findsOneWidget);
    expect(find.text('kalan ₺2.339,00'), findsOneWidget);

    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    expect(_inSheet(find.text('Market bütçesi')), findsOneWidget);
    await tester.longPress(_inSheet(find.byIcon(Icons.backspace_outlined)));
    await tester.pump();
    await _type(tester, '4000');
    await tester.tap(_inSheet(find.text('Kaydet')));
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /budgets/2').single,
        {'monthly_limit_cents': 400000});
  });

  testWidgets('a budget over its limit says by how much', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance/dashboard', _dashboard(
        budgets: [budgetJson(limit: 50000, spent: 84000)],
      ));
    await pumpFinance(tester, api, const FinanceScreen());
    await _toBudgets(tester);
    expect(find.text('₺340,00 fazla'), findsOneWidget);
  });

  testWidgets('removing a budget goes with "Geri al"', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance/dashboard', _dashboard(budgets: [budgetJson()]));
    await pumpFinance(tester, api, const FinanceScreen());
    await _toBudgets(tester);
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    await tester.tap(_inSheet(find.text('Bütçeyi kaldır')));
    await settleFrames(tester);
    expect(find.text('“Market” bütçesi kaldırıldı'), findsOneWidget);
    expect(find.text('₺661,00 / ₺3.000,00'), findsNothing, reason: 'off');
    expect(api.requests, isNot(contains('DELETE /budgets/2')));
    await letUndoRunOut(tester);
    expect(api.requests, contains('DELETE /budgets/2'));
  });

  testWidgets('nothing left to budget: the sheet makes the category, then '
      'the budget goes on it', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance/dashboard', _dashboard())
      ..on('GET /budgets', budgetsJson(budgets: const []));
    await pumpFinance(tester, api, const FinanceScreen());
    await _toBudgets(tester);
    await tester.tap(find.text('Ekle'));
    await settleFrames(tester);
    expect(
      _inSheet(find.text('Bütçe konabilecek bir gider kategorisi kalmadı. '
          'Önce bir tane ekle.')),
      findsOneWidget,
    );
    await tester.tap(_inSheet(find.text('Yeni kategori')));
    await settleFrames(tester);
    await tester.enterText(_inSheet(find.byType(TextField)), 'Eğlence');
    await tester.tap(_inSheet(find.text('Ekle')));
    await settleFrames(tester);
    // A top-level expense category: what a budget needs.
    expect(api.bodiesOf('POST /finance_categories').single, {
      'name': 'Eğlence',
      'kind': 'expense',
      'parent_id': null,
      'color': '#6B8E5A',
    });
    await _type(tester, '500');
    await tester.tap(_inSheet(find.text('Kaydet')));
    await settleFrames(tester);
    expect(api.bodiesOf('POST /budgets').single,
        {'finance_category_id': 9, 'monthly_limit_cents': 50000});
  });
}
