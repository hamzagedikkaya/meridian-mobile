/// Larger text — up to 200% (design-research §6.2) — on the finance
/// screens, measured with the app's own fonts on a small phone (360×640):
/// rows and account cards grow taller instead of overflowing, and the
/// transaction form's kind pill shrinks to the width there is. At the
/// normal size nothing moves: rows stay 64 dp, cards 140 dp. The amount
/// sheet keeps "Tamam" in reach where its keypad does not fit: in
/// landscape, and on a small phone at 200%.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/ui/screens/finance/account_card.dart';
import 'package:meridian_mobile/ui/screens/finance/archived_accounts_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/subscriptions_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/transaction_form_screen.dart';
import 'package:meridian_mobile/ui/widgets/amount_field.dart';
import 'package:meridian_mobile/ui/widgets/nokturn_row.dart';

import '../support/app_fonts.dart';
import '../support/fake_api.dart';
import '../support/finance_harness.dart';

/// A small phone, 360×640, with the system text size at [scale].
void _smallPhone(WidgetTester tester, double scale) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// A page that opens the transaction form, as Finance does.
Widget _formLauncher() => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => openTransactionForm(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

/// A page that opens the amount sheet as the account form does — with the
/// "Borç" switch, as tall as the sheet gets; [onResult] gets the amount it
/// closed with.
Widget _amountLauncher(ValueChanged<int?> onResult) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => onResult(await showAmountSheet(
              context,
              title: 'Açılış bakiyesi',
              currency: 'TRY',
              subunitToUnit: 100,
              allowDebt: true,
            )),
            child: const Text('open'),
          ),
        ),
      ),
    );

FakeApi _api() => FakeApi()
  ..on('GET /accounts', {
    'accounts': [
      accountJson(name: 'Maaş hesabı', type: 'bank', balance: 4569095000),
      accountJson(id: 4, name: 'Eski kredi kartı', type: 'credit_card',
          balance: -123456, archived: true),
    ],
  })
  ..on('GET /subscriptions', subscriptionsJson(
    active: [subscriptionJson(name: 'Netflix Premium', next: '2020-01-15')],
    inactive: [subscriptionJson(id: 8, name: 'Gazete', active: false)],
  ));

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await initializeDateFormatting();
  });

  for (final scale in const [1.6, 2.0]) {
    group('text at ${scale}x', () {
      for (final locale in const [Locale('tr'), Locale('en')]) {
        testWidgets('the transaction form (${locale.languageCode}): the kind '
            'pill stays on screen', (tester) async {
          _smallPhone(tester, scale);
          await pumpFinance(tester, _api(), _formLauncher(), locale: locale);
          await tester.tap(find.text('open'));
          await settleFrames(tester);
          expect(tester.takeException(), isNull);
          final kinds = locale.languageCode == 'tr'
              ? ['Gider', 'Gelir', 'Transfer']
              : ['Expense', 'Income', 'Transfer'];
          for (final kind in kinds) {
            final box = tester.getRect(find.text(kind));
            expect(box.left, greaterThanOrEqualTo(0), reason: kind);
            expect(box.right, lessThanOrEqualTo(360), reason: kind);
          }
        });
      }

      testWidgets('Abonelikler: rows grow with their text', (tester) async {
        _smallPhone(tester, scale);
        await pumpFinance(tester, _api(), const SubscriptionsScreen());
        expect(tester.takeException(), isNull);
        expect(find.text('Netflix Premium'), findsOneWidget);
        expect(tester.getSize(find.byType(NokturnRow).first).height,
            greaterThan(64));
      });

      testWidgets('Arşivlenmiş hesaplar: rows grow with their text',
          (tester) async {
        _smallPhone(tester, scale);
        await pumpFinance(tester, _api(), const ArchivedAccountsScreen());
        expect(tester.takeException(), isNull);
        expect(find.text('Eski kredi kartı'), findsOneWidget);
        expect(tester.getSize(find.byType(NokturnRow).first).height,
            greaterThan(64));
      });

      testWidgets('Finance: the account cards — and the carousel — grow with '
          'their text', (tester) async {
        _smallPhone(tester, scale);
        await pumpFinance(tester, _api(), const FinanceScreen());
        await tester.dragUntilVisible(find.byType(AccountCard),
            find.byType(ListView).first, const Offset(0, -100));
        await settleFrames(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Maaş hesabı'), findsOneWidget);
        expect(tester.getSize(find.byType(AccountCard)).height,
            greaterThan(AccountCard.minHeight));
      });
    });
  }

  for (final (screen, size, scale) in const [
    ('in landscape, 640×360', Size(640, 360), 1.0),
    ('in landscape, 844×390', Size(844, 390), 1.0),
    ('on a 320×568 phone at 200%', Size(320, 568), 2.0),
  ]) {
    testWidgets('the amount sheet $screen: the keypad scrolls, and "Tamam" '
        'stays on screen to confirm the amount', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      int? result;
      await pumpFinance(tester, FakeApi(), _amountLauncher((v) => result = v));
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.text('Tamam').hitTestable(), findsOneWidget);

      // The keys below the fold are a scroll away; "Tamam" stays put.
      for (final key in ['1', '0']) {
        await tester.ensureVisible(find.text(key));
        await tester.pump();
        await tester.tap(find.text(key));
        await tester.pump();
      }
      expect(find.text('Tamam').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Tamam'));
      await settleFrames(tester);
      expect(result, 1000);
    });
  }

  testWidgets('at the normal size, rows stay 64 dp and cards 140 dp',
      (tester) async {
    _smallPhone(tester, 1.0);
    await pumpFinance(tester, _api(), const SubscriptionsScreen());
    expect(tester.getSize(find.byType(NokturnRow).first).height, 64);

    await pumpFinance(tester, _api(), const FinanceScreen());
    await tester.dragUntilVisible(find.byType(AccountCard),
        find.byType(ListView).first, const Offset(0, -100));
    await settleFrames(tester);
    expect(tester.getSize(find.byType(AccountCard)).height,
        AccountCard.minHeight);
  });
}
