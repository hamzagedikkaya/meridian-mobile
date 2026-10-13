/// İşlemler and the transaction form, Noktürn v2 (design-analysis §7.7,
/// WP-9): filter chips that fit a 360 dp phone, the day's spending in its
/// heading, rows that leave out the filtered account, the search (`q`,
/// contract 13.2 — and on the phone when the server ignores it), a long
/// press's actions, and a form that records an expense without scrolling,
/// rebuilding only the amount as it is typed.
///
/// Measured in the app's own fonts on a 360×780 phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/ui/screens/finance/account_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/category_picker.dart';
import 'package:meridian_mobile/ui/screens/finance/filter_chip_bar.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/transaction_form_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/transactions_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/tx_row.dart';
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart';
import 'package:meridian_mobile/ui/widgets/collapsing_fab.dart';
import 'package:meridian_mobile/ui/widgets/form_scaffold.dart';
import 'package:meridian_mobile/ui/widgets/money_text.dart';
import 'package:meridian_mobile/ui/widgets/pressable_scale.dart';

import '../support/app_fonts.dart';
import '../support/fake_api.dart';
import '../support/app_harness.dart' show fixtureNow;
import '../support/finance_harness.dart';
import '../support/semantics.dart';

/// The phone the form is laid out for: 360×780.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Whether [finder]'s widget lies wholly on the 360×780 screen.
bool _onScreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  return rect.left >= 0 &&
      rect.right <= 360 &&
      rect.top >= 0 &&
      rect.bottom <= 780;
}

Map<String, dynamic> _row(
  int id, {
  String kind = 'expense',
  int cents = 1000,
  String date = '2026-10-04',
  String? description,
  String? note,
  Map<String, dynamic>? related,
}) =>
    {
      ...transactionJson(id: id),
      'kind': kind,
      'amount_cents': cents,
      'date': date,
      'description': description,
      'note': note,
      'related_account': related,
    };

/// Coffee and the groceries whose note mentions it — and the rent.
List<Map<String, dynamic>> _searchRows() => [
      _row(1, description: 'Kahve', cents: 8500),
      _row(2, description: 'Market', note: 'kahve, süt', cents: 41250),
      _row(3, description: 'Kira', cents: 1500000),
    ];

/// A page that pushes [location] — a screen that can be left.
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

/// The six expense categories used most, and one income category.
const _sixCategories = [
  'Market',
  'Restoran',
  'Kafe',
  'Ulaşım',
  'Faturalar',
  'Sağlık',
];

FakeApi _withSixCategories() => FakeApi()
  ..on('GET /finance_categories', {
    'categories': [
      for (var i = 0; i < _sixCategories.length; i++)
        categoryJson(id: 5 + i, name: _sixCategories[i], position: i),
      categoryJson(id: 30, name: 'Maaş', kind: 'income'),
    ],
  });

/// Opens the form as a transfer from Cüzdan, with Banka beside it.
Widget _transferLauncher({Transaction? existing}) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => openTransactionForm(context,
                existing: existing,
                initialKind: existing == null ? 'transfer' : null,
                initialAccountId: existing == null ? 1 : null),
            child: const Text('open'),
          ),
        ),
      ),
    );

FakeApi _twoAccounts({int wallet = 500000, int bank = 0}) => FakeApi()
  ..on('GET /accounts', {
    'accounts': [
      accountJson(balance: wallet),
      accountJson(id: 2, name: 'Banka', type: 'bank', balance: bank),
    ],
  });

