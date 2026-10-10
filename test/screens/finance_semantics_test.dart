/// The finance controls answer a screen reader (design-research §6.2): one
/// stop per key, pill, chip, swatch, amount field and account tile — and that
/// stop operates the control. Each leaves its own detector out of the
/// semantics tree, so a double-tap (TalkBack's ACTION_CLICK, which is
/// `SemanticsAction.tap`; Switch Access and Voice Access the same) does
/// something only because the node answers it itself. Their targets are
/// 48 dp, at the size their pills are drawn.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/ui/screens/finance/account_form.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/subscription_form.dart';
import 'package:meridian_mobile/ui/screens/finance/transaction_form_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/transactions_screen.dart';
import 'package:meridian_mobile/ui/widgets/pressable_scale.dart';

import '../support/fake_api.dart';
import '../support/finance_harness.dart';

/// The one semantics node labelled [label].
SemanticsData _node(String label) =>
    find.semantics.byLabel(label).evaluate().single.getSemanticsData();

bool _canTap(String label) => _node(label).hasAction(SemanticsAction.tap);

bool _selected(String label) =>
    _node(label).flagsCollection.isSelected == Tristate.isTrue;

/// Double-taps [label] the way a screen reader does, and lets it land.
Future<void> _doubleTap(WidgetTester tester, String label) async {
  tester.semantics.tap(find.semantics.byLabel(label));
  await settleFrames(tester);
}

