/// Budgets from the dashboard's card (contract G2.5): only an expense
/// top-level category without a budget, a limit above zero on the keypad,
/// spent against the limit, edit and remove with "Geri al".
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/haptics.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
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

  testWidgets('the category list still loading is not "none left": a '
      'spinner, then the categories',
      (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance/dashboard', _dashboard())
      ..on('GET /budgets', budgetsJson(budgets: const [], budgetable: [5]))
      ..hold('GET /finance_categories');
    await pumpFinance(tester, api, const FinanceScreen());
    await tester.tap(find.text('Bütçe koy'));
    await settleFrames(tester);
    expect(_inSheet(find.textContaining('kategori kalmadı')), findsNothing);
    expect(_inSheet(find.text('Yeni kategori')), findsNothing);
    expect(_inSheet(find.byType(CircularProgressIndicator)), findsOneWidget);
    api.release('GET /finance_categories');
    await settleFrames(tester);
    expect(_inSheet(find.text('Market')), findsOneWidget);
  });

  testWidgets('a category list that fails: the server is unreachable, with a '
      'retry — never "none left"', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance/dashboard', _dashboard())
      ..on('GET /budgets', budgetsJson(budgets: const [], budgetable: [5]))
      ..failNetwork('GET /finance_categories');
    await pumpFinance(tester, api, const FinanceScreen());
    await tester.tap(find.text('Bütçe koy'));
    await settleFrames(tester);
    expect(_inSheet(find.textContaining('kategori kalmadı')), findsNothing);
    expect(_inSheet(find.text('Sunucuya ulaşılamıyor')), findsOneWidget);

    api.on('GET /finance_categories', {
      'categories': [categoryJson()],
    });
    await tester.tap(_inSheet(find.text('Tekrar dene')));
    await settleFrames(tester);
    expect(_inSheet(find.text('Market')), findsOneWidget);
  });

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
    // No budget yet: the setup card offers one (it carries the budgets'
    // empty card while it shows).
    expect(find.text('Kurulum 3/4'), findsOneWidget);
    await tester.tap(find.text('Bütçe koy'));
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
    expect(find.text('₺661 / ₺3.000'), findsOneWidget);
    // What may still go out each day.
    expect(find.textContaining(RegExp('gün kaldı|son gün')), findsOneWidget);

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

  testWidgets('the sheet takes input: it has an X; "Bütçeyi kaldır" sits 24 '
      'dp under "Kaydet", in error; a save confirms', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance/dashboard', _dashboard(budgets: [budgetJson()]));
    await pumpFinance(tester, api, const FinanceScreen());
    await _toBudgets(tester);
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    expect(_inSheet(find.byTooltip('Kapat')), findsOneWidget);
    final save = tester.getRect(_inSheet(find.byType(FilledButton)));
    final remove = tester.getRect(_inSheet(find.text('Bütçeyi kaldır')));
    expect(remove.top - save.bottom, greaterThanOrEqualTo(24));
    final label = _inSheet(find.text('Bütçeyi kaldır'));
    expect(
      tester.renderObject<RenderParagraph>(label).text.style?.color,
      tester.element(label).nok.error,
    );
    await tester.tap(_inSheet(find.byTooltip('Kapat')));
    await settleFrames(tester);
    expect(find.byType(BottomSheet), findsNothing);

    // A save confirms (§5.8): the success notification, not a light tap.
    final played = <Object?>[];
    Haptics.debugReset(androidSdk: 34);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') played.add(call.arguments);
        return null;
      },
    );
    addTearDown(() {
      Haptics.debugReset();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    await tester.longPress(_inSheet(find.byIcon(Icons.backspace_outlined)));
    await tester.pump();
    await _type(tester, '4000');
    played.clear();
    await tester.tap(_inSheet(find.text('Kaydet')));
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /budgets/2'), isNotEmpty);
    expect(played, contains('HapticFeedbackType.successNotification'));
    expect(played, isNot(contains('HapticFeedbackType.lightImpact')));
  });

  testWidgets('a budget over its limit says by how much', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance/dashboard', _dashboard(
        budgets: [budgetJson(limit: 50000, spent: 84000)],
      ));
    await pumpFinance(tester, api, const FinanceScreen());
    await _toBudgets(tester);
    expect(find.text('₺340 fazla'), findsOneWidget);
    expect(find.text('Limiti düzenle'), findsOneWidget);
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
    expect(find.text('₺661 / ₺3.000'), findsNothing, reason: 'off');
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
    await tester.tap(find.text('Bütçe koy'));
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