/// Larger text, as the system setting sets it, for this test.
void _textScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await initializeDateFormatting();
  });

  group('İşlemler', () {
    testWidgets('the four filter chips fit a 360 dp phone; with a filter on, '
        'the × that clears it stays in reach', (tester) async {
      _phone(tester);
      await pumpFinance(tester, FakeApi(), const TransactionsScreen());
      for (final chip in ['Tür', 'Hesap', 'Kategori', 'Tarih']) {
        expect(_onScreen(tester, find.text(chip)), isTrue, reason: chip);
      }
      expect(find.byTooltip('Filtreleri temizle'), findsNothing);

      await pumpFinance(
        tester,
        FakeApi(),
        const TransactionsScreen(initial: TxFilters(kind: 'expense')),
      );
      expect(find.text('Tür: Gider'), findsOneWidget);
      final clear = find.byTooltip('Filtreleri temizle');
      expect(_onScreen(tester, clear), isTrue);
      expect(tester.getSize(clear).height, greaterThanOrEqualTo(48));
      await tester.tap(clear);
      await settleFrames(tester);
      expect(find.text('Tür'), findsOneWidget);
    });

    final now = fixtureNow;
    final everyFilter = TxFilters(
      kind: 'expense',
      accountId: 1,
      categoryId: 5,
      from: DateTime(now.year, now.month, 1),
      to: DateTime(now.year, now.month + 1, 0),
    );
    for (final (locale, clearLabel) in [
      (const Locale('tr'), 'Filtreleri temizle'),
      (const Locale('en'), 'Clear filters'),
    ]) {
      for (final (name, filters) in [
        ('at rest', const TxFilters()),
        ('one filter on', const TxFilters(kind: 'expense')),
        ('only the date on', TxFilters(from: everyFilter.from, to: everyFilter.to)),
        ('every filter on', everyFilter),
      ]) {
        testWidgets('${locale.languageCode}, $name: all four chips — and the '
            '× while a filter is on — lie whole on a 360 dp screen',
            (tester) async {
          _phone(tester);
          await pumpFinance(
            tester,
            FakeApi(),
            TransactionsScreen(initial: filters),
            locale: locale,
          );
          final chips = find.descendant(
            of: find.byType(FilterChipBar),
            matching: find.byType(PressableScale),
          );
          expect(chips, findsNWidgets(4));
          for (var i = 0; i < 4; i++) {
            expect(_onScreen(tester, chips.at(i)), isTrue,
                reason: 'chip ${i + 1}: ${tester.getRect(chips.at(i))}');
          }
          final clear = find.byTooltip(clearLabel);
          if (filters == const TxFilters()) {
            expect(clear, findsNothing);
            // At rest the four take one line.
            final top = tester.getRect(chips.at(0)).top;
            for (var i = 1; i < 4; i++) {
              expect(tester.getRect(chips.at(i)).top, top,
                  reason: 'chip ${i + 1} on the first line');
            }
          } else {
            expect(_onScreen(tester, clear), isTrue,
                reason: '× ${tester.getRect(clear)}');
            // Nothing lies over another: the × hides no chip.
            for (var i = 0; i < 4; i++) {
              expect(
                tester.getRect(chips.at(i)).overlaps(tester.getRect(clear)),
                isFalse,
                reason: 'chip ${i + 1}',
              );
            }
          }
        });
      }
    }

    testWidgets('a day of another year says which', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /transactions', {
          'transactions': [
            _row(1, date: '${fixtureNow.year - 1}-09-29',
                description: 'Eski'),
          ],
          'meta': const {'total_count': 1, 'page': 1, 'page_limit': 50},
        });
      await pumpFinance(tester, api, const TransactionsScreen());
      expect(find.textContaining('29 Eylül ${fixtureNow.year - 1}'),
          findsOneWidget);
    });

    testWidgets('an account\'s history says the year of another year\'s day '
        'too', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /transactions', {
          'transactions': [
            _row(1, date: '${DateTime.now().year - 1}-09-29',
                description: 'Eski'),
          ],
          'meta': const {'total_count': 1, 'page': 1, 'page_limit': 50},
        });
      await pumpFinance(tester, api, const AccountDetailScreen(accountId: 1));
      expect(find.textContaining('29 Eylül ${DateTime.now().year - 1}'),
          findsOneWidget);
    });

    testWidgets('scrolled to the end, the FAB covers no row\'s amount',
        (tester) async {
      _phone(tester);
      final rows = [
        for (var i = 0; i < 30; i++)
          _row(i + 1,
              cents: i == 29 ? 77700 : 1000 + i,
              date: '2026-09-${(i ~/ 3 + 1).toString().padLeft(2, '0')}',
              description: 'Satır $i'),
      ];
      final api = FakeApi()
        ..on('GET /transactions', {
          'transactions': rows,
          'meta': const {'total_count': 30, 'page': 1, 'page_limit': 50},
        });
      await pumpFinance(tester, api, const TransactionsScreen());
      final list = find.byType(CustomScrollView);
      for (var i = 0; i < 20; i++) {
        await tester.drag(list, const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settleFrames(tester);
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).last).position;
      expect(position.pixels, position.maxScrollExtent, reason: 'at the end');
      final fab = tester.getRect(find.byType(FloatingActionButton));
      final amounts = find.descendant(
        of: find.byType(TxRow),
        matching: find.byType(MoneyText),
      );
      expect(amounts, findsWidgets);
      final last = find.descendant(
        of: find.byType(TxRow),
        matching:
            find.byWidgetPredicate((w) => w is MoneyText && w.cents == 77700),
      );
      expect(last, findsOneWidget);
      expect(fab.overlaps(tester.getRect(last)), isFalse,
          reason: 'fab $fab, amount ${tester.getRect(last)}');
      for (var i = 0; i < amounts.evaluate().length; i++) {
        final rect = tester.getRect(amounts.at(i));
        if (rect.bottom <= 0 || rect.top >= 780) continue;
        expect(fab.overlaps(rect), isFalse, reason: 'amount $rect');
      }
      expect(find.byType(CollapsingFab), findsOneWidget);
    });

    testWidgets('a day\'s heading carries what was spent that day — '
        'expenses only, never a transfer or an income', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /transactions', {
          'transactions': [
            _row(1, cents: 10000, description: 'Market'),
            _row(2, cents: 4050, description: 'Kahve'),
            _row(3, kind: 'income', cents: 500000, description: 'Maaş'),
            _row(4,
                kind: 'transfer',
                cents: 300000,
                related: {'id': 2, 'name': 'Birikim'}),
            _row(5, date: '2026-10-03', cents: 2500, description: 'Simit'),
          ],
          'meta': const {'total_count': 5, 'page': 1, 'page_limit': 50},
        });
      await pumpFinance(tester, api, const TransactionsScreen());
      expect(find.text('−₺140,50'), findsOneWidget);
      expect(find.text('−₺25'), findsOneWidget);
    });

    testWidgets('filtered to one account, the rows leave its name out',
        (tester) async {
      tallPhone(tester);
      await pumpFinance(
        tester,
        FakeApi(),
        const TransactionsScreen(initial: TxFilters(accountId: 1)),
      );
      expect(find.text('Kahve'), findsOneWidget);
      expect(find.text('Kategorisiz · Cüzdan'), findsNothing);
      expect(find.text('Kategorisiz'), findsOneWidget);
    });

    testWidgets('the search sends what is typed 300 ms after the last key, '
        'from two characters on, and says when nothing matches',
        (tester) async {
      tallPhone(tester);
      final queries = <Map<String, dynamic>>[];
      final feed = transactionsFeed(_searchRows());
      final api = FakeApi()
        ..onRequest('GET /transactions', (request) {
          queries.add(request.queryParameters);
          return feed(request);
        });
      await pumpFinance(tester, api, const TransactionsScreen());
      expect(find.text('Kira'), findsOneWidget);

      await tester.tap(find.byTooltip('Ara'));
      await settleFrames(tester);
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

      await tester.enterText(field, 'k');
      await settleFrames(tester);
      expect(queries.where((q) => q.containsKey('q')), isEmpty,
          reason: 'one character is not searched');

      await tester.enterText(field, 'KAHVE');
      await tester.pump(const Duration(milliseconds: 200));
      expect(queries.where((q) => q.containsKey('q')), isEmpty,
          reason: 'still typing');
      await settleFrames(tester);
      expect(queries.last['q'], 'KAHVE');
      expect(find.text('Kahve'), findsOneWidget);
      expect(find.text('Market'), findsOneWidget, reason: 'its note');
      expect(find.text('Kira'), findsNothing);

      await tester.enterText(field, 'çay');
      await settleFrames(tester);
      expect(find.text('Sonuç yok · “çay”'), findsOneWidget);
      await tester.tap(find.text('Aramayı temizle').last);
      await settleFrames(tester);
      expect(queries.last.containsKey('q'), isFalse);
      expect(find.text('Kira'), findsOneWidget);

      await tester.tap(find.byTooltip('Aramayı kapat'));
      await settleFrames(tester);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a server that ignores `q` lists everything: the search then '
        'runs on the phone, totals and all', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /transactions', {
          'transactions': _searchRows(),
          'meta': const {
            'total_count': 3,
            'page': 1,
            'page_limit': 50,
            'filtered_income_cents': 0,
            'filtered_expense_cents': 1549750,
          },
        });
      await pumpFinance(
        tester,
        api,
        const TransactionsScreen(initial: TxFilters(q: 'kahve')),
      );
      expect(find.text('Kahve'), findsOneWidget);
      expect(find.text('Market'), findsOneWidget);
      expect(find.text('Kira'), findsNothing);
      expect(find.text('₺0 gelir · ₺497,50 gider'), findsOneWidget);
    });

    testWidgets('`?search=1` opens İşlemler with the search focused',
        (tester) async {
      tallPhone(tester);
      await pumpFinance(
          tester, FakeApi(), _pusher('/finance/transactions?search=1'));
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
    });

    testWidgets('a long press offers Düzenle · Bugüne kopyala · Sil; the copy '
        'is saved at once, with "Geri al"', (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('POST /transactions', {
          'transaction': {...transactionJson(id: 400)},
        });
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.longPress(find.text('Kahve'));
      await settleFrames(tester);
      for (final action in ['Düzenle', 'Bugüne kopyala', 'Sil']) {
        expect(
          find.descendant(
              of: find.byType(BottomSheet), matching: find.text(action)),
          findsOneWidget,
          reason: action,
        );
      }
      await tester.tap(find.text('Bugüne kopyala'));
      await settleFrames(tester);
      final body = api.bodiesOf('POST /transactions').single as Map;
      expect(body['kind'], 'expense');
      expect(body['amount_cents'], 13874);
      expect(body['account_id'], 1);
      expect(body['description'], 'Kahve');
      expect(find.text('Bugüne kopyalandı'), findsOneWidget);
      expect(find.text('Geri al'), findsOneWidget);
    });

    testWidgets('a copy whose answer is lost may have been saved: it says '
        'so, not "try again"', (tester) async {
      tallPhone(tester);
      final api = FakeApi()..timeOut('POST /transactions');
      await pumpFinance(tester, api, const TransactionsScreen());
      await tester.longPress(find.text('Kahve'));
      await settleFrames(tester);
      await tester.tap(find.text('Bugüne kopyala'));
      await settleFrames(tester);
      expect(find.textContaining('kaydedilmiş olabilir'), findsOneWidget);
    });

    // The same row grammar in every list (§6.4): an account's history and
    // Finance's "Son işlemler" too.
    for (final (place, home) in [
      ('an account\'s history', const AccountDetailScreen(accountId: 1)),
      ('Finance\'s recent rows', const FinanceScreen()),
    ]) {
      testWidgets('$place: a long press offers Düzenle · Bugüne kopyala · '
          'Sil, a swipe deletes, and a screen reader gets all three',
          (tester) async {
        tallPhone(tester);
        final handle = tester.ensureSemantics();
        final api = FakeApi()
          ..on('GET /finance/dashboard', {
            ...financeDashboardJson(),
            'recent_transactions': [transactionJson()],
          })
          ..on('POST /transactions', {
            'transaction': {...transactionJson(id: 400)},
          });
        await pumpFinance(tester, api, home);
        expect(find.text('Kahve'), findsOneWidget);
        expect(
          customActionLabels(tester.getSemantics(find.text('Kahve'))),
          containsAll(['Düzenle', 'Bugüne kopyala', 'Sil']),
        );

        await tester.longPress(find.text('Kahve'));
        await settleFrames(tester);
        for (final action in ['Düzenle', 'Bugüne kopyala', 'Sil']) {
          expect(
            find.descendant(
                of: find.byType(BottomSheet), matching: find.text(action)),
            findsOneWidget,
            reason: action,
          );
        }
        await tester.tap(find.text('Bugüne kopyala'));
        await settleFrames(tester);
        expect(api.bodiesOf('POST /transactions'), hasLength(1));
        expect(find.text('Bugüne kopyalandı'), findsOneWidget);
        await letUndoRunOut(tester);

        await tester.drag(find.text('Kahve'), const Offset(-600, 0));
        await settleFrames(tester);
        expect(find.text('İşlem silindi'), findsOneWidget);
        handle.dispose();
      });
    }
  });

  group('the transaction form', () {
    testWidgets('360×780: an expense is digits, one chip and "Kaydet" — '
        'nothing scrolls', (tester) async {
      _phone(tester);
      final api = FakeApi();
      await pumpFinance(tester, api, _formLauncher());
      await tester.tap(find.text('open'));
      await settleFrames(tester);

      final body = find.descendant(
        of: find.byType(TransactionFormScreen),
        matching: find.byWidgetPredicate((w) =>
            w is Scrollable && w.axisDirection == AxisDirection.down),
      );
      expect(
        tester.state<ScrollableState>(body.first).position.maxScrollExtent,
        0,
        reason: 'the form fits',
      );
      for (final key in ['1', '0', '8', '5']) {
        expect(_onScreen(tester, find.text(key).last), isTrue, reason: key);
      }
      expect(_onScreen(tester, find.text('Market')), isTrue);
      expect(_onScreen(tester, find.text('Kaydet')), isTrue);
      expect(find.text('Hesap: Cüzdan'), findsOneWidget);
      // A screen reader hears which field the date chip is.
      expect(find.bySemanticsLabel(RegExp(r'^Tarih\s+Bugün$')),
          findsOneWidget);

      await _type(tester, '85');
      await tester.tap(find.text('Market'));
      await tester.pump();
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      final sent = api.bodiesOf('POST /transactions').single as Map;
      expect(sent['amount_cents'], 8500);
      expect(sent['finance_category_id'], 5);
      expect(sent['account_id'], 1);
    });

    testWidgets('360×780: each of the six most used categories is in sight, '
        'a tap away — none behind a sideways swipe', (tester) async {
      _phone(tester);
      final api = _withSixCategories();
      await pumpFinance(tester, api, _formLauncher());
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      final body = find.descendant(
        of: find.byType(TransactionFormScreen),
        matching: find.byWidgetPredicate((w) =>
            w is Scrollable && w.axisDirection == AxisDirection.down),
      );
      expect(
        tester.state<ScrollableState>(body.first).position.maxScrollExtent,
        0,
        reason: 'the form fits',
      );
      for (final name in [..._sixCategories, 'Tümü…']) {
        expect(_onScreen(tester, find.text(name)), isTrue,
            reason: '$name ${tester.getRect(find.text(name))}');
      }
      expect(
        find.descendant(
          of: find.byType(TransactionFormScreen),
          matching: find.byWidgetPredicate((w) =>
              w is Scrollable && w.axisDirection == AxisDirection.right),
        ),
        findsOneWidget,
        reason: 'only the meta chips may run sideways',
      );

      // The sixth: digits, one tap, Kaydet.
      await _type(tester, '42');
      await tester.tap(find.text('Sağlık'));
      await tester.pump();
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      final sent = api.bodiesOf('POST /transactions').single as Map;
      expect(sent['finance_category_id'], 10);
      expect(sent['amount_cents'], 4200);
    });

    testWidgets('a key press rebuilds the amount, nothing else',
        (tester) async {
      _phone(tester);
      await pumpFinance(tester, FakeApi(), _formLauncher());
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      // The first digit makes the form one that asks before closing.
      await _type(tester, '1');
      final keypad = tester.widget<AmountKeypad>(find.byType(AmountKeypad));
      await _type(tester, '234');
      await settleFrames(tester);
      expect(find.text('₺1.234'), findsOneWidget);
      expect(
        identical(tester.widget<AmountKeypad>(find.byType(AmountKeypad)),
            keypad),
        isTrue,
        reason: 'the form around the amount was not rebuilt',
      );
    });

    testWidgets('"Açıklama" swaps the keypad for the text; a tap on the '
        'amount brings it back', (tester) async {
      _phone(tester);
      final api = FakeApi();
      await pumpFinance(tester, api, _formLauncher());
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await _type(tester, '20');
      await tester.ensureVisible(find.text('Açıklama'));
      await tester.tap(find.text('Açıklama'));
      await settleFrames(tester);
      expect(find.byType(AmountKeypad), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Simit');
      await tester.tap(find.text('Daha fazla'));
      await settleFrames(tester);
      await tester.enterText(find.byType(TextField).last, 'iki tane');

      await tester.tap(find.bySemanticsLabel('Tutar'));
      await settleFrames(tester);
      expect(find.byType(AmountKeypad), findsOneWidget);
      expect(find.text('Simit'), findsOneWidget, reason: 'on its chip');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      final sent = api.bodiesOf('POST /transactions').single as Map;
      expect(sent['description'], 'Simit');
      expect(sent['note'], 'iki tane');
      expect(sent['amount_cents'], 2000);
    });

    testWidgets('a transfer\'s accounts trade places with one tap',
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
                onPressed: () => openTransactionForm(context,
                    initialKind: 'transfer', initialAccountId: 1),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await tester.tap(find.text('Hedef hesap seç'));
      await settleFrames(tester);
      await tester.tap(find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Banka')));
      await settleFrames(tester);
      await _type(tester, '50');
      await settleFrames(tester);
      expect(find.textContaining('sonra:'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Hesapları değiştir'));
      await settleFrames(tester);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      final sent = api.bodiesOf('POST /transactions').single as Map;
      expect(sent['account_id'], 2);
      expect(sent['related_account_id'], 1);
    });
  });

  group('a transfer', () {
    testWidgets('no account list: the transfer says so too, and a save with '
        'no source names it', (tester) async {
      tallPhone(tester);
      final api = FakeApi()..failNetwork('GET /accounts');
      await pumpFinance(tester, api, _transferLauncher());
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(find.text('Hesaplar yüklenemedi. Tekrar denemek için dokun.'),
          findsOneWidget);
    });

    testWidgets('saving with no source says why under the cards, and a '
        'screen reader hears it on the source', (tester) async {
      tallPhone(tester);
      final api = FakeApi()..on('GET /accounts', {'accounts': <Object>[]});
      await pumpFinance(tester, api, _transferLauncher());
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await _type(tester, '50');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /transactions'), isEmpty);
      final shown = find.byWidgetPredicate((w) =>
          w is FormInlineError &&
          (w.text ?? '').contains('Önce bir hesap oluştur'));
      expect(shown, findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Kaynak')),
        findsOneWidget,
      );
      final node = tester.getSemantics(find.bySemanticsLabel(RegExp('Kaynak')));
      expect(node.hint, contains('Önce bir hesap oluştur'));
    });

    testWidgets('what the server says of the source account shows under the '
        'cards', (tester) async {
      tallPhone(tester);
      final api = _twoAccounts()
        ..on(
          'POST /transactions',
          {
            'errors': {
              'account_id': ['Hesap arşivlenmiş'],
            },
          },
          status: 422,
        );
      await pumpFinance(tester, api, _transferLauncher());
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await tester.tap(find.text('Hedef hesap seç'));
      await settleFrames(tester);
      await tester.tap(find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Banka')));
      await settleFrames(tester);
      await _type(tester, '50');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /transactions'), hasLength(1));
      expect(
        find.byWidgetPredicate(
            (w) => w is FormInlineError && (w.text ?? '').isNotEmpty),
        findsOneWidget,
      );
    });

    testWidgets('an edited transfer turned round: the balances after it '
        'take out what it did, then put in what it will do', (tester) async {
      tallPhone(tester);
      // Cüzdan → Banka ₺100 is already in the balances: ₺1.000 and ₺500.
      final api = _twoAccounts(wallet: 100000, bank: 50000);
      final existing = Transaction.fromJson({
        ...transactionJson(id: 77),
        'kind': 'transfer',
        'amount_cents': 10000,
        'account': accountJson(balance: 100000),
        'related_account': accountJson(
            id: 2, name: 'Banka', type: 'bank', balance: 50000),
        'category': null,
      });
      await pumpFinance(tester, api, _transferLauncher(existing: existing));
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(find.text('sonra: ₺1.000'), findsOneWidget, reason: 'as it is');
      expect(find.text('sonra: ₺500'), findsOneWidget);
      await tester.tap(find.byTooltip('Hesapları değiştir'));
      await settleFrames(tester);
      // Banka → Cüzdan ₺100.
      expect(find.text('sonra: ₺300'), findsOneWidget);
      expect(find.text('sonra: ₺1.200'), findsOneWidget);
    });

    testWidgets('200% text: no money on the cards ends in "…"',
        (tester) async {
      _phone(tester);
      _textScale(tester, 2.0);
      final api = _twoAccounts(wallet: 12890000, bank: 275000);
      await pumpFinance(tester, api, _transferLauncher());
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await tester.ensureVisible(find.text('Hedef hesap seç'));
      await tester.tap(find.text('Hedef hesap seç'));
      await settleFrames(tester);
      await tester.tap(find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Banka')));
      await settleFrames(tester);
      await _type(tester, '1250');
      await settleFrames(tester);
      final money = find.descendant(
        of: find.byType(TransactionFormScreen),
        matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').contains('₺')),
      );
      expect(find.textContaining('sonra:'), findsNWidgets(2));
      for (final element in money.evaluate()) {
        final paragraph = element.renderObject;
        if (paragraph is! RenderParagraph) continue;
        expect(paragraph.didExceedMaxLines, isFalse,
            reason: (element.widget as Text).data);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('the category chips', () {
    TxCategory cat(int id, {String kind = 'expense', int position = 0}) =>
        TxCategory(
          id: id,
          name: 'c$id',
          kind: kind,
          color: '#6B8E5A',
          position: position,
        );
    Transaction tx(int category, {String kind = 'expense'}) =>
        Transaction.fromJson({
          ...transactionJson(),
          'kind': kind,
          'category': {
            'id': category,
            'name': 'c$category',
            'kind': kind,
            'color': '#6B8E5A',
            'parent_id': null,
            'position': 0,
          },
        });

    test('the kind\'s most used lately first (the latest use breaking a '
        'tie), then the rest in list order, six at most', () {
      final categories = [
        for (var i = 1; i <= 8; i++) cat(i, position: i),
        cat(20, kind: 'income'),
      ];
      final recent = [tx(3), tx(5), tx(3), tx(20, kind: 'income'), tx(5),
          tx(7)];
      final ids = [
        for (final c in frequentCategories(
            recent: recent, categories: categories, kind: 'expense'))
          c.id,
      ];
      expect(ids, [3, 5, 7, 1, 2, 4]);
    });

    test('a category deleted since is skipped; with no history, list order',
        () {
      final categories = [cat(2, position: 2), cat(1, position: 1)];
      expect(
        [
          for (final c in frequentCategories(
              recent: [tx(9)], categories: categories, kind: 'expense'))
            c.id,
        ],
        [1, 2],
      );
    });
  });
}
