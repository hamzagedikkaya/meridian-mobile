/// Accounts from the phone alone (contract G2.2): the first account in one
/// tap, the account form (create and edit, a locked currency), archive and
/// restore, delete when nothing is recorded on it — and archive offered
/// instead when something is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/ui/screens/finance/account_card.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/reconcile_sheet.dart';
import 'package:meridian_mobile/ui/screens/finance/transaction_form_screen.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_form.dart';
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart';
import 'package:meridian_mobile/ui/widgets/primary_button.dart';

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
      expect(find.text('“Nakit” hesabı açıldı'), findsOneWidget);
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

      await tester.tap(find.text('Kredi kartı'));
      await settleFrames(tester);
      expect(find.widgetWithText(TextField, 'Kredi kartı'), findsOneWidget);
      await tester.tap(find.text('USD · ABD doları'));
      await settleFrames(tester);

      // The opening balance on the keypad, as a debt.
      await tester.tap(find.text('Açılış bakiyesi').first);
      await settleFrames(tester);
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      // A credit card starts in debt: the sheet's "Borç" switch is already
      // on (the form's own "Varsayılan hesap" one is under the sheet).
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isTrue);
      expect(find.text('−\$1.234'), findsOneWidget);
      await tester.tap(find.text('Tamam'));
      await settleFrames(tester);
      expect(find.text('−\$1.234,00'), findsOneWidget);

      await tester.tap(find.text('Hesabı oluştur'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /accounts').single, {
        'name': 'Kredi kartı',
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
      expect(find.text('Hesap güncellendi'), findsOneWidget);
    });

    testWidgets('a currency change refused because the account got a '
        'transaction meanwhile: currency and opening balance go back, the '
        'currency locks, and the next save sends the rest without them',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts', {
          'accounts': [accountJson(initial: 125050)],
        })
        ..on('PATCH /accounts/1', {
          'errors': {
            'currency': ['An account with transactions cannot change it.'],
          },
          'code': 'currency_locked',
        }, status: 422);
      await _openAccount(tester, api);
      await _menu(tester, 'Düzenle');
      // Nothing is recorded on it yet: the currency can change.
      expect(
        find.text('Bu hesapta işlem ya da abonelik olduğu için para birimi '
            'değişmez.'),
        findsNothing,
      );
      expect(find.text('₺1.250,50'), findsOneWidget);
      await tester.tap(find.text('GAU · Gram altın'));
      await settleFrames(tester);
      // The opening balance as typed, in grams (no decimals).
      expect(find.text('1.250\u00A0gr'), findsOneWidget);
      // A transaction was recorded on it on the web meanwhile.
      api.on('GET /accounts/1', {'account': accountDetailJson(transactions: 1)});
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /accounts/1').single,
          {'currency': 'GAU', 'initial_balance_cents': 1250});
      expect(find.text('Hesabı düzenle'), findsOneWidget, reason: 'kept open');
      expect(
        find.text('İşlemi ya da aboneliği olan bir hesabın para birimi '
            'değiştirilemez'),
        findsOneWidget,
      );
      expect(find.text('An account with transactions cannot change it.'),
          findsNothing);
      // Its own currency and opening balance again, and they stay.
      expect(find.text('₺1.250,50'), findsOneWidget);
      await tester.tap(find.text('GAU · Gram altın'));
      await settleFrames(tester);
      expect(find.text('₺1.250,50'), findsOneWidget);

      api.on('PATCH /accounts/1', {'account': accountJson(name: 'Ziraat')});
      await tester.enterText(find.byType(TextField), 'Ziraat');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /accounts/1').last, {'name': 'Ziraat'});
      expect(find.text('Hesap güncellendi'), findsOneWidget);
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

    testWidgets('a transaction recorded on it meanwhile: the delete is '
        'refused, the account comes back, and archiving is offered',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('DELETE /accounts/1', {
          'errors': {'base': ['raw server text']},
          'code': 'has_transactions',
          'transactions_count': 1,
          'incoming_transfers_count': 0,
        }, status: 422);
      await _openAccount(tester, api);
      await _menu(tester, 'Sil');
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /accounts/1'));
      expect(
        find.text('Bu hesabın 1 işlemi var; silmek yerine arşivle'),
        findsOneWidget,
      );
      await tester.tap(find.text('Arşivle'));
      await settleFrames(tester);
      expect(api.requests, contains('PATCH /accounts/1/archive'));
      expect(find.text('“Cüzdan” arşivlendi'), findsOneWidget);
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

    testWidgets('an archived account with history cannot be deleted, and '
        'archiving is no way out for it: that is only said — it is not '
        'archived again, nor offered a "Geri al" that would restore it',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts', {
          'accounts': [accountJson(archived: true)],
        })
        ..on('GET /accounts/1', {
          'account': accountDetailJson(
              archived: true, transactions: 4, incoming: 1),
        });
      await _openAccount(tester, api);
      await _menu(tester, 'Sil');
      expect(find.text('Bu hesap silinemez'), findsOneWidget);
      expect(
        find.text('Bu hesabın 4 işlemi ve 1 gelen transferi var. Geçmişi '
            'olan bir hesap silinemez; arşivde kalır ve işlemleri '
            'toplamlarda sayılmaya devam eder.'),
        findsOneWidget,
      );
      expect(find.text('Arşivle'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Tamam'));
      await settleFrames(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Geri al'), findsNothing);
      expect(
        api.requests.where((r) => !r.startsWith('GET ')),
        isEmpty,
        reason: 'no archive, no unarchive, no delete',
      );
    });

    testWidgets('an archived account that got a transaction meanwhile: the '
        'refused delete brings it back and says why — without telling it to '
        'archive itself, or offering to', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts', {
          'accounts': [accountJson(archived: true)],
        })
        ..on('GET /accounts/1', {
          'account': accountDetailJson(archived: true),
        })
        ..on('DELETE /accounts/1', {
          'errors': {'base': ['raw server text']},
          'code': 'has_transactions',
          'transactions_count': 1,
          'incoming_transfers_count': 0,
        }, status: 422);
      await _openAccount(tester, api);
      await _menu(tester, 'Sil');
      expect(find.text('“Cüzdan” silindi'), findsOneWidget);
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /accounts/1'));
      expect(
        find.text('Bu hesabın 1 işlemi var. Geçmişi olan bir hesap '
            'silinemez; arşivde kalır ve işlemleri toplamlarda sayılmaya '
            'devam eder.'),
        findsOneWidget,
      );
      expect(find.text('Arşivle'), findsNothing);
      expect(api.requests.where((r) => r.contains('archive')), isEmpty);
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
      expect(find.text('+₺100,00'), findsOneWidget);
      expect(find.text('−₺100,00'), findsOneWidget);
      expect(find.text('Banka → Cüzdan'), findsOneWidget);
    });
  });

  group('reconcile: the real balance', () {
    test('moves the opening balance by the difference', () {
      final card = Account.fromJson(accountJson(
        type: 'credit_card',
        initial: 150000,
        balance: -428550,
      ));
      // −₺4.285,50 on the phone, −₺4.000 on the statement: ₺285,50 less
      // debt, so the opening balance rises by that much.
      expect(reconciledInitialBalance(card, -400000), 178550);
      expect(reconciledInitialBalance(card, -428550), 150000,
          reason: 'already right: nothing moves');
      final wallet = Account.fromJson(accountJson(balance: 500000));
      expect(reconciledInitialBalance(wallet, 512000), 12000);
      expect(
        reconcileInput(wallet, 12000).changesFrom(wallet),
        {'initial_balance_cents': 12000},
        reason: 'only the opening balance is sent',
      );
    });

    testWidgets('"Bakiyeyi eşitle": type the real balance, see the '
        'difference, save — and "Geri al" puts the old opening balance back',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('PATCH /accounts/1', {
          'account': accountJson(initial: 12000, balance: 512000),
        });
      await _openAccount(tester, api);
      await tester.tap(find.text('Bakiyeyi eşitle'));
      await settleFrames(tester);
      expect(find.text('Gerçek bakiye'), findsOneWidget);
      expect(find.text('Şu anki: ₺5.000,00'), findsOneWidget);
      for (final digit in ['5', '1', '2', '0']) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      expect(find.text('Şu anki: ₺5.000,00 · Fark: +₺120,00'), findsOneWidget);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /accounts/1').single,
          {'initial_balance_cents': 12000});
      expect(find.text('Gerçek bakiye'), findsNothing, reason: 'closed');
      expect(find.text('Bakiye eşitlendi'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /accounts/1').last,
          {'initial_balance_cents': 0});
    });
  });

  group('an account\'s header', () {
    testWidgets('its type, its balance, and what can be done — the FAB '
        'waits until "+ İşlem" has scrolled away', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await _openAccount(tester, api);
      expect(find.text('NAKİT'), findsOneWidget);
      expect(find.text('₺5.000,00'), findsWidgets);
      expect(find.text('Transfer'), findsOneWidget);
      expect(find.text('Bakiyeyi eşitle'), findsOneWidget);
      final fab = find.byType(FloatingActionButton);
      expect(fab.hitTestable(), findsNothing, reason: 'the chip is on screen');
      expect(find.text('Bağlı hedefler (2)'), findsNothing);

      await tester.tap(find.text('Transfer'));
      await settleFrames(tester);
      final form = tester.widget<TransactionFormScreen>(
          find.byType(TransactionFormScreen));
      expect(form.initialKind, 'transfer');
      expect(form.initialAccountId, 1, reason: 'out of this account');
    });

    testWidgets('scrolled past the header, the FAB comes back', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /transactions', {
          'transactions': [
            for (var i = 0; i < 30; i++) transactionJson(id: 1000 + i),
          ],
          'meta': const {
            'total_count': 30,
            'page': 1,
            'page_limit': 50,
            'filtered_income_cents': 0,
            'filtered_expense_cents': 416220,
          },
        });
      await _openAccount(tester, api);
      final fab = find.byType(FloatingActionButton);
      expect(fab.hitTestable(), findsNothing, reason: 'the chip is on screen');

      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, -700));
      await settleFrames(tester);
      expect(find.text('Bakiyeyi eşitle').hitTestable(), findsNothing,
          reason: 'the header has scrolled away');
      expect(fab.hitTestable(), findsOneWidget);

      // Back up to the chips: the FAB steps aside again.
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, 2000));
      await settleFrames(tester);
      expect(fab.hitTestable(), findsNothing);
    });

    testWidgets('linked goals are a tap away', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts/1', {'account': accountDetailJson(goals: 2)});
      await _openAccount(tester, api);
      expect(find.text('Bağlı hedefler (2)'), findsOneWidget);
    });

    testWidgets('the balance flies from its Finance tile — not under '
        'reduced motion', (tester) async {
      tallPhone(tester);
      await pumpFinance(tester, FakeApi(), const FinanceScreen());
      HeroMode modeOf(Finder hero) => tester.widget<HeroMode>(
          find.ancestor(of: hero, matching: find.byType(HeroMode)).first);
      final tileHero = find.byWidgetPredicate(
          (w) => w is Hero && w.tag == accountBalanceHeroTag(1));
      expect(tileHero, findsOneWidget);
      expect(modeOf(tileHero).enabled, isTrue);

      await tester.tap(find.byType(AccountTile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-flight: the shuttle is in the overlay, scaling the balance.
      expect(
        find.descendant(
          of: find.byType(Overlay).first,
          matching: find.byWidgetPredicate(
              (w) => w is FittedBox && w.fit == BoxFit.contain),
        ),
        findsOneWidget,
      );
      await settleFrames(tester);
      expect(find.text('NAKİT'), findsOneWidget);
    });

    testWidgets('reduced motion: no flight', (tester) async {
      tallPhone(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpFinance(tester, FakeApi(), const FinanceScreen());
      final mode = tester.widget<HeroMode>(find
          .ancestor(
            of: find.byWidgetPredicate(
                (w) => w is Hero && w.tag == accountBalanceHeroTag(1)),
            matching: find.byType(HeroMode),
          )
          .first);
      expect(mode.enabled, isFalse);
    });
  });

  testWidgets('the old archive link opens Hesaplar with its archive open, '
      'which restores an archived account', (tester) async {
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
    expect(find.text('Arşivlenmiş hesaplar (1)'), findsOneWidget);
    expect(find.text('Eski kart'), findsOneWidget);

    await tester.tap(find.text('Geri yükle'));
    await settleFrames(tester);
    expect(api.requests, contains('PATCH /accounts/4/unarchive'));
    expect(find.text('“Eski kart” geri yüklendi'), findsOneWidget);
  });

  group('Hesaplar', () {
    testWidgets('totals per currency — never added across them — and the '
        'accounts grouped by type; a row opens its account', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts', {
          'accounts': [
            accountJson(balance: 325000),
            accountJson(id: 2, name: 'Banka', type: 'bank', balance: 3300000),
            accountJson(
                id: 3, name: 'Gram altın', type: 'savings', currency: 'GAU',
                subunit: 1, balance: 412),
          ],
        });
      await pumpFinance(tester, api, _launcher('/finance/accounts'));
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(find.text('Hesaplar'), findsOneWidget);
      expect(find.text('TRY'), findsOneWidget);
      expect(find.text('₺36.250,00'), findsOneWidget);
      // Gram gold reads as a word, not its code.
      expect(find.text('Altın'), findsOneWidget);
      expect(find.text('GAU'), findsNothing);
      expect(find.text('412\u00A0gr'), findsWidgets);
      // Groups in their order: Nakit, Banka, Birikim.
      final cash = tester.getTopLeft(find.text('Nakit').first).dy;
      final bank = tester.getTopLeft(find.text('Banka').first).dy;
      final savings = tester.getTopLeft(find.text('Birikim').first).dy;
      expect(cash, lessThan(bank));
      expect(bank, lessThan(savings));
      expect(find.text('Arşivlenmiş hesaplar (0)'), findsNothing);

      await tester.tap(find.text('Cüzdan'));
      await settleFrames(tester);
      expect(find.text('NAKİT'), findsOneWidget, reason: 'its page');
    });

    testWidgets('"Hesap" opens the account form', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await pumpFinance(tester, api, _launcher('/finance/accounts'));
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Hesap'));
      await settleFrames(tester);
      expect(find.text('Yeni hesap'), findsOneWidget);
    });
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
    // The kind first, as a card (§7.11).
    await tester.tap(find.text('Birikim hedefi'));
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
    // The target on the keypad, never the system keyboard.
    await tester.tap(find.text('Hedef değer'));
    await settleFrames(tester);
    for (final d in '20000'.split('')) {
      await tester.tap(find.descendant(
        of: find.byType(AmountKeypad),
        matching: find.text(d),
      ));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(PrimaryButton, 'Tamam'));
    await settleFrames(tester);
    await tester.tap(find.text('Hedef oluştur'));
    await settleFrames(tester);
    expect((api.bodiesOf('POST /goals').single as Map)['related'], 'Account-2');
  });
}
