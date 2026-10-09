/// Recording money without the web (contract G2.3): a transaction without
/// a category, a category made from the picker, transfers within one
/// currency, edits that send only what changed — and the list: deletes with
/// "Geri al", day headings that never pile up, filters that work.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/data/data_scope.dart';
import 'package:meridian_mobile/data/deferred_deletes.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/date_utils.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/ui/screens/finance/account_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/transaction_form_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/transactions_screen.dart';

import '../support/fake_api.dart';
import '../support/finance_harness.dart';

/// A page that opens the transaction form, as Finance does.
Widget _formLauncher({Transaction? existing}) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => openTransactionForm(context, existing: existing),
            child: const Text('open'),
          ),
        ),
      ),
    );

Future<void> _openForm(WidgetTester tester, FakeApi api,
    {Transaction? existing}) async {
  await pumpFinance(tester, api, _formLauncher(existing: existing));
  await tester.tap(find.text('open'));
  await settleFrames(tester);
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
}

/// A plain page that pushes [location] — a screen that can be left.
Widget _pusher(String location) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.push(location),
            child: const Text('open'),
          ),
        ),
      ),
    );

Map<String, dynamic> _accounts() => {
      'accounts': [
        accountJson(),
        accountJson(id: 2, name: 'Banka', type: 'bank', color: '#6B8FA0'),
        accountJson(
            id: 3, name: 'Altın', type: 'savings', currency: 'GAU', subunit: 1),
      ],
    };

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

