/// Accounts from the phone alone (contract G2.2): the first account in one
/// tap, the account form (create and edit, a locked currency), archive and
/// restore, delete when nothing is recorded on it — and archive offered
/// instead when something is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_form.dart';

import '../support/fake_api.dart';
import '../support/finance_harness.dart';

Widget _launcher(String location) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.push(location),
            child: const Text('open'),
          ),
        ),
      ),
    );

/// Opens account 1's screen over a plain page, so it can be left.
Future<void> _openAccount(WidgetTester tester, FakeApi api) async {
  await pumpFinance(tester, api, _launcher('/finance/account/1'));
  await tester.tap(find.text('open'));
  await settleFrames(tester);
  expect(find.text('Cüzdan'), findsWidgets);
}

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('Diğer seçenekler'));
  await settleFrames(tester);
  await tester.tap(find.text(item).last);
  await settleFrames(tester);
}

void main() {
  setUpAll(initializeDateFormatting);

  group('first run: from no account to tracking money', () {
    testWidgets('"Nakit hesabıyla başla" opens a cash account in one tap, '
        'and the next step is the first transaction', (tester) async {
      tallPhone(tester);
      final api = FakeApi()..on('GET /accounts', {'accounts': const []});
      await pumpFinance(tester, api, const FinanceScreen());
      expect(find.text('İlk hesabını oluştur'), findsOneWidget);

      api.on('GET /accounts', {
        'accounts': [accountJson(name: 'Nakit')],
      });
      api.on('POST /accounts', {'account': accountJson(name: 'Nakit')},
          status: 201);
      await tester.tap(find.text('Nakit hesabıyla başla'));
      await settleFrames(tester);

      // The user's currency is the server's to pick.
      expect(api.bodiesOf('POST /accounts').single, {
        'name': 'Nakit',
        'account_type': 'cash',
        'initial_balance_cents': 0,
        'color': '#D4A853',
      });
      expect(find.text('“Nakit” hesabı açıldı ✓'), findsOneWidget);
      // The account list refetched: the card moved on.
      expect(find.text('İlk hesabını oluştur'), findsNothing);
      expect(find.text('İlk işlemini ekle'), findsOneWidget);
    });

    testWidgets('"Başka bir hesap ekle": the form — type, name, currency, a '
        'card\'s debt as the opening balance, colour', (tester) async {
      tallPhone(tester);
      final api = FakeApi()..on('GET /accounts', {'accounts': const []});
      await pumpFinance(tester, api, const FinanceScreen());
      await tester.tap(find.text('Başka bir hesap ekle'));
      await settleFrames(tester);
      expect(find.text('Yeni hesap'), findsOneWidget);
      // Named after its type until the user names it.
      expect(find.widgetWithText(TextField, 'Nakit'), findsOneWidget);

      await tester.tap(find.text('Kredi Kartı'));
      await settleFrames(tester);
      expect(find.widgetWithText(TextField, 'Kredi Kartı'), findsOneWidget);
      await tester.tap(find.text('USD · ABD doları'));
      await settleFrames(tester);

      // The opening balance on the keypad, as a debt.
      await tester.tap(find.text('Açılış bakiyesi').first);
      await settleFrames(tester);
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.text('−1.234 \$'), findsOneWidget);
      await tester.tap(find.text('Tamam'));
      await settleFrames(tester);
      expect(find.text('−1.234,00 \$'), findsOneWidget);

      await tester.tap(find.text('Hesabı oluştur'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /accounts').single, {
        'name': 'Kredi Kartı',
        'account_type': 'credit_card',
        'currency': 'USD',
        'initial_balance_cents': -123400,
        'color': '#D4A853',
      });
      expect(find.text('Yeni hesap'), findsNothing, reason: 'closed');
    });

    testWidgets('a name is needed; the server\'s refusal lands under its field',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()..on('GET /accounts', {'accounts': const []});
      await pumpFinance(tester, api, const FinanceScreen());
      await tester.tap(find.text('Başka bir hesap ekle'));
      await settleFrames(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Hesabı oluştur'));
      await settleFrames(tester);
      expect(find.text('Bir ad gir'), findsOneWidget);
      expect(api.bodiesOf('POST /accounts'), isEmpty);

      api.on('POST /accounts', {
        'errors': {'name': ['Ad çok uzun']},
        'code': 'validation_failed',
        'details': {
          'name': [
            {'error': 'too_long', 'count': 60},
          ],
        },
      }, status: 422);
      await tester.enterText(find.byType(TextField), 'Birikim');
      await tester.tap(find.text('Hesabı oluştur'));
      await settleFrames(tester);
      expect(find.text('En fazla 60 karakter olabilir'), findsOneWidget);
      expect(find.text('Yeni hesap'), findsOneWidget, reason: 'kept open');
    });
  });

  group('an account\'s own screen', () {
    testWidgets('edit sends only what changed; a currency in use is locked',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts/1', {'account': accountDetailJson(transactions: 3)});
      await _openAccount(tester, api);
      await _menu(tester, 'Düzenle');
      expect(find.text('Hesabı düzenle'), findsOneWidget);
      expect(
        find.text('Bu hesapta işlem ya da abonelik olduğu için para birimi '
            'değişmez.'),
        findsOneWidget,
      );
      // A locked currency does not change on a tap.
      await tester.tap(find.text('USD · ABD doları'));
      await settleFrames(tester);

      await tester.enterText(find.byType(TextField), 'Ziraat');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /accounts/1').single, {'name': 'Ziraat'});
      expect(find.text('Hesap güncellendi ✓'), findsOneWidget);
    });

    testWidgets('archive at once, with "Geri al" that restores it',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await _openAccount(tester, api);
      await _menu(tester, 'Arşivle');
      expect(api.requests, contains('PATCH /accounts/1/archive'));
      expect(find.text('“Cüzdan” arşivlendi'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(api.requests, contains('PATCH /accounts/1/unarchive'));
    });

    testWidgets('an empty account is deleted with an undo: nothing is sent '
        'until the snackbar goes', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await _openAccount(tester, api);
      await _menu(tester, 'Sil');
      // Back where it was opened from; the account is gone from the lists.
      expect(find.text('open'), findsOneWidget);
      expect(find.text('“Cüzdan” silindi'), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /accounts/1')));

      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /accounts/1'));
    });

    testWidgets('"Geri al" keeps an emptied account: no delete is sent',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await _openAccount(tester, api);
      await _menu(tester, 'Sil');
      await tester.tap(find.text('Geri al'));
      await letUndoRunOut(tester);
      expect(api.requests, isNot(contains('DELETE /accounts/1')));
    });

    testWidgets('an account with history cannot be deleted: archiving is '
        'offered instead', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts/1', {
          'account': accountDetailJson(transactions: 4, incoming: 1),
        });
      await _openAccount(tester, api);
      await _menu(tester, 'Sil');
      expect(find.text('Bu hesap silinemez'), findsOneWidget);
      expect(
        find.text('Bu hesabın 4 işlemi ve 1 gelen transferi var; silmek '
            'yerine arşivle'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Arşivle'));
      await settleFrames(tester);
      expect(api.requests, contains('PATCH /accounts/1/archive'));
      expect(api.requests, isNot(contains('DELETE /accounts/1')));
    });

    testWidgets('a delete that takes subscriptions and unlinks goals says so '
        'first, then goes at once', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts/1', {
          'account': accountDetailJson(subscriptions: 2, goals: 1),
        });
      await _openAccount(tester, api);
      await _menu(tester, 'Sil');
      expect(find.text('“Cüzdan” silinsin mi?'), findsOneWidget);
      expect(find.textContaining('2 abonelik de silinecek'), findsOneWidget);
      expect(find.textContaining('1 hedefin bağlantısı kalkacak'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
      await settleFrames(tester);
      expect(api.requests, contains('DELETE /accounts/1'));
      expect(find.text('“Cüzdan” silindi'), findsOneWidget);
    });

    testWidgets('its history lists the transfers into it as money in, and '
        'its own as money out', (tester) async {
      tallPhone(tester);
      Map<String, dynamic> transfer(int id, int from, int to) => {
            ...transactionJson(id: id),
            'kind': 'transfer',
            'amount_cents': 10000,
            'description': null,
            'account': {
              'id': from,
              'name': from == 1 ? 'Cüzdan' : 'Banka',
              'color': '#D4A574',
              'currency': 'TRY',
              'subunit_to_unit': 100,
            },
            'related_account': {'id': to, 'name': to == 1 ? 'Cüzdan' : 'Banka'},
          };
      final queries = <Map<String, dynamic>>[];
      final api = FakeApi()
        ..onRequest('GET /transactions', (request) {
          queries.add(request.queryParameters);
          return {
            'transactions': [transfer(500, 2, 1), transfer(501, 1, 2)],
            'meta': const {'total_count': 2, 'page': 1, 'page_limit': 50},
          };
        });
      await _openAccount(tester, api);
      expect(queries.first['account_id'], 1);
      expect(queries.first['include_incoming_transfers'], true);
      expect(find.text('+100,00 ₺'), findsOneWidget);
      expect(find.text('−100,00 ₺'), findsOneWidget);
      expect(find.text('Banka → Cüzdan'), findsOneWidget);
    });
  });

  testWidgets('the archive page restores an archived account', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /accounts', {
        'accounts': [
          accountJson(),
          accountJson(id: 4, name: 'Eski kart', archived: true),
        ],
      })
      ..on('PATCH /accounts/4/unarchive', {'account': accountJson(id: 4)});
    await pumpFinance(tester, api, _launcher('/finance/accounts/archived'));
    await tester.tap(find.text('open'));
    await settleFrames(tester);
    expect(find.text('Arşivlenmiş hesaplar'), findsOneWidget);
    expect(find.text('Eski kart'), findsOneWidget);
    expect(find.text('Cüzdan'), findsNothing, reason: 'active ones are not');

    await tester.tap(find.text('Geri yükle'));
    await settleFrames(tester);
    expect(api.requests, contains('PATCH /accounts/4/unarchive'));
    expect(find.text('“Eski kart” geri yüklendi'), findsOneWidget);
  });

  testWidgets('a savings goal with no account yet: the account form opens '
      'from the goal form, and the goal is linked to the new account',
      (tester) async {
    // As wide as the goals tests use: the form's type pill is one row.
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi()..on('GET /accounts', {'accounts': const []});
    await pumpFinance(
      tester,
      api,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const GoalFormScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settleFrames(tester);
    await tester.tap(find.text('Finansal'));
    await settleFrames(tester);
    await tester.tap(find.text('Bağlı hesap'));
    await settleFrames(tester);
    expect(find.text('Yeni hesap'), findsOneWidget, reason: 'the account form');
    await tester.tap(find.text('Hesabı oluştur'));
    await settleFrames(tester);
    expect(api.bodiesOf('POST /accounts'), hasLength(1));
    // Back in the goal form, linked to it.
    expect(find.text('Banka'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Hedef adı'), 'Tatil');
    await tester.enterText(
        find.widgetWithText(TextField, 'Hedef değer'), '20000');
    await tester.tap(find.text('Hedef oluştur'));
    await settleFrames(tester);
    expect((api.bodiesOf('POST /goals').single as Map)['related'], 'Account-2');
  });
}
