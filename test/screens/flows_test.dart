/// The flow entry points (`lib/ui/flows/flows.dart`, WP-4): what a screen
/// calls to add something or act on a record.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/models/subscription.dart';
import 'package:meridian_mobile/ui/flows/flows.dart';

import '../support/app_harness.dart';
import '../support/fake_api.dart';

/// A button at `/` that runs [open] with a [WidgetRef].
Widget _refOpener(void Function(BuildContext context, WidgetRef ref) open) =>
    Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Center(
          child: TextButton(
            onPressed: () => open(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  setUpAll(initializeDateFormatting);

  group('markSubscriptionPaid', () {
    final netflix =
        SubscriptionLite.of(Subscription.fromJson(subscriptionJson()));

    testWidgets('records one payment however often it is tapped, says so, '
        'and "Geri al" deletes it and puts the due date back', (tester) async {
      final api = FakeApi()
        ..hold('POST /subscriptions/6/charge')
        ..on('DELETE /transactions/401', null, status: 204);
      await pumpWithRoutes(
        tester,
        api,
        home: _refOpener(
            (context, ref) => markSubscriptionPaid(context, ref, netflix)),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pump();
      api.release('POST /subscriptions/6/charge');
      await settleFrames(tester);
      expect(
          api.requests.where((r) => r == 'POST /subscriptions/6/charge'),
          hasLength(1));
      expect(find.textContaining('Ödeme kaydedildi'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(api.requests, contains('DELETE /transactions/401'));
      expect(api.bodiesOf('PATCH /subscriptions/6').single,
          {'next_charge_on': '2026-10-15'});
    });

    testWidgets('a refusal is said, and the next tap may try again',
        (tester) async {
      final api = FakeApi()..fail('POST /subscriptions/6/charge', 500);
      await pumpWithRoutes(
        tester,
        api,
        home: _refOpener(
            (context, ref) => markSubscriptionPaid(context, ref, netflix)),
      );
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Geri al'), findsNothing);

      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(
          api.requests.where((r) => r == 'POST /subscriptions/6/charge'),
          hasLength(2));
    });
  });

  testWidgets('openTransactionForm fills a new transaction in',
      (tester) async {
    await pumpWithRoutes(
      tester,
      FakeApi(),
      home: _refOpener((context, _) => openTransactionForm(
            context,
            initialKind: 'income',
            initialAmountCents: 12345,
            initialDescription: 'Maaş',
          )),
    );
    await tester.tap(find.text('open'));
    await settleFrames(tester);
    final description = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller?.text);
    expect(description, contains('Maaş'));
    expect(find.textContaining('123,45'), findsWidgets);
  });

  testWidgets('openHabitLog for a past day logs that day', (tester) async {
    final api = FakeApi();
    await pumpWithRoutes(
      tester,
      api,
      home: _refOpener((context, _) =>
          openHabitLog(context, habitId: 7, date: DateTime(2026, 10, 2))),
    );
    await tester.tap(find.text('open'));
    await settleFrames(tester);
    expect(find.text('2 Ekim'), findsOneWidget, reason: 'the day, not today');
    await tester.tap(find.text('Tamamla'));
    await settleFrames(tester);
    expect(
        api.requests.where((r) => r.startsWith('PUT /habits/7/logs/')),
        ['PUT /habits/7/logs/2026-10-02']);
  });

  group('openHabitLog for a day before the Habits list\'s two weeks', () {
    /// Koşu with a target of 8, its list copy reaching back to Oct 3 only;
    /// its year of history has Sep 10 at 5 of 8.
    FakeApi api() {
      final habit = habitJson(targetCount: 8);
      return FakeApi()
        ..on('GET /habits', {
          'habits': [habit],
          'meta': habitsMeta(totalActive: 1),
        })
        ..on('GET /habits/7', {
          'habit': {
            ...habitDetailJson(),
            'target_count': 8,
            'chain': [
              {
                'date': '2026-09-10',
                'status': 'partial',
                'completed': 5,
                'possible': 8,
              },
              ...habit['chain'] as List,
            ],
          },
        });
    }

    Future<void> open(WidgetTester tester, FakeApi api) async {
      await pumpWithRoutes(
        tester,
        api,
        home: _refOpener((context, _) =>
            openHabitLog(context, habitId: 7, date: DateTime(2026, 9, 10))),
      );
      await tester.tap(find.text('open'));
    }

    testWidgets('reads the habit\'s year first, then steps from the day\'s '
        'count', (tester) async {
      final fake = api()..hold('GET /habits/7');
      await open(tester, fake);
      await settleFrames(tester);
      expect(find.text('Tamamla'), findsNothing,
          reason: 'nothing to write from until the day is read');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      fake.release('GET /habits/7');
      await settleFrames(tester);
      expect(find.text('5 / 8'), findsOneWidget);
      await tester.tap(find.byTooltip('Bir artır'));
      await settleFrames(tester);
      expect(fake.bodiesOf('PUT /habits/7/logs/2026-09-10'), [
        {'count': 6},
      ]);
    });

    testWidgets('taps made while a change is on its way are sent after it, '
        'the last one last', (tester) async {
      final fake = api();
      await open(tester, fake);
      await settleFrames(tester);
      expect(find.text('5 / 8'), findsOneWidget);

      fake.hold('PUT /habits/7/logs/2026-09-10');
      await tester.tap(find.byTooltip('Bir artır'));
      await tester.pump();
      await tester.tap(find.byTooltip('Bir artır'));
      await tester.pump();
      await tester.tap(find.byTooltip('Bir artır'));
      await tester.pump();
      expect(find.text('8 / 8'), findsOneWidget);
      fake.release('PUT /habits/7/logs/2026-09-10');
      await settleFrames(tester);
      expect(fake.bodiesOf('PUT /habits/7/logs/2026-09-10'), [
        {'count': 6},
        {'count': 8},
      ]);
      expect(find.text('8 / 8'), findsOneWidget);
    });
  });
}
