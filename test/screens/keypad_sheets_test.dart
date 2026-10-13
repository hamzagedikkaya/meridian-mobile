/// Every sheet with the amount keypad, at 1.0 and 2.0 text on a 360 dp
/// phone, with the app's own fonts (WP-17 follow-up k). WP-9 grew the
/// keypad's keys with the text (`max(keyHeightFor(h), 34 × scale + 16)`),
/// which makes the keypad 4 × 84 dp at 2.0: each sheet must still lay out
/// without an overflow, every key must be reachable and the sheet's button
/// must stay tappable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/ui/screens/finance/budget_sheet.dart';
import 'package:meridian_mobile/ui/screens/finance/reconcile_sheet.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_value_sheet.dart';
import 'package:meridian_mobile/ui/widgets/amount_field.dart';
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart';

import '../support/app_fonts.dart';
import '../support/fake_api.dart';
import '../support/finance_harness.dart';

/// A page with one button, "open", that opens the sheet [open] shows.
Widget _launcher(void Function(BuildContext context, WidgetRef ref) open) =>
    Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => open(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
    );

final _sheets = <(String, String, void Function(BuildContext, WidgetRef))>[
  (
    'the budget sheet',
    'Kaydet',
    (context, ref) => showBudgetSheet(context),
  ),
  (
    'the amount sheet',
    'Tamam',
    (context, ref) => showAmountSheet(
      context,
      title: 'Açılış bakiyesi',
      currency: 'TRY',
      subunitToUnit: 100,
      allowDebt: true,
    ),
  ),
  (
    'the goal value sheet',
    'Tamam',
    (context, ref) => showGoalValueSheet(
      context,
      title: 'Değer gir',
      kind: const GoalValueKind.money(currency: 'TRY', subunit: 100),
    ),
  ),
  (
    'the reconcile sheet',
    'Kaydet',
    (context, ref) => showReconcileSheet(
      context,
      ref,
      Account.fromJson(accountJson(balance: 325000)),
    ),
  ),
];

FakeApi _api() => FakeApi()
  ..on('GET /accounts', {
    'accounts': [accountJson()],
  })
  ..on('GET /finance_categories', {
    'categories': [categoryJson(), categoryJson(id: 6, name: 'Kira')],
  })
  ..on('GET /budgets', budgetsJson(budgets: const [], budgetable: [5, 6]));

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    await loadAppFonts();
  });

  for (final scale in [1.0, 2.0]) {
    for (final (name, button, open) in _sheets) {
      testWidgets('$name at ${scale}x on a 360 dp phone: no overflow, every '
          'key reachable, "$button" tappable', (tester) async {
        tester.view.physicalSize = const Size(360, 780) * 3;
        tester.view.devicePixelRatio = 3.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpFinance(tester, _api(), _launcher(open));
        await tester.tap(find.text('open'));
        await settleFrames(tester);
        expect(tester.takeException(), isNull, reason: 'no overflow');
        expect(find.byType(AmountKeypad), findsOneWidget);

        // Every digit is a scroll away at most, and takes the tap.
        for (final key in ['1', '5', '9', '0']) {
          final digit = _inSheet(find.text(key)).last;
          await tester.ensureVisible(digit);
          await tester.pump();
          expect(digit.hitTestable(), findsOneWidget, reason: 'key $key');
        }
        final action = _inSheet(find.text(button)).last;
        await tester.ensureVisible(action);
        await tester.pump();
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
