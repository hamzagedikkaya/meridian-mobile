/// Recording money without the web (contract G2.3): a transaction without
/// a category, a category made from the picker, transfers within one
/// currency, edits that send only what changed — and the list: deletes with
/// "Geri al", day headings that never pile up, filters that work.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/date_utils.dart';
import 'package:meridian_mobile/models/transaction.dart';
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
      expect(find.text('21.474.836,4 ₺'), findsOneWidget, reason: 'refused 8');
      expect(find.text('En fazla 21.474.836,47 ₺ girilebilir'), findsOneWidget);
    });

    testWidgets('closing with unsaved changes asks first; "Düzenlemeye devam" '
        'keeps them', (tester) async {
      tallPhone(tester);
      final api = FakeApi();
      await _openForm(tester, api);
      await _type(tester, '12');
      await tester.tap(find.byIcon(Icons.close));
      await settleFrames(tester);
      expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
      await tester.tap(find.text('Düzenlemeye devam'));
      await settleFrames(tester);
      expect(find.text('12 ₺'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
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
      expect(find.text('5 gr gelir · 12 gr gider'), findsOneWidget);
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
}
