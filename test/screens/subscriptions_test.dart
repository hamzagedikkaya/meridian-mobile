/// The Abonelikler page by urgency (design-analysis §7.8, WP-10): overdue,
/// this week, this month, later, paused — and what a due row does in
/// place: "Ödendi" (one payment however often it is tapped, D29; "Geri al"
/// deletes it and puts the date back) and "Atla" (the date one period on;
/// "Geri al" writes the old one back).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/subscription.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/ui/screens/finance/subscriptions_screen.dart';

import '../support/fake_api.dart';
import '../support/finance_harness.dart';

/// Sunday 4 October 2026, 09:41.
final _now = DateTime(2026, 10, 4, 9, 41);

FakeApi _api() => FakeApi()
  ..on('GET /subscriptions', subscriptionsJson(
    active: [
      subscriptionJson(next: '2026-10-01'),
      subscriptionJson(id: 9, name: 'Spotify', amount: 5999, next: '2026-10-08'),
      subscriptionJson(id: 10, name: 'Spor salonu', next: '2026-10-25'),
      subscriptionJson(
          id: 11, name: 'Bulut', frequency: 'yearly', next: '2026-12-01'),
    ],
    inactive: [subscriptionJson(id: 8, name: 'Gazete', active: false)],
  ));

Future<void> _pump(WidgetTester tester, FakeApi api) => pumpFinance(
      tester,
      api,
      const SubscriptionsScreen(),
      now: _now,
    );

const _charge = 'POST /subscriptions/6/charge';