/// A plain page with a button that runs [open] — a form or sheet over it.
Widget _launcher(void Function(BuildContext context) open) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  void Function(BuildContext context) open,
) async {
  await pumpFinance(tester, api, _launcher(open));
  await tester.tap(find.text('open'));
  await settleFrames(tester);
}

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('the keypad: a double-tap on a key types it, on ⌫ drops the '
      'last digit, and a long-press on ⌫ clears the amount', (tester) async {
    tallPhone(tester);
    final handle = tester.ensureSemantics();
    final api = FakeApi();
    await _open(tester, api, (context) => openTransactionForm(context));
    for (final key in [
      for (var digit = 0; digit <= 9; digit++) '$digit',
      'Ondalık virgül',
      'Son rakamı sil',
    ]) {
      expect(_canTap(key), isTrue, reason: key);
    }
    expect(_node('Son rakamı sil').hasAction(SemanticsAction.longPress),
        isTrue);
    expect(_node('Son rakamı sil').hint, 'Tümünü silmek için basılı tut');

    for (final key in ['1', '2', '5']) {
      tester.semantics.tap(find.semantics.byLabel(key));
      await tester.pump();
    }
    expect(find.text('₺125'), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('Son rakamı sil'));
    await tester.pump();
    expect(find.text('₺12'), findsOneWidget);
    tester.semantics.longPress(find.semantics.byLabel('Son rakamı sil'));
    await tester.pump();
    expect(find.text('₺0'), findsOneWidget);

    for (final key in ['4', 'Ondalık virgül', '5']) {
      tester.semantics.tap(find.semantics.byLabel(key));
      await tester.pump();
    }
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    expect(
      (api.bodiesOf('POST /transactions').single as Map)['amount_cents'],
      450,
    );
    handle.dispose();
  });

  testWidgets('the kind pill: each kind is one stop, and a double-tap picks '
      'it', (tester) async {
    tallPhone(tester);
    final handle = tester.ensureSemantics();
    final api = FakeApi();
    await _open(tester, api, (context) => openTransactionForm(context));
    expect(_selected('Gider'), isTrue);
    expect(_canTap('Gelir'), isTrue);
    expect(_canTap('Transfer'), isTrue);

    await _doubleTap(tester, 'Gelir');
    expect(_selected('Gelir'), isTrue);
    expect(_selected('Gider'), isFalse);
    expect(_canTap('Gider'), isTrue);

    tester.semantics.tap(find.semantics.byLabel('8'));
    await tester.pump();
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    final body = api.bodiesOf('POST /transactions').single as Map;
    expect(body['kind'], 'income');
    expect(body['amount_cents'], 800);
    handle.dispose();
  });

  testWidgets('İşlemler\'s filter chips: each is one stop saying whether it '
      'is on, and a double-tap filters', (tester) async {
    tallPhone(tester);
    final handle = tester.ensureSemantics();
    final kinds = <Object?>[];
    final api = FakeApi()
      ..onRequest('GET /transactions', (request) {
        kinds.add(request.queryParameters['kind']);
        return {
          'transactions': [transactionJson()],
          'meta': const {'total_count': 1, 'page': 1, 'page_limit': 50},
        };
      });
    await pumpFinance(tester, api, const TransactionsScreen());
    for (final chip in ['Tümü', 'Gelir', 'Gider', 'Transfer', 'Hesap']) {
      expect(_canTap(chip), isTrue, reason: chip);
    }
    expect(_selected('Tümü'), isTrue);

    await _doubleTap(tester, 'Gelir');
    expect(kinds.last, 'income');
    expect(_selected('Gelir'), isTrue);
    expect(_selected('Tümü'), isFalse);

    // A picker chip opens its picker.
    await _doubleTap(tester, 'Hesap');
    expect(find.byType(BottomSheet), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the account form\'s pills and swatches: one stop each, a '
      'double-tap picks it; the chosen one has nothing to do',
      (tester) async {
    tallPhone(tester);
    final handle = tester.ensureSemantics();
    final api = FakeApi();
    await _open(tester, api, (context) => openAccountForm(context));
    expect(_selected('Nakit'), isTrue);
    expect(_canTap('Nakit'), isFalse);
    expect(_canTap('Banka'), isTrue);
    expect(_canTap('Toz mavisi'), isTrue);

    await _doubleTap(tester, 'Banka');
    await _doubleTap(tester, 'USD · ABD doları');
    await _doubleTap(tester, 'Toz mavisi');
    expect(_selected('Banka'), isTrue);
    expect(_selected('USD · ABD doları'), isTrue);
    expect(_selected('Toz mavisi'), isTrue);

    await tester.tap(find.text('Hesabı oluştur'));
    await settleFrames(tester);
    final body = api.bodiesOf('POST /accounts').single as Map;
    expect(body['account_type'], 'bank');
    expect(body['currency'], 'USD');
    expect(body['color'], '#6B8FA0');
    handle.dispose();
  });

  testWidgets('a currency that is locked shows, but offers no action',
      (tester) async {
    tallPhone(tester);
    final handle = tester.ensureSemantics();
    final api = FakeApi()
      ..on('GET /accounts/1', {'account': accountDetailJson(transactions: 3)});
    await _open(
      tester,
      api,
      (context) => openAccountForm(
        context,
        existing: Account.fromJson(accountJson()),
      ),
    );
    expect(_selected('TRY · Türk lirası'), isTrue);
    expect(_canTap('USD · ABD doları'), isFalse);
    expect(
      _node('USD · ABD doları').flagsCollection.isEnabled,
      Tristate.isFalse,
    );
    handle.dispose();
  });

  testWidgets('an amount field is one stop: a double-tap opens the keypad; '
      'its hint is read, and an error is said the moment it appears',
      (tester) async {
    tallPhone(tester);
    final handle = tester.ensureSemantics();
    final api = FakeApi();
    await _open(tester, api, (context) => openSubscriptionForm(context));
    expect(_canTap('Tutar, ₺0'), isTrue);

    await tester.enterText(find.byType(TextField).first, 'Spotify');
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    final error = _node('Sıfırdan büyük bir tutar gir');
    expect(error.flagsCollection.isLiveRegion, isTrue);

    await _doubleTap(tester, 'Tutar, ₺0');
    expect(find.text('Tamam'), findsOneWidget, reason: 'the keypad sheet');
    for (final key in ['5', '0']) {
      tester.semantics.tap(find.semantics.byLabel(key));
      await tester.pump();
    }
    await _doubleTap(tester, 'Tamam');
    expect(_canTap('Tutar, ₺50,00'), isTrue);
    expect(find.semantics.byLabel('Sıfırdan büyük bir tutar gir'),
        findsNothing);

    // A frequency pill, the same way.
    await _doubleTap(tester, 'Yıllık');
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    final body = api.bodiesOf('POST /subscriptions').single as Map;
    expect(body['amount_cents'], 5000);
    expect(body['frequency'], 'yearly');
    handle.dispose();
  });

  testWidgets('the opening balance\'s hint is read with the field',
      (tester) async {
    tallPhone(tester);
    final handle = tester.ensureSemantics();
    await _open(tester, FakeApi(), (context) => openAccountForm(context));
    expect(_canTap('Açılış bakiyesi, ₺0'), isTrue);
    expect(
      find.semantics.byLabel(
          'Hesapta bugün duran tutar. Kredi kartı borcunu “Borç” ile gir.'),
      findsOne,
    );
    handle.dispose();
  });

  testWidgets('the account tiles: one stop each that names the account, '
      'its type and its balance, and opens it; "+ Hesap" adds one',
      (tester) async {
    tallPhone(tester);
    final handle = tester.ensureSemantics();
    final api = FakeApi()
      ..on('GET /accounts', {
        'accounts': [
          accountJson(balance: 325000),
          accountJson(id: 2, name: 'Banka', type: 'bank'),
        ],
      });
    await pumpFinance(tester, api, const FinanceScreen());
    const tile = 'Cüzdan, Nakit, ₺3.250';
    expect(_canTap(tile), isTrue);
    expect(_node(tile).hasAction(SemanticsAction.longPress), isTrue,
        reason: 'its actions (edit, archive)');
    final size = tester.getSize(find.bySemanticsLabel(tile));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(_canTap('Yeni hesap'), isTrue);

    await _doubleTap(tester, tile);
    expect(find.text('NAKİT'), findsOneWidget, reason: 'its page');
    handle.dispose();
  });

  group('48 dp targets, at the size their pills are drawn', () {
    testWidgets('İşlemler\'s filter chips', (tester) async {
      tallPhone(tester);
      await pumpFinance(tester, FakeApi(), const TransactionsScreen());
      for (final chip in ['Tümü', 'Gelir', 'Gider', 'Transfer']) {
        final target = find.ancestor(
          of: find.text(chip),
          matching: find.byType(PressableScale),
        );
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48),
            reason: chip);
        final pill = find
            .ancestor(of: find.text(chip), matching: find.byType(Container))
            .first;
        expect(tester.getSize(pill).height, lessThan(48),
            reason: '$chip: the pill keeps its size');
      }
    });

    testWidgets('the kind pill\'s segments', (tester) async {
      tallPhone(tester);
      await _open(tester, FakeApi(), (context) => openTransactionForm(context));
      for (final kind in ['Gider', 'Gelir', 'Transfer']) {
        final target = find.ancestor(
          of: find.text(kind),
          matching: find.byType(GestureDetector),
        );
        expect(tester.getSize(target.first).height, greaterThanOrEqualTo(48),
            reason: kind);
      }
      // A tap at the top edge of a segment's target picks it.
      final gelir = find
          .ancestor(of: find.text('Gelir'), matching: find.byType(GestureDetector))
          .first;
      await tester.tapAt(tester.getRect(gelir).topCenter + const Offset(0, 2));
      await settleFrames(tester);
      final selected = tester.widget<AnimatedContainer>(find
          .ancestor(of: find.text('Gelir'), matching: find.byType(AnimatedContainer))
          .first);
      expect((selected.decoration! as BoxDecoration).color,
          isNot(Colors.transparent));
    });
  });
}
