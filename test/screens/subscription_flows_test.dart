/// Subscriptions from the phone (contract G2.6): the Abonelikler page with
/// what they cost, the form, and the sheet that records a payment, pauses,
/// edits and deletes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/subscriptions_screen.dart';

import '../support/fake_api.dart';
import '../support/finance_harness.dart';

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

FakeApi _api() => FakeApi()
  ..on('GET /subscriptions', subscriptionsJson(
    inactive: [subscriptionJson(id: 8, name: 'Gazete', active: false)],
  ));

Future<void> _openSheet(WidgetTester tester, FakeApi api) async {
  await pumpFinance(tester, api, const SubscriptionsScreen());
  await tester.tap(find.text('Netflix'));
  await settleFrames(tester);
  expect(_inSheet(find.text('Netflix')), findsOneWidget);
}

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('what the active ones cost, then active and paused',
      (tester) async {
    tallPhone(tester);
    await pumpFinance(tester, _api(), const SubscriptionsScreen());
    expect(find.text('Aylık sabit giderin 229,99 ₺'), findsOneWidget);
    expect(find.text('yılda 2.759,88 ₺'), findsOneWidget);
    expect(find.text('Aktif'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Duraklatılmış'), findsOneWidget);
    expect(find.text('Gazete'), findsOneWidget);
  });

  testWidgets('a new one: name and amount needed; the first due date is the '
      'server\'s to propose', (tester) async {
    tallPhone(tester);
    final api = _api();
    await pumpFinance(tester, api, const SubscriptionsScreen());
    await tester.tap(find.byType(FloatingActionButton));
    await settleFrames(tester);
    expect(find.text('Yeni abonelik'), findsOneWidget);

    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    expect(find.text('Bir ad gir'), findsOneWidget);
    expect(find.text('Sıfırdan büyük bir tutar gir'), findsOneWidget);
    expect(api.bodiesOf('POST /subscriptions'), isEmpty);

    await tester.enterText(find.byType(TextField).first, 'Spotify');
    await tester.tap(find.text('Tutar').first);
    await settleFrames(tester);
    for (final key in ['9', '9', ',', '9', '9']) {
      await tester.tap(_inSheet(find.text(key)).last);
      await tester.pump();
    }
    await tester.tap(_inSheet(find.text('Tamam')));
    await settleFrames(tester);
    await tester.tap(find.text('Yıllık'));
    await tester.pump();
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    final body = api.bodiesOf('POST /subscriptions').single as Map;
    expect(body['name'], 'Spotify');
    expect(body['account_id'], 1);
    expect(body['amount_cents'], 9999);
    expect(body['frequency'], 'yearly');
    expect(body.containsKey('next_charge_on'), isFalse);
    expect(find.text('Abonelik eklendi ✓'), findsOneWidget);
  });

  testWidgets('"Ödendi olarak kaydet" records the payment', (tester) async {
    tallPhone(tester);
    final api = _api();
    await _openSheet(tester, api);
    await tester.tap(_inSheet(find.text('Ödendi olarak kaydet')));
    await settleFrames(tester);
    expect(api.requests, contains('POST /subscriptions/6/charge'));
    expect(find.text('Ödeme kaydedildi · 229,99 ₺'), findsOneWidget);
  });

  testWidgets('a payment refused because it was paused elsewhere says so in '
      'the app\'s words', (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on('POST /subscriptions/6/charge', {
        'errors': {'base': ['Only an active subscription can be charged.']},
        'code': 'not_chargeable',
        'reason': 'inactive',
      }, status: 422);
    await _openSheet(tester, api);
    await tester.tap(_inSheet(find.text('Ödendi olarak kaydet')));
    await settleFrames(tester);
    expect(
      find.text('Duraklatılmış bir abonelik ödendi olarak işaretlenemez'),
      findsOneWidget,
    );
  });

  testWidgets('pause sends active=false', (tester) async {
    tallPhone(tester);
    final api = _api();
    await _openSheet(tester, api);
    await tester.tap(_inSheet(find.text('Durdur')));
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /subscriptions/6').single, {'active': false});
    expect(find.text('“Netflix” durduruldu'), findsOneWidget);
  });

  testWidgets('edit sends only what changed', (tester) async {
    tallPhone(tester);
    final api = _api();
    await _openSheet(tester, api);
    await tester.tap(_inSheet(find.text('Düzenle')));
    await settleFrames(tester);
    expect(find.text('Aboneliği düzenle'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Netflix Aile');
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /subscriptions/6').single,
        {'name': 'Netflix Aile'});
  });

  testWidgets('delete goes with "Geri al"', (tester) async {
    tallPhone(tester);
    final api = _api();
    await _openSheet(tester, api);
    await tester.tap(_inSheet(find.text('Sil')));
    await settleFrames(tester);
    expect(find.text('“Netflix” silindi'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing, reason: 'off the list');
    expect(api.requests, isNot(contains('DELETE /subscriptions/6')));
    await letUndoRunOut(tester);
    expect(api.requests, contains('DELETE /subscriptions/6'));
  });

  testWidgets('the dashboard: a payment past its date reads "Gecikmiş", and '
      'a tap opens its sheet', (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on('GET /finance/dashboard', {
        'currency': 'TRY',
        'subunit_to_unit': 100,
        'month': {'income_cents': 0, 'expense_cents': 0, 'net_cents': 0},
        'year': {'income_cents': 0, 'expense_cents': 0},
        'six_month_series': {'labels': [], 'income_cents': [], 'expense_cents': []},
        'pie': [],
        'budgets': [],
        'upcoming_subscriptions': [
          {
            'id': 6,
            'name': 'Netflix',
            'amount_cents': 22999,
            'frequency': 'monthly',
            'next_charge_on': '2020-01-15',
            'account': {'id': 1, 'name': 'Cüzdan', 'color': '#D4A574', 'currency': 'TRY', 'subunit_to_unit': 100},
          },
        ],
        'recent_transactions': [transactionJson()],
      });
    await pumpFinance(tester, api, const FinanceScreen());
    await tester.dragUntilVisible(find.textContaining('Gecikmiş'),
        find.byType(ListView).first, const Offset(0, -300));
    await settleFrames(tester);
    expect(find.text('Gecikmiş · 15 Ocak'), findsOneWidget);
    await tester.tap(find.text('Netflix'));
    await settleFrames(tester);
    expect(_inSheet(find.text('Ödendi olarak kaydet')), findsOneWidget);
  });
}
