/// Larger text — up to 200% (design-research §6.2) — on the finance
/// screens, measured with the app's own fonts on a small phone (360×640):
/// rows and account tiles grow taller instead of overflowing, and the
/// transaction form's kind pill shrinks to the width there is. At the
/// normal size nothing moves: rows stay 64 dp, tiles 92 dp. The amount
/// sheet keeps "Tamam" in reach where its keypad does not fit: in
/// landscape, and on a small phone at 200%.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/ui/screens/finance/account_card.dart';
import 'package:meridian_mobile/ui/screens/finance/accounts_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_category_bars.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/subscriptions_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/transaction_form_screen.dart';
import 'package:meridian_mobile/ui/widgets/amount_field.dart';
import 'package:meridian_mobile/ui/widgets/nokturn_row.dart';

import '../support/app_fonts.dart';
import '../support/fake_api.dart';
import '../support/finance_harness.dart';

/// A small phone, 360×640, with the system text size at [scale].
void _smallPhone(WidgetTester tester, double scale) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// A page that opens the transaction form, as Finance does.
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

/// A page that opens the amount sheet as the account form does — with the
/// "Borç" switch, as tall as the sheet gets; [onResult] gets the amount it
/// closed with.
Widget _amountLauncher(ValueChanged<int?> onResult) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async => onResult(
          await showAmountSheet(
            context,
            title: 'Açılış bakiyesi',
            currency: 'TRY',
            subunitToUnit: 100,
            allowDebt: true,
          ),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

FakeApi _api() => FakeApi()
  ..on('GET /accounts', {
    'accounts': [
      accountJson(name: 'Maaş hesabı', type: 'bank', balance: 4569095000),
      accountJson(
        id: 4,
        name: 'Eski kredi kartı',
        type: 'credit_card',
        balance: -123456,
        archived: true,
      ),
    ],
  })
  ..on(
    'GET /subscriptions',
    subscriptionsJson(
      active: [subscriptionJson(name: 'Netflix Premium', next: '2020-01-15')],
      inactive: [subscriptionJson(id: 8, name: 'Gazete', active: false)],
    ),
  );

/// A dashboard with every section: a big net, budgets (one over), due
/// payments, recent transactions, categories, six months, the pace line.
Map<String, dynamic> _busyDashboard() => {
  ...financeDashboardJson(),
  'month': {
    'income_cents': 4569095000,
    'expense_cents': 123456789,
    'net_cents': 4445638211,
  },
  'year': {'income_cents': 9999999999, 'expense_cents': 123456789},
  'spend_cumulative_cents': [1000000, 50000000, 90000000, 123456789],
  'reference_cumulative_cents': List.generate(30, (i) => i * 3000000),
  'six_month_series': {
    'labels': [
      '2026-05',
      '2026-06',
      '2026-07',
      '2026-08',
      '2026-09',
      '2026-10',
    ],
    'income_cents': [100000, 0, 300000, 0, 500000, 4569095000],
    'expense_cents': [90000, 80000, 0, 70000, 60000, 123456789],
  },
  'pie': [
    {
      'id': 5,
      'name': 'Market ve gıda alışverişi',
      'color': '#D4915A',
      'amount_cents': 1800000,
      'breakdown': const [],
    },
    {
      'id': 0,
      'name': 'Kategorisiz',
      'color': '#6E6A64',
      'amount_cents': 345678,
      'breakdown': const [],
      'uncategorized': true,
    },
  ],
  'budgets': [
    budgetJson(),
    budgetJson(id: 3, categoryName: 'Restoran', spent: 9999999),
  ],
  'upcoming_subscriptions': [
    {
      'id': 6,
      'name': 'Netflix Premium Aile Paketi',
      'amount_cents': 22999,
      'frequency': 'monthly',
      'next_charge_on': '2020-01-15',
      'account': {
        'id': 1,
        'name': 'Maaş hesabı',
        'color': '#D4A574',
        'currency': 'TRY',
        'subunit_to_unit': 100,
      },
    },
  ],
  'recent_transactions': [transactionJson()],
};

/// A phone [width] dp wide (and 760 tall), with the text size at [scale].
void _phoneAt(WidgetTester tester, double width, double scale) {
  tester.view.physicalSize = Size(width * 3, 760 * 3);
  tester.view.devicePixelRatio = 3.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// This month's spending by category: a six-figure one first, and
/// [uncategorized] cents with no category.
Map<String, dynamic> _categoriesDashboard(int uncategorized) => {
  ...financeDashboardJson(),
  'month': {
    'income_cents': 0,
    'expense_cents': 15147345 + uncategorized,
    'net_cents': -(15147345 + uncategorized),
  },
  'pie': [
    {
      'id': 7,
      'name': 'Kira ve aidat',
      'color': '#B85450',
      'amount_cents': 12345678,
      'breakdown': const [],
    },
    {
      'id': 5,
      'name': 'Market ve gıda alışverişi',
      'color': '#D4915A',
      'amount_cents': 1800000,
      'breakdown': const [],
    },
    {
      'id': 6,
      'name': 'Ulaşım',
      'color': '#5A8FD4',
      'amount_cents': 1001667,
      'breakdown': const [],
    },
    {
      'id': 0,
      'name': 'Kategorisiz',
      'color': '#6E6A64',
      'amount_cents': uncategorized,
      'breakdown': const [],
      'uncategorized': true,
    },
  ],
};

/// No day-by-day series, but five months before this one with spending:
/// the hero projects the month's end against their average.
Map<String, dynamic> _projectionDashboard() => {
  ...financeDashboardJson(),
  'month': {'income_cents': 0, 'expense_cents': 3456789, 'net_cents': -3456789},
  'spend_cumulative_cents': null,
  'reference_cumulative_cents': null,
  'six_month_series': {
    'labels': [
      '2026-05',
      '2026-06',
      '2026-07',
      '2026-08',
      '2026-09',
      '2026-10',
    ],
    'income_cents': [0, 0, 0, 0, 0, 0],
    'expense_cents': [4123456, 3987654, 4234567, 3876543, 4012345, 3456789],
  },
};

/// Spending, and nothing to compare it with: what was spent, and per day.
Map<String, dynamic> _spentDashboard() => {
  ...financeDashboardJson(),
  'month': {'income_cents': 0, 'expense_cents': 3456789, 'net_cents': -3456789},
};

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await initializeDateFormatting();
  });

  for (final scale in const [1.6, 2.0]) {
    group('text at ${scale}x', () {
      for (final locale in const [Locale('tr'), Locale('en')]) {
        testWidgets('the transaction form (${locale.languageCode}): the kind '
            'pill stays on screen', (tester) async {
          _smallPhone(tester, scale);
          await pumpFinance(tester, _api(), _formLauncher(), locale: locale);
          await tester.tap(find.text('open'));
          await settleFrames(tester);
          expect(tester.takeException(), isNull);
          final kinds = locale.languageCode == 'tr'
              ? ['Gider', 'Gelir', 'Transfer']
              : ['Expense', 'Income', 'Transfer'];
          for (final kind in kinds) {
            final box = tester.getRect(find.text(kind));
            expect(box.left, greaterThanOrEqualTo(0), reason: kind);
            expect(box.right, lessThanOrEqualTo(360), reason: kind);
          }
        });
      }

      testWidgets('Abonelikler: rows grow with their text', (tester) async {
        _smallPhone(tester, scale);
        await pumpFinance(tester, _api(), const SubscriptionsScreen());
        expect(tester.takeException(), isNull);
        expect(find.text('Netflix Premium'), findsOneWidget);
        // Overdue: the row with its inline "Ödendi" (design-analysis §7.8).
        expect(
          tester.getSize(find.byType(SubscriptionRow).first).height,
          greaterThan(64),
        );
      });

      testWidgets('Hesaplar, the archive open: rows grow with their text', (
        tester,
      ) async {
        _smallPhone(tester, scale);
        await pumpFinance(
          tester,
          _api(),
          const AccountsScreen(showArchived: true),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Eski kredi kartı'), findsOneWidget);
        expect(
          tester.getSize(find.byType(NokturnRow).first).height,
          greaterThan(64),
        );
      });

      testWidgets('Finance: every section lays out, nothing overflows', (
        tester,
      ) async {
        _smallPhone(tester, scale);
        final api = _api()..on('GET /finance/dashboard', _busyDashboard());
        await pumpFinance(tester, api, const FinanceScreen());
        expect(tester.takeException(), isNull);
        final list = find.byType(ListView).first;
        for (var i = 0; i < 16; i++) {
          await tester.drag(list, const Offset(0, -300));
          await settleFrames(tester);
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('Finance: the account tiles — and their strip — grow with '
          'their text', (tester) async {
        _smallPhone(tester, scale);
        await pumpFinance(tester, _api(), const FinanceScreen());
        await tester.dragUntilVisible(
          find.byType(AccountTile),
          find.byType(ListView).first,
          const Offset(0, -100),
        );
        await settleFrames(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Maaş hesabı'), findsOneWidget);
        expect(
          tester.getSize(find.byType(AccountTile).first).height,
          greaterThan(AccountTile.minHeight),
        );
      });
    });
  }

  // The common text sizes on 360 and 384 dp phones (§8.3): the categories'
  // rows — an uncategorized slice with "Kategorize et", a six-figure
  // category — fit without overflowing and without cutting an amount.
  for (final width in const [360.0, 384.0]) {
    for (final scale in const [1.15, 1.2, 1.3, 1.8, 2.0]) {
      for (final locale in const [Locale('tr'), Locale('en')]) {
        for (final uncategorized in const [345678, 34567]) {
          testWidgets('Finance categories, ${width.round()} dp at ${scale}x '
              '(${locale.languageCode}, uncategorized $uncategorized): '
              'nothing overflows, no amount is cut', (tester) async {
            _phoneAt(tester, width, scale);
            final api = _api()
              ..on(
                'GET /finance/dashboard',
                _categoriesDashboard(uncategorized),
              );
            await pumpFinance(
              tester,
              api,
              const FinanceScreen(),
              locale: locale,
            );
            expect(tester.takeException(), isNull);
            final categorize = find.text(
              locale.languageCode == 'tr' ? 'Kategorize et' : 'Categorize',
            );
            await tester.dragUntilVisible(
              categorize,
              find.byType(ListView).first,
              const Offset(0, -200),
            );
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -200),
            );
            await settleFrames(tester);
            expect(tester.takeException(), isNull);
            // The six-figure amount, whole and on screen.
            final big = find.descendant(
              of: find.byType(FinanceCategoryBars),
              matching: find.textContaining(RegExp(r'123[.,]456')),
            );
            expect(big, findsOneWidget);
            expect(tester.getRect(big).right, lessThanOrEqualTo(width - 16));
            expect(
              tester.getRect(categorize).right,
              lessThanOrEqualTo(width - 16),
            );
            for (var i = 0; i < 6; i++) {
              await tester.drag(
                find.byType(ListView).first,
                const Offset(0, -300),
              );
              await settleFrames(tester);
              expect(tester.takeException(), isNull);
            }
          });
        }
      }
    }
  }

  // The hero's sentence (§4.20) is never cut with "…": where two lines are
  // not enough it is shown whole under the hero's figures.
  for (final (locale, json, prefix, width) in [
    (const Locale('tr'), _projectionDashboard(), 'Bu tempoyla', 360.0),
    (const Locale('en'), _projectionDashboard(), 'At this pace', 360.0),
    (const Locale('en'), _projectionDashboard(), 'At this pace', 411.0),
    (const Locale('tr'), _spentDashboard(), 'Bu ay', 360.0),
    (const Locale('en'), _spentDashboard(), 'You have spent', 360.0),
  ]) {
    for (final scale in const [1.0, 1.15, 1.3, 2.0]) {
      testWidgets('the hero\'s "$prefix…" sentence, ${width.round()} dp at '
          '${scale}x (${locale.languageCode}): whole', (tester) async {
        _phoneAt(tester, width, scale);
        final api = _api()..on('GET /finance/dashboard', json);
        await pumpFinance(tester, api, const FinanceScreen(), locale: locale);
        expect(tester.takeException(), isNull);
        final sentence = find.byWidgetPredicate(
          (w) => w is Text && (w.data?.startsWith(prefix) ?? false),
        );
        expect(sentence, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: sentence, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
      });
    }
  }

  // A due row keeps "Ödendi" and ⋯ beside its texts only while the date
  // fits there in two lines (design-analysis §7.8): it wraps but is never
  // cut, so a payment missed long ago keeps its year. And the two targets
  // keep 8 dp apart (§8.2).
  for (final (width, scale) in const [
    (360.0, 1.0),
    (360.0, 1.2),
    (360.0, 1.25),
    (360.0, 1.3),
    (320.0, 1.0),
    (320.0, 1.15),
  ]) {
    for (final locale in const [Locale('tr'), Locale('en')]) {
      testWidgets('Abonelikler at ${scale}x on a ${width.toInt()} dp phone '
          '(${locale.languageCode}): the overdue date is never cut', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 640) * 3;
        tester.view.devicePixelRatio = 3.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpFinance(
          tester,
          _api(),
          const SubscriptionsScreen(),
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        final row = find.byType(SubscriptionRow).first;
        final texts = find.descendant(of: row, matching: find.byType(RichText));
        expect(texts, findsWidgets);
        for (final element in texts.evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '"${paragraph.text.toPlainText()}" is cut',
          );
        }
        final date = locale.languageCode == 'tr'
            ? 'Gecikmiş · 15 Ocak 2020'
            : 'Overdue · January 15, 2020';
        expect(
          find.descendant(of: row, matching: find.text(date)),
          findsOneWidget,
        );

        final paid = tester.getRect(
          find.descendant(of: row, matching: find.byType(OutlinedButton)),
        );
        final more = tester.getRect(
          find.descendant(of: row, matching: find.byType(IconButton)),
        );
        if (paid.top < more.bottom && more.top < paid.bottom) {
          expect(more.left - paid.right, greaterThanOrEqualTo(8));
        }
        expect(more.right, lessThanOrEqualTo(width));
      });
    }
  }

  for (final (screen, size, scale) in const [
    ('in landscape, 640×360', Size(640, 360), 1.0),
    ('in landscape, 844×390', Size(844, 390), 1.0),
    ('on a 320×568 phone at 200%', Size(320, 568), 2.0),
  ]) {
    testWidgets('the amount sheet $screen: the keypad scrolls, and "Tamam" '
        'stays on screen to confirm the amount', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      int? result;
      await pumpFinance(tester, FakeApi(), _amountLauncher((v) => result = v));
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.text('Tamam').hitTestable(), findsOneWidget);

      // The keys below the fold are a scroll away; "Tamam" stays put.
      for (final key in ['1', '0']) {
        await tester.ensureVisible(find.text(key));
        await tester.pump();
        await tester.tap(find.text(key));
        await tester.pump();
      }
      expect(find.text('Tamam').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Tamam'));
      await settleFrames(tester);
      expect(result, 1000);
    });
  }

  testWidgets('at the normal size, rows stay 64 dp and tiles 92 dp', (
    tester,
  ) async {
    _smallPhone(tester, 1.0);
    await pumpFinance(tester, _api(), const SubscriptionsScreen());
    // 64 dp at least; a meta line that wraps (up to two, §4.4) grows it.
    expect(
      tester.getSize(find.byType(NokturnRow).first).height,
      greaterThanOrEqualTo(64),
    );

    await pumpFinance(tester, _api(), const FinanceScreen());
    await tester.dragUntilVisible(
      find.byType(AccountTile),
      find.byType(ListView).first,
      const Offset(0, -100),
    );
    await settleFrames(tester);
    expect(
      tester.getSize(find.byType(AccountTile).first).height,
      AccountTile.minHeight,
    );
  });
}
