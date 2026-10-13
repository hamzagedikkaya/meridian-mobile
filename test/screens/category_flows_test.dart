/// Finance categories from the phone (contract G2.4): the Kategoriler page
/// with both types and their subcategories, create and edit in one sheet,
/// a starter set for a new user, and deletes that say what they touch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/ui/screens/finance/categories_screen.dart';

import '../support/fake_api.dart';
import '../support/finance_harness.dart';

Map<String, dynamic> _categories() => {
      'categories': [
        categoryJson(),
        categoryJson(id: 6, name: 'Atıştırmalık', parentId: 5, color: '#C9A227'),
        categoryJson(id: 7, name: 'Maaş', kind: 'income', color: '#6B8E5A'),
      ],
    };

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('both types, each top-level category with its subcategories',
      (tester) async {
    tallPhone(tester);
    final api = FakeApi()..on('GET /finance_categories', _categories());
    await pumpFinance(tester, api, const CategoriesScreen());
    // Expenses first, then income, each under its heading.
    expect(find.text('Gider'), findsOneWidget);
    expect(find.text('Gelir'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Atıştırmalık'), findsOneWidget);
    expect(find.text('1 alt kategori'), findsOneWidget);
    expect(find.text('Maaş'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Gider')).dy,
        lessThan(tester.getTopLeft(find.text('Market')).dy));
    expect(tester.getTopLeft(find.text('Atıştırmalık')).dy,
        lessThan(tester.getTopLeft(find.text('Gelir')).dy));
    expect(tester.getTopLeft(find.text('Gelir')).dy,
        lessThan(tester.getTopLeft(find.text('Maaş')).dy));
    // A subcategory sits 56 dp in from the card, past its parent's circle.
    expect(
      tester.getTopLeft(find.text('Atıştırmalık')).dx -
          tester.getTopLeft(find.text('Market')).dx,
      36,
    );
  });

  testWidgets('a top-level expense category says what went to it this month '
      '— from the dashboard — and how many subcategories it has; an income '
      'one only the subcategories', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance_categories', _categories())
      ..on('GET /finance/dashboard', {
        'currency': 'TRY',
        'subunit_to_unit': 100,
        'month': {'income_cents': 0, 'expense_cents': 1240000, 'net_cents': -1240000},
        'year': {'income_cents': 0, 'expense_cents': 1240000},
        'six_month_series': {'labels': [], 'income_cents': [], 'expense_cents': []},
        'pie': [
          {'id': 5, 'name': 'Market', 'color': '#D4915A', 'amount_cents': 1240000, 'breakdown': const []},
        ],
        'budgets': [],
        'upcoming_subscriptions': [],
        'recent_transactions': [],
      });
    await pumpFinance(tester, api, const CategoriesScreen());
    expect(find.text('Bu ay ₺12.400 · 1 alt kategori'), findsOneWidget);
    expect(find.textContaining('Bu ay', findRichText: true), findsOneWidget,
        reason: 'not on the income category');
  });

  testWidgets('a new subcategory: name, parent, colour', (tester) async {
    tallPhone(tester);
    final api = FakeApi()..on('GET /finance_categories', _categories());
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.byType(FloatingActionButton));
    await settleFrames(tester);
    expect(_inSheet(find.text('Yeni kategori')), findsOneWidget);
    await tester.enterText(_inSheet(find.byType(TextField)), 'Ekmek');
    // Only a top-level category of the same type can be a parent.
    expect(_inSheet(find.text('Atıştırmalık')), findsNothing);
    expect(_inSheet(find.text('Maaş')), findsNothing);
    await tester.tap(_inSheet(find.text('Market')));
    await tester.pump();
    await tester.tap(_inSheet(find.text('Ekle')));
    await settleFrames(tester);
    expect(api.bodiesOf('POST /finance_categories').single, {
      'name': 'Ekmek',
      'kind': 'expense',
      'parent_id': 5,
      // The colours rotate: the fourth category gets the fourth swatch.
      'color': '#B85450',
    });
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('“Yeni” eklendi'), findsOneWidget);
  });

  testWidgets('a name already taken is said under the field, in the app\'s '
      'words', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('POST /finance_categories', {
        'errors': {'name': ['Name has already been taken']},
        'code': 'validation_failed',
        'details': {
          'name': [
            {'error': 'taken', 'value': 'market'},
          ],
        },
      }, status: 422);
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.byType(FloatingActionButton));
    await settleFrames(tester);
    await tester.enterText(_inSheet(find.byType(TextField)), 'market');
    await tester.tap(_inSheet(find.text('Ekle')));
    await settleFrames(tester);
    expect(_inSheet(find.text('Bu zaten kullanılıyor')), findsOneWidget);
    expect(find.text('Name has already been taken'), findsNothing);
  });

  testWidgets('an edit sends only what changed; the type of a category in '
      'use shows, locked, and says why', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance_categories', _categories())
      ..on('GET /finance_categories/5', {
        'category': categoryUsageJson(transactions: 3, children: 1),
      });
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    expect(_inSheet(find.text('Kategoriyi düzenle')), findsOneWidget);
    expect(_inSheet(find.text('Tür')), findsOneWidget);
    expect(
      _inSheet(find.text('Kullanımda olduğu için türü değiştirilemez.')),
      findsOneWidget,
    );
    // A locked type does not change on a tap.
    await tester.tap(_inSheet(find.text('Gelir')));
    await tester.pump();
    // A category with subcategories cannot get a parent.
    expect(
      _inSheet(find.text('Alt kategorileri olduğu için başka bir kategorinin '
          'altına alınamaz.')),
      findsOneWidget,
    );
    await tester.enterText(_inSheet(find.byType(TextField)), 'Gıda');
    await tester.tap(_inSheet(find.text('Kaydet')));
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /finance_categories/5').single, {'name': 'Gıda'});
  });

  testWidgets('a type change refused because the category got used '
      'meanwhile: the type goes back and locks, it says why, and the next '
      'save sends the rest without it', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance_categories', _categories())
      ..on('PATCH /finance_categories/5', {
        'errors': {
          'kind': ['A category in use cannot change its type.'],
        },
        'code': 'kind_locked',
      }, status: 422);
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    // Nothing is filed under it yet: the type can change.
    expect(
      _inSheet(find.text('Kullanımda olduğu için türü değiştirilemez.')),
      findsNothing,
    );
    await tester.tap(_inSheet(find.text('Gelir')));
    await tester.pump();
    // Something was filed under it on the web meanwhile.
    api.on('GET /finance_categories/5', {
      'category': categoryUsageJson(transactions: 1),
    });
    await tester.tap(_inSheet(find.text('Kaydet')));
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /finance_categories/5').single,
        {'kind': 'income'});
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'kept open');
    expect(
      _inSheet(find.text('Kullanımda olan bir kategorinin türü '
          'değiştirilemez')),
      findsOneWidget,
    );
    expect(find.text('A category in use cannot change its type.'),
        findsNothing);

    // The type is its own again, and stays: a tap does not change it.
    await tester.tap(_inSheet(find.text('Gelir')));
    await tester.pump();
    api.on('PATCH /finance_categories/5', {
      'category': categoryJson(name: 'Gıda'),
    });
    await tester.enterText(_inSheet(find.byType(TextField)), 'Gıda');
    await tester.tap(_inSheet(find.text('Kaydet')));
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /finance_categories/5').last, {'name': 'Gıda'});
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Kategori güncellendi'), findsOneWidget);
  });

  testWidgets('a save that changes nothing closes the sheet quietly',
      (tester) async {
    tallPhone(tester);
    final api = FakeApi();
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    await tester.tap(_inSheet(find.text('Kaydet')));
    await settleFrames(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(api.bodiesOf('PATCH /finance_categories/5'), isEmpty);
    expect(find.text('Kategori güncellendi'), findsNothing);
  });

  testWidgets('a category nothing is filed under is deleted with "Geri al"',
      (tester) async {
    tallPhone(tester);
    final api = FakeApi();
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    await tester.tap(_inSheet(find.text('Sil')));
    await settleFrames(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('“Market” silindi'), findsOneWidget);
    expect(find.text('Market'), findsNothing, reason: 'off the list');
    expect(api.requests, isNot(contains('DELETE /finance_categories/5')));
    await letUndoRunOut(tester);
    expect(api.requests, contains('DELETE /finance_categories/5'));
  });

  testWidgets('when what a delete would touch cannot be read, the sheet says '
      'so — where it can be seen, not in a snackbar under it — and nothing '
      'is deleted', (tester) async {
    tallPhone(tester);
    final api = FakeApi()..failNetwork('GET /finance_categories/5');
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    await tester.tap(_inSheet(find.text('Sil')));
    await settleFrames(tester);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'still open');
    expect(_inSheet(find.text('Kategori yüklenemedi')).hitTestable(),
        findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await letUndoRunOut(tester);
    expect(api.requests, isNot(contains('DELETE /finance_categories/5')));

    // Readable again: the next "Sil" asks again, and goes as usual.
    api.on('GET /finance_categories/5', {'category': categoryUsageJson()});
    await tester.tap(_inSheet(find.text('Sil')));
    await settleFrames(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('“Market” silindi'), findsOneWidget);
  });

  testWidgets('a category whose delete waits out its undo is no parent for a '
      'new one: the server would delete the new one with it',
      (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance_categories', {
        'categories': [
          categoryJson(),
          categoryJson(id: 6, name: 'Ulaşım', color: '#6B8FA0'),
        ],
      });
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    await tester.tap(_inSheet(find.text('Sil')));
    await settleFrames(tester);
    expect(find.text('“Market” silindi'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await settleFrames(tester);
    expect(_inSheet(find.text('Yeni kategori')), findsOneWidget);
    expect(_inSheet(find.text('Ulaşım')), findsOneWidget);
    expect(_inSheet(find.text('Market')), findsNothing);
    expect(api.requests, isNot(contains('DELETE /finance_categories/5')));
  });

  testWidgets('a category in use: the dialog says what its delete touches, '
      'then it goes at once', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance_categories/5', {
        'category': categoryUsageJson(
            children: 3, transactions: 47, subscriptions: 2, budgets: 1),
      });
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    await tester.tap(_inSheet(find.text('Sil')));
    await settleFrames(tester);
    expect(find.text('“Market” silinsin mi?'), findsOneWidget);
    expect(
      find.text('47 işlem kategorisiz kalacak. 2 abonelik kategorisiz '
          'kalacak. 3 alt kategori de silinecek. 1 bütçe silinecek.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await settleFrames(tester);
    expect(api.requests, contains('DELETE /finance_categories/5'));
    expect(find.text('“Market” silindi'), findsOneWidget);
  });

  testWidgets('a category in use can hand its transactions to another of its '
      'type: "Diğer" is offered first, "Sil ve taşı" moves them and then '
      'deletes it', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance_categories', {
        'categories': [
          categoryJson(),
          categoryJson(id: 6, name: 'Atıştırmalık', parentId: 5),
          categoryJson(id: 8, name: 'Diğer', color: '#A09B8E'),
          categoryJson(id: 7, name: 'Maaş', kind: 'income'),
        ],
      })
      ..on('GET /finance_categories/5', {
        'category': categoryUsageJson(children: 1, transactions: 1),
      });
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    await tester.tap(_inSheet(find.text('Sil')));
    await settleFrames(tester);
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('İşlemler şuraya taşınsın')),
        findsOneWidget);
    expect(
      find.text('1 işlem “Diğer” kategorisine taşınacak. '
          '1 alt kategori de silinecek.'),
      findsOneWidget,
    );
    // Neither itself, its subcategory nor an income category is offered.
    await tester.tap(find.descendant(of: dialog, matching: find.text('Diğer')));
    await settleFrames(tester);
    expect(find.text('Kategorisiz'), findsWidgets);
    expect(find.text('Atıştırmalık').hitTestable(), findsNothing);
    expect(find.text('Maaş').hitTestable(), findsNothing);
    await tester.tap(find.text('Diğer').last);
    await settleFrames(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Sil ve taşı'));
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /transactions/316').single,
        {'finance_category_id': 8});
    final move = api.requests.indexOf('PATCH /transactions/316');
    final delete = api.requests.indexOf('DELETE /finance_categories/5');
    expect(delete, greaterThan(move), reason: 'moved first');
    expect(find.text('“Market” silindi · 1 işlem taşındı'), findsOneWidget);
  });

  testWidgets('"Sil ve taşı" says it is moving them; one that fails stops '
      'it, the category comes back, and the snackbar says how many moved',
      (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance_categories', {
        'categories': [
          categoryJson(),
          categoryJson(id: 8, name: 'Diğer', color: '#A09B8E'),
        ],
      })
      ..on('GET /finance_categories/5', {
        'category': categoryUsageJson(transactions: 3),
      })
      ..on('GET /transactions', {
        'transactions': [
          transactionJson(),
          transactionJson(id: 317),
          transactionJson(id: 318),
        ],
        'meta': const {
          'total_count': 3,
          'page': 1,
          'page_limit': 50,
          'filtered_income_cents': 0,
          'filtered_expense_cents': 41622,
        },
      })
      ..on('PATCH /transactions/317', transactionJson(id: 317))
      ..fail('PATCH /transactions/318', 500)
      ..hold('PATCH /transactions/316');
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    await tester.tap(_inSheet(find.text('Sil')));
    await settleFrames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sil ve taşı'));
    await settleFrames(tester);
    // On its way: said, and the category is off the list.
    expect(find.text('3 işlem taşınıyor…'), findsOneWidget);
    expect(find.text('Market'), findsNothing);

    api.release('PATCH /transactions/316');
    await settleFrames(tester);
    expect(api.requests, isNot(contains('DELETE /finance_categories/5')));
    expect(find.text('Kategori silinemedi · 3 işlemin 2 tanesi taşındı'),
        findsOneWidget);
    expect(find.text('3 işlem taşınıyor…'), findsNothing);
    expect(find.text('Market'), findsOneWidget, reason: 'back');
  });

  testWidgets('"Kategorisiz" in the dialog leaves them uncategorized: no move, '
      'just the delete', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance_categories', {
        'categories': [
          categoryJson(),
          categoryJson(id: 8, name: 'Diğer', color: '#A09B8E'),
        ],
      })
      ..on('GET /finance_categories/5', {
        'category': categoryUsageJson(transactions: 1),
      });
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Market'));
    await settleFrames(tester);
    await tester.tap(_inSheet(find.text('Sil')));
    await settleFrames(tester);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Diğer')));
    await settleFrames(tester);
    await tester.tap(find.text('Kategorisiz').last);
    await settleFrames(tester);
    expect(find.text('1 işlem kategorisiz kalacak.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await settleFrames(tester);
    expect(api.requests, isNot(contains('PATCH /transactions/316')));
    expect(api.requests, contains('DELETE /finance_categories/5'));
  });

  testWidgets('a new user starts from a set: "Hazır kategorileri ekle" adds '
      'both types in the app\'s language', (tester) async {
    tallPhone(tester);
    final api = FakeApi()..on('GET /finance_categories', {'categories': const []});
    await pumpFinance(tester, api, const CategoriesScreen());
    expect(find.text('Henüz kategori yok'), findsOneWidget);
    // The empty state carries the create action: the FAB steps aside.
    expect(
      tester
          .widget<IgnorePointer>(find
              .ancestor(
                  of: find.byType(FloatingActionButton),
                  matching: find.byType(IgnorePointer))
              .first)
          .ignoring,
      isTrue,
    );
    await tester.tap(find.text('Hazır kategorileri ekle'));
    await settleFrames(tester);
    final sent = [
      for (final body in api.bodiesOf('POST /finance_categories'))
        '${(body as Map)['kind']}:${body['name']}',
    ];
    expect(sent, [
      'expense:Market',
      'expense:Ulaşım',
      'expense:Faturalar',
      'expense:Kira',
      'expense:Yemek',
      'expense:Sağlık',
      'expense:Eğlence',
      'expense:Diğer',
      'income:Maaş',
      'income:Diğer gelir',
    ]);
    expect(find.text('Hazır kategoriler eklendi'), findsOneWidget);
  });

  testWidgets('a starter set that half failed offers the retry it asks '
      'for', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /finance_categories', {'categories': const []})
      ..blip('POST /finance_categories');
    await pumpFinance(tester, api, const CategoriesScreen());
    await tester.tap(find.text('Hazır kategorileri ekle'));
    await settleFrames(tester);
    expect(api.bodiesOf('POST /finance_categories'), hasLength(10));
    expect(find.text('Kategorilerin bir kısmı eklenemedi, tekrar dene'),
        findsOneWidget);

    // The set runs again (the names already there are refused as taken,
    // and skipped); this time every one goes through.
    await tester.tap(find.text('Tekrar dene'));
    await settleFrames(tester);
    final retried = api.bodiesOf('POST /finance_categories').skip(10);
    expect([for (final body in retried) (body as Map)['name']],
        contains('Market'));
    expect(find.text('Hazır kategoriler eklendi'), findsOneWidget);
  });

  group('the new-category sheet with the keyboard up', () {
    // 360×780 dp, a 24 dp status bar, a 300 dp keyboard (its top at 480).
    const keyboardTop = 780.0 - 300;
    void phoneWithKeyboard(WidgetTester tester, double textScale) {
      tester.view.physicalSize = const Size(360, 780) * 3;
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = const FakeViewPadding(top: 24 * 3);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    /// Eight expense categories: the colour row is far down the form.
    Map<String, dynamic> manyRoots() => {
          'categories': [
            for (var i = 0; i < 8; i++)
              categoryJson(id: 20 + i, name: 'Kök $i', position: i),
          ],
        };

    for (final scale in [1.0, 2.0]) {
      testWidgets('at ${scale}x: "Ekle" stays above the keyboard, and ✓ puts '
          'the keyboard away instead of saving', (tester) async {
        phoneWithKeyboard(tester, scale);
        final api = FakeApi()..on('GET /finance_categories', manyRoots());
        await pumpFinance(tester, api, const CategoriesScreen());
        await tester.tap(find.byType(FloatingActionButton));
        await settleFrames(tester);
        expect(tester.takeException(), isNull, reason: 'nothing overflows');
        final add = _inSheet(find.text('Ekle'));
        expect(add.hitTestable(), findsOneWidget);
        expect(tester.getRect(find.byType(FilledButton).last).bottom,
            lessThanOrEqualTo(keyboardTop));

        await tester.enterText(_inSheet(find.byType(TextField)), 'Ekmek');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settleFrames(tester);
        expect(api.bodiesOf('POST /finance_categories'), isEmpty,
            reason: 'the parent and colour are still to choose');
        expect(find.byType(BottomSheet), findsOneWidget);
      });
    }
  });

  testWidgets('a create in flight is sent once: ✓ after "Ekle" neither '
      'sends it again nor closes the page under the sheet', (tester) async {
    tallPhone(tester);
    final api = FakeApi()..hold('POST /finance_categories');
    await pumpFinance(
      tester,
      api,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/finance/categories'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settleFrames(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await settleFrames(tester);
    await tester.enterText(_inSheet(find.byType(TextField)), 'Ekmek');
    await tester.tap(_inSheet(find.text('Ekle')));
    await settleFrames(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settleFrames(tester);
    expect(api.bodiesOf('POST /finance_categories'), hasLength(1));

    api.release('POST /finance_categories');
    await settleFrames(tester);
    expect(api.bodiesOf('POST /finance_categories'), hasLength(1));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(CategoriesScreen), findsOneWidget,
        reason: 'Kategoriler is still open');
  });
}
