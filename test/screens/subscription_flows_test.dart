/// Subscriptions from the phone (contract G2.6): the Abonelikler page with
/// what they cost, the form, and the sheet that records a payment, pauses,
/// edits and deletes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/formats.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/date_utils.dart';
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

const _charge = 'POST /subscriptions/6/charge';

/// Whether the sheet's "Ödendi olarak kaydet" can be tapped.
bool _chargeEnabled(WidgetTester tester) => tester
    .widget<ButtonStyleButton>(find
        .ancestor(
          of: _inSheet(find.text('Ödendi olarak kaydet')),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        )
        .first)
    .enabled;

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

  testWidgets('the account list could not be loaded: the account row says '
      'so, a tap loads it again, and no first account is offered meanwhile',
      (tester) async {
    tallPhone(tester);
    final api = _api()..failNetwork('GET /accounts');
    await pumpFinance(tester, api, const SubscriptionsScreen());
    await tester.tap(find.byType(FloatingActionButton));
    await settleFrames(tester);
    expect(find.text('Hesaplar yüklenemedi. Tekrar denemek için dokun.'),
        findsOneWidget);
    expect(find.text('Önce bir hesap oluştur'), findsNothing);

    api.on('GET /accounts', {
      'accounts': [accountJson()],
    });
    final loads = api.gets.where((p) => p == '/accounts').length;
    await tester.tap(find.text('Hesap'));
    await settleFrames(tester);
    expect(find.text('Yeni hesap'), findsNothing, reason: 'no account form');
    expect(find.byType(BottomSheet), findsNothing, reason: 'no picker');
    expect(api.gets.where((p) => p == '/accounts').length, loads + 1);
    expect(find.text('Cüzdan'), findsOneWidget);
    expect(find.text('Hesaplar yüklenemedi. Tekrar denemek için dokun.'),
        findsNothing);
  });

  testWidgets('saved before the account list is here, the form says the list '
      'is the problem — not that there is no account', (tester) async {
    tallPhone(tester);
    final api = _api()..hold('GET /accounts');
    await pumpFinance(tester, api, const SubscriptionsScreen());
    await tester.tap(find.byType(FloatingActionButton));
    await settleFrames(tester);
    expect(find.text('Hesaplar yükleniyor…'), findsWidgets);
    await tester.tap(find.text('Hesap'));
    await settleFrames(tester);
    expect(find.text('Yeni hesap'), findsNothing);
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    expect(find.text('Önce bir hesap oluştur'), findsNothing);
    expect(api.bodiesOf('POST /subscriptions'), isEmpty);

    api.release('GET /accounts');
    await settleFrames(tester);
    expect(find.text('Cüzdan'), findsOneWidget);
    expect(find.text('Hesaplar yükleniyor…'), findsNothing);
  });

  testWidgets('an amount typed before the list came in is read in the '
      'currency of the account the subscription falls to', (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on('GET /accounts', {
        'accounts': [
          accountJson(id: 3, name: 'Altın', currency: 'GAU', subunit: 1),
        ],
      })
      ..hold('GET /accounts');
    await pumpFinance(tester, api, const SubscriptionsScreen());
    await tester.tap(find.byType(FloatingActionButton));
    await settleFrames(tester);
    await tester.enterText(find.byType(TextField).first, 'Altın birikimi');
    await tester.tap(find.text('Tutar').first);
    await settleFrames(tester);
    for (final key in ['5', ',', '5']) {
      await tester.tap(_inSheet(find.text(key)).last);
      await tester.pump();
    }
    await tester.tap(_inSheet(find.text('Tamam')));
    await settleFrames(tester);
    expect(find.text('5,50 ₺'), findsOneWidget);

    api.release('GET /accounts');
    await settleFrames(tester);
    expect(find.text('Altın'), findsOneWidget);
    expect(find.text('5 gr'), findsOneWidget);
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    final body = api.bodiesOf('POST /subscriptions').single as Map;
    expect(body['account_id'], 3);
    expect(body['amount_cents'], 5);
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
      'the app\'s words — in the sheet, where it can be seen', (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on(_charge, {
        'errors': {'base': ['Only an active subscription can be charged.']},
        'code': 'not_chargeable',
        'reason': 'inactive',
      }, status: 422);
    await _openSheet(tester, api);
    await tester.tap(_inSheet(find.text('Ödendi olarak kaydet')));
    await settleFrames(tester);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'still open');
    // Seen, not just in the tree: nothing is drawn over it.
    expect(
      find
          .text('Duraklatılmış bir abonelik ödendi olarak işaretlenemez')
          .hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('"Ödendi olarak kaydet" waits for its answer: the button is '
      'off while the payment is sent, so a second tap sends nothing',
      (tester) async {
    tallPhone(tester);
    final api = _api()..hold(_charge);
    await _openSheet(tester, api);
    await tester.tap(_inSheet(find.text('Ödendi olarak kaydet')));
    await settleFrames(tester);
    expect(_chargeEnabled(tester), isFalse);
    await tester.tap(_inSheet(find.text('Ödendi olarak kaydet')),
        warnIfMissed: false);
    await settleFrames(tester);
    expect(api.requests.where((r) => r == _charge), hasLength(1));

    api.release(_charge);
    await settleFrames(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Ödeme kaydedildi · 229,99 ₺'), findsOneWidget);
    expect(api.requests.where((r) => r == _charge), hasLength(1));
  });

  testWidgets('a payment whose answer is lost may have been recorded: the '
      'sheet says so where it can be seen, nothing is sent again, and the '
      'button stays off until the refetched list says what happened',
      (tester) async {
    tallPhone(tester);
    const maybe = 'Sunucu zamanında yanıt vermedi — ödeme kaydedilmiş '
        'olabilir. Tekrar denemeden önce işlemlere bak.';
    final api = _api()..timeOut(_charge);
    await _openSheet(tester, api);
    // The refetch the lost write starts has not landed yet.
    api.hold('GET /subscriptions');
    await tester.tap(_inSheet(find.text('Ödendi olarak kaydet')));
    await settleFrames(tester);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'still open');
    expect(_inSheet(find.text(maybe)).hitTestable(), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(_chargeEnabled(tester), isFalse);
    await tester.tap(_inSheet(find.text('Ödendi olarak kaydet')),
        warnIfMissed: false);
    await settleFrames(tester);
    expect(api.requests.where((r) => r == _charge), hasLength(1),
        reason: 'never sent again on its own, nor by a second tap');

    // The list lands: the payment did go through — the next one is due a
    // month on.
    api.on('GET /subscriptions', subscriptionsJson(
      active: [subscriptionJson(next: '2026-11-15')],
      inactive: [subscriptionJson(id: 8, name: 'Gazete', active: false)],
    ));
    api.release('GET /subscriptions');
    await settleFrames(tester);
    expect(_inSheet(find.text('Sonraki ödeme: 15 Kasım 2026')),
        findsOneWidget);
    expect(_chargeEnabled(tester), isTrue);
    expect(_inSheet(find.text(maybe)), findsOneWidget, reason: 'still said');
    expect(api.requests.where((r) => r == _charge), hasLength(1));
  });

  testWidgets('a pause that fails is said in the sheet, where it can be seen',
      (tester) async {
    tallPhone(tester);
    final api = _api()..failNetwork('PATCH /subscriptions/6');
    await _openSheet(tester, api);
    await tester.tap(_inSheet(find.text('Durdur')));
    await settleFrames(tester);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'still open');
    expect(_inSheet(find.text('Abonelik güncellenemedi')).hitTestable(),
        findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
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

  testWidgets('leaving Abonelikler ends a delete\'s undo window: it goes at '
      'once, and its "Geri al" goes too', (tester) async {
    tallPhone(tester);
    final api = _api();
    await pumpFinance(
      tester,
      api,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/finance/subscriptions'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settleFrames(tester);
    await tester.tap(find.text('Netflix'));
    await settleFrames(tester);
    await tester.tap(_inSheet(find.text('Sil')));
    await settleFrames(tester);
    expect(find.text('“Netflix” silindi'), findsOneWidget);
    expect(api.requests, isNot(contains('DELETE /subscriptions/6')));

    await tester.tap(find.byType(BackButton));
    await settleFrames(tester);
    expect(find.text('open'), findsOneWidget);
    expect(api.requests, contains('DELETE /subscriptions/6'));
    expect(find.text('Geri al'), findsNothing);
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
    // Missed in an earlier year: the date says which.
    expect(find.text('Gecikmiş · 15 Ocak 2020'), findsOneWidget);
    await tester.tap(find.text('Netflix'));
    await settleFrames(tester);
    expect(_inSheet(find.text('Ödendi olarak kaydet')), findsOneWidget);
  });

  testWidgets('the Abonelikler page says since when a payment is overdue: '
      'this year\'s date plainly, an earlier year\'s with its year',
      (tester) async {
    tallPhone(tester);
    final today = DateTime.now();
    // The 1st of this month, or of last month on the 1st itself: past, and
    // this year unless today is the 1st of January.
    final thisYear = today.day > 1
        ? DateTime(today.year, today.month, 1)
        : DateTime(today.year, today.month - 1, 1);
    final api = FakeApi()
      ..on('GET /subscriptions', subscriptionsJson(active: [
        subscriptionJson(next: isoDate(thisYear)),
        subscriptionJson(id: 9, name: 'Gazete', next: '2020-01-15'),
      ]));
    await pumpFinance(tester, api, const SubscriptionsScreen());
    final shown =
        formatDate(thisYear, withYear: thisYear.year != today.year);
    expect(find.text('Gecikmiş · $shown · Aylık'), findsOneWidget);
    expect(find.text('Gecikmiş · 15 Ocak 2020 · Aylık'), findsOneWidget);
  });

  test('overdueSince: the year only when it is not today\'s', () async {
    // Dates follow the UI language, which the delegate sets.
    addTearDown(() => AppL10n.delegate.load(const Locale('tr')));
    final today = DateTime(2026, 10, 4);
    final tr = await AppL10n.delegate.load(const Locale('tr'));
    expect(overdueSince(tr, DateTime(2026, 10, 3), today), 'Gecikmiş · 3 Ekim');
    expect(overdueSince(tr, DateTime(2025, 12, 31), today),
        'Gecikmiş · 31 Aralık 2025');
    final en = await AppL10n.delegate.load(const Locale('en'));
    expect(overdueSince(en, DateTime(2026, 10, 3), today), 'Overdue · October 3');
    expect(overdueSince(en, DateTime(2025, 12, 31), today),
        'Overdue · December 31, 2025');
  });
}