void main() {
  setUpAll(initializeDateFormatting);

  group('the transaction form', () {
    testWidgets('an expense needs no category: it is saved "Kategorisiz" on '
        'the only account', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await _openForm(tester, api);
      expect(find.text('Kategorisiz'), findsOneWidget);
      await _type(tester, '250');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);

      final body = api.bodiesOf('POST /transactions').single as Map;
      expect(body['kind'], 'expense');
      expect(body['amount_cents'], 25000);
      expect(body['account_id'], 1);
      expect(body.containsKey('finance_category_id'), isFalse);
      expect(find.text('open'), findsOneWidget, reason: 'the form closed');
    });

    testWidgets('a category made from the picker, in the same sheet, is the '
        'one the transaction gets', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await _openForm(tester, api);
      await _type(tester, '45');
      await tester.tap(find.text('Kategori'));
      await settleFrames(tester);
      expect(_inSheet(find.text('Market')), findsOneWidget);
      expect(_inSheet(find.text('Kategorisiz')), findsOneWidget);

      await tester.tap(_inSheet(find.text('Yeni kategori')));
      await settleFrames(tester);
      await tester.enterText(
          _inSheet(find.byType(TextField)), 'Kahve');
      await tester.tap(_inSheet(find.text('Ekle')));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /finance_categories').single, {
        'name': 'Kahve',
        'kind': 'expense',
        'parent_id': null,
        'color': '#6B8E5A',
      });
      // The sheet closed on the new category (the fake answers "Yeni").
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Yeni'), findsOneWidget);

      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(
        (api.bodiesOf('POST /transactions').single as Map)['finance_category_id'],
        9,
      );
    });

    testWidgets('a transfer goes only to another account in the same currency',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()..on('GET /accounts', _accounts());
      await _openForm(tester, api);
      await tester.tap(find.text('Transfer'));
      await settleFrames(tester);
      await tester.tap(find.text('Hesap'));
      await settleFrames(tester);
      await tester.tap(_inSheet(find.text('Cüzdan')));
      await settleFrames(tester);
      await tester.tap(find.text('Hedef hesap'));
      await settleFrames(tester);
      expect(_inSheet(find.text('Banka')), findsOneWidget);
      expect(_inSheet(find.text('Altın')), findsNothing, reason: 'GAU');
      expect(
        _inSheet(find.text('Transfer yalnızca aynı para birimindeki hesaplar '
            'arasında yapılır.')),
        findsOneWidget,
      );
      await tester.tap(_inSheet(find.text('Banka')));
      await settleFrames(tester);
      await _type(tester, '1000');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      final body = api.bodiesOf('POST /transactions').single as Map;
      expect(body['kind'], 'transfer');
      expect(body['account_id'], 1);
      expect(body['related_account_id'], 2);
      expect(body.containsKey('finance_category_id'), isFalse);
    });

    testWidgets('an edit sends only what changed — the note written on the '
        'web stays', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      final existing = Transaction.fromJson({
        ...transactionJson(),
        'note': 'web notu',
        'category': categoryJson(),
      });
      await _openForm(tester, api, existing: existing);
      expect(find.text('web notu'), findsOneWidget);
      // Clear the amount (long-press ⌫) and type a new one.
      await tester.longPress(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      await _type(tester, '150');
      await tester.tap(find.text('Güncelle'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /transactions/316').single,
          {'amount_cents': 15000});
    });

    testWidgets('a note the web saved with a trailing newline is no change: '
        'the form opens clean, and "Güncelle" rewrites nothing',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      final existing = Transaction.fromJson({
        ...transactionJson(),
        'description': 'Kahve ',
        'note': 'web notu\r\n',
      });
      await _openForm(tester, api, existing: existing);
      // Closed untouched: no "unsaved changes" sheet.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await settleFrames(tester);
      expect(find.text('Değişiklikler kaydedilmedi'), findsNothing);
      expect(find.byType(TransactionFormScreen), findsNothing);

      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await tester.tap(find.text('Güncelle'));
      await settleFrames(tester);
      expect(find.byType(TransactionFormScreen), findsNothing);
      expect(api.bodiesOf('PATCH /transactions/316'), isEmpty);
    });

    testWidgets('an older transfer between two currencies stays editable: a '
        'new description is saved, the accounts are not checked again',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()..on('GET /accounts', _accounts());
      // Saved before transfers kept to one currency: lira into gold.
      final existing = Transaction.fromJson({
        ...transactionJson(),
        'kind': 'transfer',
        'amount_cents': 100000,
        'related_account': {'id': 3, 'name': 'Altın'},
      });
      await _openForm(tester, api, existing: existing);
      await tester.enterText(
          find.widgetWithText(TextField, 'Açıklama'), 'Altın birikimi');
      await tester.tap(find.text('Güncelle'));
      await settleFrames(tester);
      expect(api.bodiesOf('PATCH /transactions/316').single,
          {'description': 'Altın birikimi'});
      expect(find.text('open'), findsOneWidget, reason: 'the form closed');
    });

    testWidgets('…but a transfer whose accounts change is held to one '
        'currency again', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts', {
          'accounts': [
            ..._accounts()['accounts'] as List,
            accountJson(id: 4, name: 'Euro', currency: 'EUR'),
          ],
        });
      final existing = Transaction.fromJson({
        ...transactionJson(),
        'kind': 'transfer',
        'amount_cents': 100000,
        'related_account': {'id': 3, 'name': 'Altın'},
      });
      await _openForm(tester, api, existing: existing);
      // A new source: the gold target no longer goes with it.
      await tester.tap(find.text('Hesap'));
      await settleFrames(tester);
      await tester.tap(_inSheet(find.text('Euro')));
      await settleFrames(tester);
      await tester.tap(find.text('Güncelle'));
      await settleFrames(tester);
      expect(find.text('Hedef hesap seç'), findsOneWidget);
      expect(api.bodiesOf('PATCH /transactions/316'), isEmpty);
    });

    testWidgets('the account list could not be loaded: the row says so, a '
        'tap loads it again, and no first account is offered meanwhile',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()..failNetwork('GET /accounts');
      await _openForm(tester, api);
      expect(find.text('Hesaplar yüklenemedi. Tekrar denemek için dokun.'),
          findsOneWidget);
      expect(find.text('Önce bir hesap oluştur'), findsNothing);
      await _type(tester, '250');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /transactions'), isEmpty);

      api.on('GET /accounts', {
        'accounts': [accountJson()],
      });
      final loads = api.gets.where((p) => p == '/accounts').length;
      await tester.tap(find.text('Hesap'));
      await settleFrames(tester);
      expect(find.text('Yeni hesap'), findsNothing, reason: 'no account form');
      expect(find.byType(BottomSheet), findsNothing, reason: 'no picker');
      expect(api.gets.where((p) => p == '/accounts').length, loads + 1);
      // Loaded: the only account is filled in, as it would have been.
      expect(find.text('Cüzdan'), findsOneWidget);
      expect(find.text('Hesaplar yüklenemedi. Tekrar denemek için dokun.'),
          findsNothing);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect((api.bodiesOf('POST /transactions').single as Map)['account_id'],
          1);
    });

    testWidgets('while the account list loads, the row says so and a tap '
        'opens nothing', (tester) async {
      tallPhone(tester);
      final api = FakeApi()..hold('GET /accounts');
      await _openForm(tester, api);
      expect(find.text('Hesaplar yükleniyor…'), findsOneWidget);
      await tester.tap(find.text('Hesap'));
      await settleFrames(tester);
      expect(find.text('Yeni hesap'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      api.release('GET /accounts');
      await settleFrames(tester);
      expect(find.text('Cüzdan'), findsOneWidget);
    });

    testWidgets('an amount typed before the list came in is read in the '
        'currency of the account filled in then', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts', {
          'accounts': [
            accountJson(id: 3, name: 'Altın', currency: 'GAU', subunit: 1),
          ],
        })
        ..hold('GET /accounts');
      await _openForm(tester, api);
      await _type(tester, '12');
      await tester.tap(find.text(','));
      await tester.pump();
      await _type(tester, '5');
      expect(find.text('₺12,5'), findsOneWidget);
      api.release('GET /accounts');
      await settleFrames(tester);
      // Gram gold has no decimals.
      expect(find.text('12\u00A0gr'), findsOneWidget);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      final body = api.bodiesOf('POST /transactions').single as Map;
      expect(body['account_id'], 3);
      expect(body['amount_cents'], 12);
    });

    testWidgets('an account whose delete waits out its undo is not picked '
        'for a new transaction: saving on it would make that delete fail',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts', {
          'accounts': [
            accountJson(),
            accountJson(id: 2, name: 'Banka', type: 'bank'),
          ],
        });
      await pumpFinance(
        tester,
        api,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    openTransactionForm(context, initialAccountId: 2),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      ProviderScope.containerOf(tester.element(find.text('open')))
          .read(deferredDeletesProvider.notifier)
          .stage((scope: DataScope.accounts, id: 2), send: () async {});
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(find.text('Banka'), findsNothing);
      expect(find.text('Cüzdan'), findsOneWidget,
          reason: 'the one account left');
    });

    testWidgets('no account yet: the account row makes one, and picks it',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()..on('GET /accounts', {'accounts': const []});
      await _openForm(tester, api);
      expect(find.text('Önce bir hesap oluştur'), findsOneWidget);
      await tester.tap(find.text('Önce bir hesap oluştur'));
      await settleFrames(tester);
      await tester.tap(find.text('Hesabı oluştur'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /accounts'), hasLength(1));
      // Back in the transaction form, on the new account.
      expect(find.text('Banka'), findsOneWidget);
    });

    testWidgets('an amount stops where the server can store it, and says so',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await _openForm(tester, api);
      await _type(tester, '21474836');
      await tester.tap(find.text(','));
      await tester.pump();
      await _type(tester, '48');
      expect(find.text('₺21.474.836,4'), findsOneWidget, reason: 'refused 8');
      expect(find.text('En fazla ₺21.474.836,47 girilebilir'), findsOneWidget);
    });

    testWidgets('closing with unsaved changes asks first; "Düzenlemeye devam" '
        'keeps them', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await _openForm(tester, api);
      await _type(tester, '12');
      await tester.tap(find.byIcon(Icons.close_rounded));
      await settleFrames(tester);
      expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
      await tester.tap(find.text('Düzenlemeye devam'));
      await settleFrames(tester);
      expect(find.text('₺12'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await settleFrames(tester);
      await tester.tap(find.text('Değişiklikleri at'));
      await settleFrames(tester);
      expect(find.text('open'), findsOneWidget, reason: 'closed');
      expect(api.bodiesOf('POST /transactions'), isEmpty);
    });
  });

  group('the transactions list', () {
    testWidgets('a swipe deletes with "Geri al", no dialog: undo sends '
        'nothing', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await pumpFinance(tester, api, const TransactionsScreen());
      expect(find.text('Kahve'), findsOneWidget);

      await tester.drag(find.text('Kahve'), const Offset(-600, 0));
      await settleFrames(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Kahve'), findsNothing);
      expect(find.text('İşlem silindi'), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /transactions/316')));

      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(find.text('Kahve'), findsOneWidget);
      await letUndoRunOut(tester);
      expect(api.requests, isNot(contains('DELETE /transactions/316')));
    });

    testWidgets('a swipe left alone: the delete goes once the snackbar does',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.drag(find.text('Kahve'), const Offset(-600, 0));
      await settleFrames(tester);
      // What the server lists once the delete has gone through.
      api.on('GET /transactions', {
        'transactions': const [],
        'meta': const {'total_count': 0, 'page': 1, 'page_limit': 50},
      });
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /transactions/316'));
      expect(find.text('Kahve'), findsNothing);
    });

    testWidgets('leaving İşlemler ends the undo window: the delete goes at '
        'once, and its "Geri al" goes with it', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await pumpFinance(tester, api, _pusher('/finance/transactions'));
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await tester.drag(find.text('Kahve'), const Offset(-600, 0));
      await settleFrames(tester);
      expect(find.text('İşlem silindi'), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /transactions/316')));

      // Back, well inside the snackbar's 6 s.
      await tester.tap(find.byType(BackButton));
      await settleFrames(tester);
      expect(find.text('open'), findsOneWidget);
      expect(api.requests, contains('DELETE /transactions/316'));
      expect(find.text('İşlem silindi'), findsNothing);
      expect(find.text('Geri al'), findsNothing);
      await letUndoRunOut(tester);
      expect(api.requests.where((r) => r == 'DELETE /transactions/316'),
          hasLength(1));
    });

    testWidgets('…and so does leaving an account\'s history; the sheet\'s '
        '"Sil" the same', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await pumpFinance(tester, api, _pusher('/finance/account/1'));
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await tester.tap(find.text('Kahve'));
      await settleFrames(tester);
      await tester.tap(_inSheet(find.text('Sil')));
      await settleFrames(tester);
      expect(find.text('İşlem silindi'), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /transactions/316')));

      await tester.tap(find.byType(BackButton));
      await settleFrames(tester);
      expect(api.requests, contains('DELETE /transactions/316'));
      expect(find.text('Geri al'), findsNothing);
    });

    testWidgets('a delete undone stays undone when the screen is left',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await pumpFinance(tester, api, _pusher('/finance/transactions'));
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await tester.drag(find.text('Kahve'), const Offset(-600, 0));
      await settleFrames(tester);
      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(find.text('Kahve'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await letUndoRunOut(tester);
      expect(api.requests, isNot(contains('DELETE /transactions/316')));
    });

    testWidgets('the sheet of a row: Düzenle opens the form, Sil deletes '
        'with "Geri al"', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.tap(find.text('Kahve'));
      await settleFrames(tester);
      expect(_inSheet(find.text('Düzenle')), findsOneWidget);
      await tester.tap(_inSheet(find.text('Sil')));
      await settleFrames(tester);
      expect(find.text('Kahve'), findsNothing);
      expect(find.text('İşlem silindi'), findsOneWidget);
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /transactions/316'));
    });

    testWidgets('day headings never pile up: each is pushed away by the next '
        'day\'s', (tester) async {
      tallPhone(tester);
      // Ten days in May, five rows each.
      final api = FakeApi()
        ..on('GET /transactions', {
          'transactions': [
            for (var day = 20; day > 10; day--)
              for (var i = 0; i < 5; i++)
                {
                  ...transactionJson(id: day * 10 + i),
                  'date': isoDate(DateTime(2026, 5, day)),
                  'description': 'Satır $day-$i',
                },
          ],
          'meta': const {'total_count': 50, 'page': 1, 'page_limit': 50},
        });
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1600));
      await settleFrames(tester);

      final headings = [
        for (final element in find.textContaining('Mayıs').evaluate())
          tester.getTopLeft(find.byWidget(element.widget)).dy,
      ]..sort();
      expect(headings.length, greaterThan(1));
      for (var i = 1; i < headings.length; i++) {
        // A day's five rows sit between two headings; piled-up headings
        // would be one heading's height (36) apart.
        expect(headings[i] - headings[i - 1], greaterThan(64),
            reason: 'headings at $headings');
      }
    });

    testWidgets('the summary is in the filtered account\'s currency',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /accounts', _accounts())
        ..on('GET /transactions', {
          'transactions': const [],
          'meta': const {
            'total_count': 0,
            'page': 1,
            'page_limit': 50,
            'filtered_income_cents': 5,
            'filtered_expense_cents': 12,
          },
        });
      await pumpFinance(
        tester,
        api,
        const TransactionsScreen(initial: TxFilters(accountId: 3)),
      );
      expect(find.text('5\u00A0gr gelir · 12\u00A0gr gider'), findsOneWidget);
    });

    testWidgets('the category filter offers every category and "Kategorisiz"',
        (tester) async {
      tallPhone(tester);
      final queries = <Map<String, dynamic>>[];
      final api = FakeApi()
        ..on('GET /finance_categories', {
          'categories': [
            categoryJson(),
            categoryJson(id: 6, name: 'Atıştırmalık', parentId: 5),
            categoryJson(id: 7, name: 'Maaş', kind: 'income'),
          ],
        })
        ..onRequest('GET /transactions', (request) {
          queries.add(request.queryParameters);
          return {
            'transactions': [transactionJson()],
            'meta': const {'total_count': 1, 'page': 1, 'page_limit': 50},
          };
        });
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.ensureVisible(find.text('Kategori'));
      await settleFrames(tester);
      await tester.tap(find.text('Kategori'));
      await settleFrames(tester);
      for (final label in [
        'Tüm kategoriler',
        'Kategorisiz',
        'GİDER',
        'Market',
        'Atıştırmalık',
        'GELİR',
        'Maaş',
      ]) {
        expect(_inSheet(find.text(label)), findsOneWidget, reason: label);
      }
      await tester.tap(_inSheet(find.text('Kategorisiz')));
      await settleFrames(tester);
      expect(queries.last['category_id'], 'none');
      expect(find.text('Kategorisiz'), findsWidgets, reason: 'the chip');
    });

    testWidgets('a drill-down opens with its filters on: this month\'s '
        'uncategorized spending', (tester) async {
      tallPhone(tester);
      final today = DateTime.now();
      final queries = <Map<String, dynamic>>[];
      final api = FakeApi()
        ..onRequest('GET /transactions', (request) {
          queries.add(request.queryParameters);
          return {
            'transactions': const [],
            'meta': const {'total_count': 0, 'page': 1, 'page_limit': 50},
          };
        });
      await pumpFinance(
        tester,
        api,
        TransactionsScreen(
          initial: TxFilters(
            kind: 'expense',
            uncategorized: true,
            from: DateTime(today.year, today.month, 1),
            to: DateTime(today.year, today.month + 1, 0),
          ),
        ),
      );
      expect(queries.single['category_id'], 'none');
      expect(queries.single['kind'], 'expense');
      expect(queries.single['from'], isoDate(DateTime(today.year, today.month, 1)));
      expect(find.text('Bu ay'), findsOneWidget);
      expect(find.text('Kategorisiz'), findsOneWidget);
      expect(find.text('Bu filtreyle işlem yok'), findsOneWidget);
      // One tap clears them all.
      await tester.tap(find.text('Filtreleri temizle').first);
      await settleFrames(tester);
      expect(queries.last, {'page': 1});
    });
  });

  group('a pair the web saved together (contract 4.3, linked)', () {
    /// The cash expense (316, "Kahve") and the gold it bought (317), as
    /// İşlemler lists them; [linked] is what GET /transactions/316 says.
    FakeApi pairApi({Map<String, dynamic>? linked}) => FakeApi()
      ..on('GET /transactions', {
        'transactions': [
          transactionJson(),
          {
            ...transactionJson(id: 317),
            'kind': 'income',
            'amount_cents': 2,
            'description': 'Altın alımı',
            'account': {
              'id': 3,
              'name': 'Altın',
              'color': '#B8860B',
              'currency': 'GAU',
              'subunit_to_unit': 1,
            },
          },
        ],
        'meta': const {'total_count': 2, 'page': 1, 'page_limit': 50},
      })
      ..on('GET /transactions/316', {
        'transaction': transactionDetailJson(linked: linked),
      });

    testWidgets('the sheet of the parent shows its linked row; "Sil" asks '
        'first, naming it — "Vazgeç" keeps both', (tester) async {
      tallPhone(tester);
      final api = pairApi(linked: linkedJson());
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.tap(find.text('Kahve'));
      await settleFrames(tester);
      expect(_inSheet(find.text('Bağlı işlem')), findsOneWidget);
      expect(_inSheet(find.text('Altın')), findsOneWidget);
      expect(_inSheet(find.text('Altın alımı · 2 Ekim 2026')), findsOneWidget);
      expect(_inSheet(find.text('+2\u00A0gr')), findsOneWidget);
      expect(
        _inSheet(find.text('Bu işlem silinirse bağlı işlem de silinir.')),
        findsOneWidget,
      );

      await tester.tap(_inSheet(find.text('Sil')));
      await settleFrames(tester);
      expect(find.text('“Kahve” silinsin mi?'), findsOneWidget);
      expect(
        find.text('Bağlı işlem de silinecek: Altın · +2\u00A0gr · 2 Ekim 2026. '
            'Bu geri alınamaz.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Vazgeç'));
      await settleFrames(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'still open');
      expect(api.requests, isNot(contains('DELETE /transactions/316')));
    });

    testWidgets('confirmed, both go at once — no "Geri al" — and leave the '
        'list', (tester) async {
      tallPhone(tester);
      final api = pairApi(linked: linkedJson());
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.tap(find.text('Kahve'));
      await settleFrames(tester);
      await tester.tap(_inSheet(find.text('Sil')));
      await settleFrames(tester);
      await tester.tap(find.text('İkisini de sil'));
      await settleFrames(tester);

      expect(api.requests, contains('DELETE /transactions/316'));
      expect(find.text('İşlem ve bağlı işlem silindi'), findsOneWidget);
      expect(find.text('Geri al'), findsNothing);
      // The refetch the delete triggers still lists both on this fake
      // server: they stay hidden all the same.
      expect(find.text('Kahve'), findsNothing);
      expect(find.text('Altın alımı'), findsNothing);
    });

    testWidgets('a refused delete of the pair brings both back and says so',
        (tester) async {
      tallPhone(tester);
      final api = pairApi(linked: linkedJson())
        ..fail('DELETE /transactions/316', 500);
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.tap(find.text('Kahve'));
      await settleFrames(tester);
      await tester.tap(_inSheet(find.text('Sil')));
      await settleFrames(tester);
      await tester.tap(find.text('İkisini de sil'));
      await settleFrames(tester);

      expect(find.text('Silinemedi'), findsOneWidget);
      expect(find.text('Kahve'), findsOneWidget);
      expect(find.text('Altın alımı'), findsOneWidget);
    });

    testWidgets('a swipe on the parent asks too: kept, the row slides back; '
        'confirmed, both go', (tester) async {
      tallPhone(tester);
      final api = pairApi(linked: linkedJson());
      await pumpFinance(tester, api, const TransactionsScreen());

      await tester.drag(find.text('Kahve'), const Offset(-600, 0));
      await settleFrames(tester);
      expect(find.text('“Kahve” silinsin mi?'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await settleFrames(tester);
      expect(find.text('Kahve'), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /transactions/316')));

      await tester.drag(find.text('Kahve'), const Offset(-600, 0));
      await settleFrames(tester);
      await tester.tap(find.text('İkisini de sil'));
      await settleFrames(tester);
      expect(api.requests, contains('DELETE /transactions/316'));
      expect(find.text('Kahve'), findsNothing);
      expect(find.text('Altın alımı'), findsNothing);
    });

    testWidgets('the child of a pair goes with "Geri al", like any other: its '
        'parent stays', (tester) async {
      tallPhone(tester);
      final api = pairApi(
        linked: linkedJson(
          id: 317,
          kind: 'expense',
          amount: 600000,
          relation: 'parent',
        ),
      );
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.tap(find.text('Kahve'));
      await settleFrames(tester);
      expect(
        _inSheet(find.text('Bu işlem silinirse bağlı işlem silinmez.')),
        findsOneWidget,
      );
      await tester.tap(_inSheet(find.text('Sil')));
      await settleFrames(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('İşlem silindi'), findsOneWidget);
      expect(find.text('Geri al'), findsOneWidget);
      expect(find.text('Kahve'), findsNothing);
      expect(find.text('Altın alımı'), findsOneWidget);
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /transactions/316'));
    });

    testWidgets('when what it is linked to cannot be read, nothing is '
        'deleted and the snackbar says so', (tester) async {
      tallPhone(tester);
      final api = pairApi()..failNetwork('GET /transactions/316');
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.drag(find.text('Kahve'), const Offset(-600, 0));
      await settleFrames(tester);
      expect(find.text('Silinemedi'), findsOneWidget);
      expect(find.text('Kahve'), findsOneWidget, reason: 'slid back');
      await letUndoRunOut(tester);
      expect(api.requests, isNot(contains('DELETE /transactions/316')));
    });

    testWidgets('in the sheet, a link that cannot be read is said there — '
        'not in a snackbar under the sheet — and nothing is deleted',
        (tester) async {
      tallPhone(tester);
      final api = pairApi()..failNetwork('GET /transactions/316');
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.tap(find.text('Kahve'));
      await settleFrames(tester);
      await tester.tap(_inSheet(find.text('Sil')));
      await settleFrames(tester);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'still open');
      expect(_inSheet(find.text('Silinemedi')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Kahve'), findsWidgets, reason: 'still listed');
      await letUndoRunOut(tester);
      expect(api.requests, isNot(contains('DELETE /transactions/316')));

      // Readable again: the next "Sil" goes as usual.
      api.on('GET /transactions/316', {
        'transaction': transactionDetailJson(),
      });
      await tester.tap(_inSheet(find.text('Sil')));
      await settleFrames(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('İşlem silindi'), findsOneWidget);
    });

    testWidgets('the sheet of a transaction deleted elsewhere says so, and '
        'offers neither edit nor delete', (tester) async {
      tallPhone(tester);
      final api = pairApi()..fail('GET /transactions/316', 404);
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.tap(find.text('Kahve'));
      await settleFrames(tester);
      expect(_inSheet(find.text('Bu işlem silinmiş')), findsOneWidget);
      expect(_inSheet(find.text('Düzenle')), findsNothing);
      expect(_inSheet(find.text('Sil')), findsNothing);
    });

    testWidgets('an account\'s history asks the same before a swipe takes '
        'the pair', (tester) async {
      tallPhone(tester);
      final api = pairApi(linked: linkedJson());
      await pumpFinance(tester, api, const AccountDetailScreen(accountId: 1));
      await tester.drag(find.text('Kahve'), const Offset(-600, 0));
      await settleFrames(tester);
      expect(find.text('“Kahve” silinsin mi?'), findsOneWidget);
      await tester.tap(find.text('İkisini de sil'));
      await settleFrames(tester);
      expect(api.requests, contains('DELETE /transactions/316'));
      expect(find.text('İşlem ve bağlı işlem silindi'), findsOneWidget);
    });
  });

  testWidgets('Finance shows the month\'s uncategorized spending, and a tap '
      'opens it in İşlemler', (tester) async {
    tallPhone(tester);
    final queries = <Map<String, dynamic>>[];
    final api = FakeApi()
      ..on('GET /finance/dashboard', {
        'currency': 'TRY',
        'subunit_to_unit': 100,
        'month': {'income_cents': 0, 'expense_cents': 691100, 'net_cents': -691100},
        'year': {'income_cents': 0, 'expense_cents': 691100},
        'six_month_series': {'labels': [], 'income_cents': [], 'expense_cents': []},
        'pie': [
          {'id': 0, 'name': 'Uncategorized', 'color': '#6E6A64', 'amount_cents': 625000, 'breakdown': [], 'uncategorized': true},
          {'id': 5, 'name': 'Market', 'color': '#D4915A', 'amount_cents': 66100, 'breakdown': []},
        ],
        'budgets': [],
        'upcoming_subscriptions': [],
        'recent_transactions': [transactionJson()],
      })
      ..onRequest('GET /transactions', (request) {
        queries.add(request.queryParameters);
        return {
          'transactions': const [],
          'meta': const {'total_count': 0, 'page': 1, 'page_limit': 50},
        };
      });
    await pumpFinance(tester, api, const FinanceScreen());
    await tester.dragUntilVisible(find.text('Kategorize et'),
        find.byType(ListView).first, const Offset(0, -300));
    await settleFrames(tester);
    // Worded by the app, not the server's English.
    expect(find.text('Kategorisiz'), findsOneWidget);
    expect(find.text('Uncategorized'), findsNothing);

    await tester.tap(find.text('Kategorize et'));
    await settleFrames(tester);
    expect(find.text('İşlemler'), findsOneWidget);
    expect(queries.single['category_id'], 'none');
    expect(queries.single['kind'], 'expense');
  });

  group('a slice\'s breakdown opens only what İşlemler can list', () {
    /// Market's 661,00: 575,50 filed under Market itself, 85,50 under its
    /// subcategory Atıştırmalık.
    FakeApi breakdownApi(List<Map<String, dynamic>> queries) => FakeApi()
      ..on('GET /finance/dashboard', {
        'currency': 'TRY',
        'subunit_to_unit': 100,
        'month': {'income_cents': 0, 'expense_cents': 66100, 'net_cents': -66100},
        'year': {'income_cents': 0, 'expense_cents': 66100},
        'six_month_series': {'labels': [], 'income_cents': [], 'expense_cents': []},
        'pie': [
          {
            'id': 5,
            'name': 'Market',
            'color': '#D4915A',
            'amount_cents': 66100,
            'breakdown': [
              {'id': 5, 'name': 'Market', 'amount_cents': 57550, 'is_root': true},
              {'id': 6, 'name': 'Atıştırmalık', 'amount_cents': 8550, 'is_root': false},
            ],
          },
        ],
        'budgets': [],
        'upcoming_subscriptions': [],
        'recent_transactions': [],
      })
      ..onRequest('GET /transactions', (request) {
        queries.add(request.queryParameters);
        return {
          'transactions': const [],
          'meta': const {'total_count': 0, 'page': 1, 'page_limit': 50},
        };
      });

    Future<void> openSheet(WidgetTester tester, FakeApi api) async {
      await pumpFinance(tester, api, const FinanceScreen());
      await tester.dragUntilVisible(find.text('Market'),
          find.byType(ListView).first, const Offset(0, -300));
      await settleFrames(tester);
      await tester.tap(find.text('Market'));
      await settleFrames(tester);
    }

    testWidgets('the whole slice, the category\'s own part and each '
        'subcategory; the own part opens nothing', (tester) async {
      tallPhone(tester);
      final queries = <Map<String, dynamic>>[];
      final api = breakdownApi(queries);
      await openSheet(tester, api);
      expect(_inSheet(find.text('Tümü')), findsOneWidget);
      expect(_inSheet(find.text('Alt kategoriler dahil')), findsOneWidget);
      expect(_inSheet(find.text('−₺661,00')), findsOneWidget);
      expect(_inSheet(find.text('Market (genel)')), findsOneWidget);
      expect(_inSheet(find.text('−₺575,50')), findsOneWidget);
      expect(_inSheet(find.text('Atıştırmalık')), findsOneWidget);
      expect(_inSheet(find.text('−₺85,50')), findsOneWidget);

      // İşlemler cannot list Market without its subcategory: no drill.
      await tester.tap(_inSheet(find.text('Market (genel)')));
      await settleFrames(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(queries, isEmpty);

      await tester.tap(_inSheet(find.text('Atıştırmalık')));
      await settleFrames(tester);
      expect(find.text('İşlemler'), findsOneWidget);
      expect(queries.single['category_id'], 6);
      expect(queries.single['kind'], 'expense');
    });

    testWidgets('"Tümü" opens the whole slice: Market with its subcategory',
        (tester) async {
      tallPhone(tester);
      final queries = <Map<String, dynamic>>[];
      final api = breakdownApi(queries);
      await openSheet(tester, api);
      await tester.tap(_inSheet(find.text('Tümü')));
      await settleFrames(tester);
      expect(find.text('İşlemler'), findsOneWidget);
      expect(queries.single['category_id'], 5);
    });
  });
}