/// The inline "Ödendi" of [name]'s row.
Finder _paid(String name) => find.descendant(
      of: find.ancestor(
        of: find.text(name),
        matching: find.byType(SubscriptionRow),
      ),
      matching: find.widgetWithText(OutlinedButton, 'Ödendi'),
    );

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<OutlinedButton>(button).enabled;

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('grouped by how soon each is due, in that order; the overdue '
      'heading is in error', (tester) async {
    tallPhone(tester);
    // Every group on one screen (the list builds lazily).
    tester.view.physicalSize = const Size(1290, 4200);
    await _pump(tester, _api());
    final headings = ['Gecikmiş', 'Bu hafta', 'Bu ay', 'Sonra', 'Duraklatılmış'];
    final rows = ['Netflix', 'Spotify', 'Spor salonu', 'Bulut', 'Gazete'];
    for (var i = 0; i < headings.length; i++) {
      expect(find.text(headings[i]), findsOneWidget, reason: headings[i]);
      final heading = tester.getTopLeft(find.text(headings[i])).dy;
      final row = tester.getTopLeft(find.text(rows[i])).dy;
      expect(heading, lessThan(row), reason: '${rows[i]} under its heading');
      if (i > 0) {
        expect(tester.getTopLeft(find.text(rows[i - 1])).dy, lessThan(heading),
            reason: '${headings[i]} after ${rows[i - 1]}');
      }
    }
    final c = tester.element(find.text('Gecikmiş')).nok;
    expect(tester.widget<Text>(find.text('Gecikmiş')).style!.color, c.error);
    expect(tester.widget<Text>(find.text('Bu hafta')).style!.color,
        isNot(c.error));

    // Overdue and this week: the amount in the meta line, "Ödendi" inline.
    expect(find.text('Gecikmiş · 1 Ekim'), findsOneWidget);
    expect(find.text('₺229,99 / ay'), findsOneWidget);
    expect(find.text('4 gün sonra'), findsOneWidget);
    expect(find.text('₺59,99 / ay'), findsOneWidget);
    expect(_paid('Netflix'), findsOneWidget);
    expect(_paid('Spotify'), findsOneWidget);
    // Later ones keep it at the end, with how often.
    expect(_paid('Spor salonu'), findsNothing);
    expect(find.text('21 gün sonra · Aylık'), findsOneWidget);
    // "Ödendi" is 36 dp to see and 48 dp to hit.
    expect(tester.getSize(_paid('Netflix')).height, 48);
  });

  testWidgets('"Ödendi" is locked from the first tap to the answer: a double '
      'tap records one payment', (tester) async {
    tallPhone(tester);
    final api = _api()..hold(_charge);
    await _pump(tester, api);
    await tester.tap(_paid('Netflix'));
    await tester.pump();
    expect(_enabled(tester, _paid('Netflix')), isFalse);
    await tester.tap(_paid('Netflix'), warnIfMissed: false);
    await tester.pump();
    await settleFrames(tester);
    expect(api.requests.where((r) => r == _charge), hasLength(1));

    api.release(_charge);
    await settleFrames(tester);
    expect(api.requests.where((r) => r == _charge), hasLength(1));
    expect(find.text('Ödeme kaydedildi · ₺229,99'), findsOneWidget);
  });

  testWidgets('"Geri al" after "Ödendi" deletes the payment and puts the due '
      'date back', (tester) async {
    tallPhone(tester);
    final api = _api()..on('DELETE /transactions/401', null, status: 204);
    await _pump(tester, api);
    await tester.tap(_paid('Netflix'));
    await settleFrames(tester);
    expect(find.text('Ödeme kaydedildi · ₺229,99'), findsOneWidget);
    await tester.tap(find.text('Geri al'));
    await settleFrames(tester);
    expect(api.requests, contains('DELETE /transactions/401'));
    expect(api.bodiesOf('PATCH /subscriptions/6').single,
        {'next_charge_on': '2026-10-01'});
  });

  testWidgets('a "Geri al" whose date cannot go back changes nothing and '
      'says so — the payment is not deleted', (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on('DELETE /transactions/401', null, status: 204)
      ..fail('PATCH /subscriptions/6', 500);
    await _pump(tester, api);
    await tester.tap(_paid('Netflix'));
    await settleFrames(tester);
    await tester.tap(find.text('Geri al'));
    await settleFrames(tester);
    expect(tester.takeException(), isNull);
    expect(api.requests, contains('PATCH /subscriptions/6'));
    expect(api.requests, isNot(contains('DELETE /transactions/401')));
    expect(find.text('Ödeme geri alınamadı; kayıtlı duruyor.'), findsOneWidget);
  });

  testWidgets('a "Geri al" whose delete fails after the date went back says '
      'where to delete the payment', (tester) async {
    tallPhone(tester);
    final api = _api()..fail('DELETE /transactions/401', 500);
    await _pump(tester, api);
    await tester.tap(_paid('Netflix'));
    await settleFrames(tester);
    await tester.tap(find.text('Geri al'));
    await settleFrames(tester);
    expect(tester.takeException(), isNull);
    final patch = api.requests.indexOf('PATCH /subscriptions/6');
    final delete = api.requests.indexOf('DELETE /transactions/401');
    expect(patch, greaterThanOrEqualTo(0));
    expect(delete, greaterThan(patch), reason: 'the date goes back first');
    expect(
      find.text('Tarih geri alındı; ödemeyi İşlemler\'den sil.'),
      findsOneWidget,
    );
  });

  testWidgets('a "Geri al" whose date change loses its answer does not say '
      'nothing changed: the date may be back, the payment is not deleted',
      (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on('DELETE /transactions/401', null, status: 204)
      ..timeOut('PATCH /subscriptions/6');
    await _pump(tester, api);
    await tester.tap(_paid('Netflix'));
    await settleFrames(tester);
    await tester.tap(find.text('Geri al'));
    await settleFrames(tester);
    expect(tester.takeException(), isNull);
    expect(api.requests, contains('PATCH /subscriptions/6'));
    expect(api.requests, isNot(contains('DELETE /transactions/401')));
    expect(find.text('Ödeme geri alınamadı; kayıtlı duruyor.'), findsNothing);
    expect(
      find.text('Yanıt gelmedi; tarih geri alınmış olabilir, ödeme kayıtlı.'),
      findsOneWidget,
    );
  });

  testWidgets('a payment whose answer is lost keeps the row\'s "Ödendi" off '
      'until a refetched list lands — a failed refetch keeps it off',
      (tester) async {
    tallPhone(tester);
    final api = _api()..timeOut(_charge);
    await _pump(tester, api);
    api.failNetwork('GET /subscriptions');
    await tester.tap(_paid('Netflix'));
    await settleFrames(tester);
    expect(find.textContaining('kaydedilmiş olabilir'), findsOneWidget);
    expect(_enabled(tester, _paid('Netflix')), isFalse);
    await tester.tap(_paid('Netflix'), warnIfMissed: false);
    await settleFrames(tester);
    expect(api.requests.where((r) => r == _charge), hasLength(1));

    // The list comes back: the payment did not go through.
    api.on('GET /subscriptions', subscriptionsJson(
      active: [
        subscriptionJson(next: '2026-10-01'),
        subscriptionJson(
            id: 9, name: 'Spotify', amount: 5999, next: '2026-10-08'),
        subscriptionJson(id: 10, name: 'Spor salonu', next: '2026-10-25'),
        subscriptionJson(
            id: 11, name: 'Bulut', frequency: 'yearly', next: '2026-12-01'),
      ],
      inactive: [subscriptionJson(id: 8, name: 'Gazete', active: false)],
    ));
    ProviderScope.containerOf(tester.element(find.byType(SubscriptionsScreen)))
        .invalidate(subscriptionsProvider);
    await settleFrames(tester);
    expect(_enabled(tester, _paid('Netflix')), isTrue);
  });

  testWidgets('an "Atla" whose "Geri al" fails says the date could not go '
      'back', (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on('PATCH /subscriptions/9', {
        'subscription': subscriptionJson(
            id: 9, name: 'Spotify', amount: 5999, next: '2026-11-08'),
      });
    await _pump(tester, api);
    await tester.longPress(find.text('Spotify'));
    await settleFrames(tester);
    await tester.tap(find.text('Atla'));
    await settleFrames(tester);
    api.failNetwork('PATCH /subscriptions/9');
    await tester.tap(find.text('Geri al'));
    await settleFrames(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Tarih geri alınamadı'), findsOneWidget);
  });

  testWidgets('"Atla" moves the due date one period on — the row moves at '
      'once — and "Geri al" writes the old date back', (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on('PATCH /subscriptions/9', {
        'subscription': subscriptionJson(
            id: 9, name: 'Spotify', amount: 5999, next: '2026-11-08'),
      })
      ..hold('PATCH /subscriptions/9');
    await _pump(tester, api);
    await tester.tap(find.descendant(
      of: find.ancestor(
          of: find.text('Spotify'), matching: find.byType(SubscriptionRow)),
      matching: find.byTooltip('Diğer seçenekler'),
    ));
    await settleFrames(tester);
    await tester.tap(find.text('Atla').last);
    await tester.pump();
    // Out of "Bu hafta" before the server answers.
    expect(_paid('Spotify'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Spotify')).dy,
      greaterThan(tester.getTopLeft(find.text('Sonra')).dy),
    );
    api.release('PATCH /subscriptions/9');
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /subscriptions/9').single,
        {'next_charge_on': '2026-11-08'});
    expect(find.text('“Spotify” atlandı · sonraki 8 Kasım'), findsOneWidget);
    expect(api.requests, isNot(contains('POST /subscriptions/9/charge')));

    await tester.tap(find.text('Geri al'));
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /subscriptions/9').last,
        {'next_charge_on': '2026-10-08'});
  });

  testWidgets('a skip on its way: the sheet shows the date it moves to, and '
      '"Ödendi" and "Atla" wait for it', (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on('PATCH /subscriptions/9', {
        'subscription': subscriptionJson(
            id: 9, name: 'Spotify', amount: 5999, next: '2026-11-08'),
      })
      ..hold('PATCH /subscriptions/9');
    await _pump(tester, api);
    await tester.longPress(find.text('Spotify'));
    await settleFrames(tester);
    await tester.tap(find.text('Atla'));
    await settleFrames(tester);
    await tester.tap(find.text('Spotify'));
    await settleFrames(tester);
    final sheet = find.byType(BottomSheet);
    expect(
        find.descendant(
            of: sheet, matching: find.text('Sonraki ödeme: 8 Kasım 2026')),
        findsOneWidget);
    final pay = tester.widget<ButtonStyleButton>(find.ancestor(
      of: find.descendant(
          of: sheet, matching: find.text('Ödendi olarak kaydet')),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ));
    expect(pay.enabled, isFalse);
    final skip = tester.widget<ButtonStyleButton>(find.ancestor(
      of: find.descendant(of: sheet, matching: find.text('Atla')),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ));
    expect(skip.enabled, isFalse);
    expect(api.requests, isNot(contains('POST /subscriptions/9/charge')));

    api.release('PATCH /subscriptions/9');
    await settleFrames(tester);
  });

  testWidgets('a skip from a sheet opened outside Abonelikler (Finans, Bugün, '
      'Arama) lets go once it has answered: reopened, the sheet shows the '
      'server\'s date and "Ödendi" and "Atla" work', (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on('PATCH /subscriptions/9', {
        'subscription': subscriptionJson(
            id: 9, name: 'Spotify', amount: 5999, next: '2026-11-08'),
      });
    await pumpFinance(
      tester,
      api,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showSubscriptionSheet(context, id: 9, name: 'Spotify'),
            child: const Text('aç'),
          ),
        ),
      ),
      overrides: [clockProvider.overrideWithValue(() => _now)],
    );
    Finder inSheet(String text) =>
        find.descendant(of: find.byType(BottomSheet), matching: find.text(text));
    bool enabled(String label) => tester
        .widget<ButtonStyleButton>(find.ancestor(
          of: inSheet(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ))
        .enabled;
    Future<void> open() async {
      await tester.tap(find.text('aç'));
      await settleFrames(tester);
    }

    Future<void> close() async {
      await tester.tapAt(const Offset(20, 20));
      await settleFrames(tester);
    }

    await open();
    await tester.tap(inSheet('Atla'));
    await letUndoRunOut(tester);
    expect(api.bodiesOf('PATCH /subscriptions/9').single,
        {'next_charge_on': '2026-11-08'});

    // The server has the skip now.
    api.on('GET /subscriptions', subscriptionsJson(active: [
      subscriptionJson(id: 9, name: 'Spotify', amount: 5999, next: '2026-11-08'),
    ]));
    await open();
    expect(inSheet('Sonraki ödeme: 8 Kasım 2026'), findsOneWidget);
    expect(enabled('Ödendi olarak kaydet'), isTrue);
    expect(enabled('Atla'), isTrue);
    await close();

    // Moved on elsewhere: the sheet follows the server, not the old skip.
    api.on('GET /subscriptions', subscriptionsJson(active: [
      subscriptionJson(id: 9, name: 'Spotify', amount: 5999, next: '2026-12-08'),
    ]));
    await open();
    expect(inSheet('Sonraki ödeme: 8 Aralık 2026'), findsOneWidget);
    expect(enabled('Ödendi olarak kaydet'), isTrue);
  });

  testWidgets('"Durdur" from the row moves it to "Duraklatılmış" at once, '
      'before the server answers', (tester) async {
    tallPhone(tester);
    final api = _api()
      ..on('PATCH /subscriptions/10', {
        'subscription': subscriptionJson(
            id: 10, name: 'Spor salonu', next: '2026-10-25', active: false),
      })
      ..hold('PATCH /subscriptions/10');
    await _pump(tester, api);
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Spor salonu'), lessThan(y('Duraklatılmış')));
    await tester.longPress(find.text('Spor salonu'));
    await settleFrames(tester);
    await tester.tap(find.text('Durdur'));
    // The menu closes; the PATCH is still unanswered.
    await settleFrames(tester);
    expect(y('Spor salonu'), greaterThan(y('Duraklatılmış')),
        reason: 'paused before the server answers');
    expect(api.bodiesOf('PATCH /subscriptions/10').single, {'active': false});
    api.release('PATCH /subscriptions/10');
    await settleFrames(tester);
    expect(find.text('“Spor salonu” durduruldu'), findsOneWidget);
  });

  testWidgets('a pause the server refuses puts the row back', (tester) async {
    tallPhone(tester);
    final api = _api()..failNetwork('PATCH /subscriptions/10');
    await _pump(tester, api);
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    await tester.longPress(find.text('Spor salonu'));
    await settleFrames(tester);
    await tester.tap(find.text('Durdur'));
    await settleFrames(tester);
    expect(y('Spor salonu'), lessThan(y('Duraklatılmış')));
    expect(find.byType(SnackBar), findsOneWidget, reason: 'it says why');
  });

  testWidgets('a skip the server refuses moves the row back and says so',
      (tester) async {
    tallPhone(tester);
    final api = _api()..failNetwork('PATCH /subscriptions/9');
    await _pump(tester, api);
    await tester.longPress(find.text('Spotify'));
    await settleFrames(tester);
    await tester.tap(find.text('Atla'));
    await settleFrames(tester);
    expect(find.text('Ödeme atlanamadı'), findsOneWidget);
    expect(_paid('Spotify'), findsOneWidget, reason: 'back in "Bu hafta"');
  });

  testWidgets('the form: the next payment from date chips; editing, pause '
      'and — further down — delete with "Geri al"', (tester) async {
    tallPhone(tester);
    final api = _api();
    await _pump(tester, api);
    await tester.tap(find.byType(FloatingActionButton));
    await settleFrames(tester);
    await tester.enterText(find.byType(TextField).first, 'Dergi');
    await tester.tap(find.text('Tutar').first);
    await settleFrames(tester);
    for (final key in ['5', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('Tamam'));
    await settleFrames(tester);
    await tester.tap(find.text('1 hafta'));
    await tester.pump();
    expect(find.text('11 Ekim 2026'), findsOneWidget);
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    final body = api.bodiesOf('POST /subscriptions').single as Map;
    expect(body['next_charge_on'], '2026-10-11');

    // Editing: "Durdur" above, "Sil" at least 24 dp below it.
    await tester.tap(find.text('Spor salonu'));
    await settleFrames(tester);
    await tester.tap(find.text('Düzenle'));
    await settleFrames(tester);
    final pause = tester.getRect(find.text('Durdur'));
    final delete = tester.getRect(find.text('Sil'));
    expect(delete.top - pause.bottom, greaterThanOrEqualTo(24));
    await tester.tap(find.text('Sil'));
    await settleFrames(tester);
    expect(find.text('Aboneliği düzenle'), findsNothing, reason: 'closed');
    expect(find.text('“Spor salonu” silindi'), findsOneWidget);
    expect(find.text('Spor salonu'), findsNothing, reason: 'off the list');
    expect(api.requests, isNot(contains('DELETE /subscriptions/10')));
  });

  for (final (locale, today, tomorrow, later) in const [
    (Locale('tr'), 'Bugün', 'Yarın', '3 gün sonra'),
    (Locale('en'), 'Today', 'Tomorrow', 'In 3 days'),
  ]) {
    testWidgets('${locale.languageCode}: a due row\'s date stands on its own '
        'line in sentence case — "$today", "$tomorrow", "$later"',
        (tester) async {
      tallPhone(tester);
      final api = FakeApi()
        ..on('GET /subscriptions', subscriptionsJson(active: [
          subscriptionJson(next: '2026-10-04'),
          subscriptionJson(id: 9, name: 'Spotify', next: '2026-10-05'),
          subscriptionJson(id: 10, name: 'Dergi', next: '2026-10-07'),
        ]));
      await pumpFinance(
        tester,
        api,
        const SubscriptionsScreen(),
        locale: locale,
        overrides: [clockProvider.overrideWithValue(() => _now)],
      );
      expect(find.text(today), findsOneWidget);
      expect(find.text(tomorrow), findsOneWidget);
      expect(find.text(later), findsOneWidget);
    });
  }

  test('nextChargeAfter: one period on, a missing day the month\'s last', () {
    expect(nextChargeAfter(DateTime(2026, 1, 31), 'monthly'),
        DateTime(2026, 2, 28));
    expect(nextChargeAfter(DateTime(2026, 12, 15), 'monthly'),
        DateTime(2027, 1, 15));
    expect(nextChargeAfter(DateTime(2028, 2, 29), 'yearly'),
        DateTime(2029, 2, 28));
    expect(nextChargeAfter(DateTime(2026, 10, 29), 'weekly'),
        DateTime(2026, 11, 5));
  });

  test('nextChargeAfter: a date a short month cut goes back to the start '
      'date\'s day (contract 4.6: 01-31 → 02-28 → 03-31 → 04-30)', () {
    final start = DateTime(2027, 1, 31);
    expect(nextChargeAfter(DateTime(2027, 1, 31), 'monthly', start: start),
        DateTime(2027, 2, 28));
    expect(nextChargeAfter(DateTime(2027, 2, 28), 'monthly', start: start),
        DateTime(2027, 3, 31));
    expect(nextChargeAfter(DateTime(2027, 3, 31), 'monthly', start: start),
        DateTime(2027, 4, 30));
    expect(nextChargeAfter(DateTime(2026, 9, 30), 'monthly', start: start),
        DateTime(2026, 10, 31));
    // A date the user set to another day keeps its day.
    expect(nextChargeAfter(DateTime(2027, 3, 15), 'monthly', start: start),
        DateTime(2027, 4, 15));
    // A 29 February start: back on the 29th in the next leap year.
    final leap = DateTime(2028, 2, 29);
    expect(nextChargeAfter(DateTime(2031, 2, 28), 'yearly', start: leap),
        DateTime(2032, 2, 29));
    expect(nextChargeAfter(DateTime(2029, 2, 28), 'yearly', start: leap),
        DateTime(2030, 2, 28));
  });

  test('firstChargeAfter: the contract\'s examples for a new one with a '
      'start and no date (on 2026-10-04)', () {
    final today = DateTime(2026, 10, 4);
    expect(firstChargeAfter(DateTime(2025, 1, 31), 'monthly', today),
        DateTime(2026, 10, 31));
    expect(firstChargeAfter(DateTime(2026, 9, 1), 'weekly', today),
        DateTime(2026, 10, 6));
    expect(firstChargeAfter(DateTime(2026, 11, 20), 'monthly', today),
        DateTime(2026, 11, 20), reason: 'a start after today');
    expect(firstChargeAfter(today, 'monthly', today), DateTime(2026, 11, 4),
        reason: 'the default: one period on');
    expect(firstChargeAfter(DateTime(2024, 2, 29), 'yearly', today),
        DateTime(2027, 2, 28));
    expect(firstChargeAfter(DateTime(2026, 9, 27), 'weekly', today),
        DateTime(2026, 10, 11), reason: 'not today itself');
  });

  testWidgets('"Atla" on a payment a short month cut moves it back to the '
      'billing day, as the server would', (tester) async {
    tallPhone(tester);
    final api = FakeApi()
      ..on('GET /subscriptions', subscriptionsJson(active: [
        {
          ...subscriptionJson(id: 9, name: 'Spotify', next: '2026-09-30'),
          'start_date': '2026-01-31',
        },
      ]));
    await _pump(tester, api);
    await tester.longPress(find.text('Spotify'));
    await settleFrames(tester);
    await tester.tap(find.text('Atla'));
    await settleFrames(tester);
    expect(api.bodiesOf('PATCH /subscriptions/9').single,
        {'next_charge_on': '2026-10-31'});
  });

  test('the form\'s start and end go only when touched; a cleared one as '
      'null', () {
    final before = Subscription.fromJson(subscriptionJson());
    SubscriptionInput input(({DateTime? start, DateTime? end})? period) =>
        SubscriptionInput(
          name: before.name,
          accountId: before.account.id,
          amountCents: before.amountCents,
          frequency: before.frequency,
          nextChargeOn: before.nextChargeOn,
          color: before.color,
          period: period,
        );
    expect(input(null).changesFrom(before, accountCurrency: 'TRY'), isEmpty);
    expect(
      input((start: DateTime(2026, 1, 15), end: DateTime(2026, 12, 31)))
          .changesFrom(before, accountCurrency: 'TRY'),
      {'end_date': '2026-12-31'},
    );
    expect(
      input((start: null, end: null))
          .changesFrom(before, accountCurrency: 'TRY'),
      {'start_date': null},
    );
    final created =
        input((start: DateTime(2026, 2, 1), end: null)).toJson();
    expect(created['start_date'], '2026-02-01');
    expect(created.containsKey('end_date'), isFalse);
  });

  test('urgencyOf: overdue, within 7 days, this month, later', () {
    final today = DateTime(2026, 10, 4);
    final sub = Subscription.fromJson(subscriptionJson());
    expect(urgencyOf(sub, DateTime(2026, 10, 3), today),
        SubscriptionUrgency.overdue);
    expect(urgencyOf(sub, DateTime(2026, 10, 11), today),
        SubscriptionUrgency.thisWeek);
    expect(urgencyOf(sub, DateTime(2026, 10, 12), today),
        SubscriptionUrgency.thisMonth);
    expect(urgencyOf(sub, DateTime(2026, 11, 1), today),
        SubscriptionUrgency.later);
    expect(urgencyOf(sub, null, today), SubscriptionUrgency.later);
    final paused = Subscription.fromJson(subscriptionJson(active: false));
    expect(urgencyOf(paused, DateTime(2026, 10, 3), today),
        SubscriptionUrgency.paused);
  });
}
