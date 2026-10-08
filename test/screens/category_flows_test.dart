/// Finance categories from the phone (contract G2.4): the Kategoriler page
/// with both types and their subcategories, create and edit in one sheet,
/// a starter set for a new user, and deletes that say what they touch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Atıştırmalık'), findsOneWidget);
    expect(find.text('1 alt kategori'), findsOneWidget);
    expect(find.text('Maaş'), findsNothing);

    await tester.tap(find.text('Gelir'));
    await settleFrames(tester);
    expect(find.text('Maaş'), findsOneWidget);
    expect(find.text('Market'), findsNothing);
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
    expect(find.text('“Yeni” eklendi ✓'), findsOneWidget);
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
      'use is not offered', (tester) async {
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
    expect(_inSheet(find.text('Tür')), findsNothing, reason: 'in use');
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

  testWidgets('a new user starts from a set: "Hazır kategorileri ekle" adds '
      'both types in the app\'s language', (tester) async {
    tallPhone(tester);
    final api = FakeApi()..on('GET /finance_categories', {'categories': const []});
    await pumpFinance(tester, api, const CategoriesScreen());
    expect(find.text('Henüz gider kategorisi yok'), findsOneWidget);
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
    expect(find.text('Hazır kategoriler eklendi ✓'), findsOneWidget);
  });
}
