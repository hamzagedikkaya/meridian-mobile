import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/finance/transactions_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';

// --- Fixtures (shaped exactly like scratchpad/api-samples.json) ---------------

final _at = DateTime(2026, 7, 11);

/// Real /accounts payload: a GAU account (subunit 1), a negative balance, a big
/// positive, a zero-init credit card.
List<Account> _accounts() => [
      Account.fromJson(const {
        'id': 21,
        'name': 'Altın',
        'account_type': 'savings',
        'currency': 'GAU',
        'subunit_to_unit': 1,
        'color': '#B8860B',
        'initial_balance_cents': 12,
        'balance_cents': 31,
        'archived': false,
      }),
      Account.fromJson(const {
        'id': 17,
        'name': 'Cüzdan',
        'account_type': 'cash',
        'currency': 'TRY',
        'subunit_to_unit': 100,
        'color': '#D4A574',
        'initial_balance_cents': 20000,
        'balance_cents': -6859733,
        'archived': false,
      }),
      Account.fromJson(const {
        'id': 18,
        'name': 'Maaş hesabı',
        'account_type': 'bank',
        'currency': 'TRY',
        'subunit_to_unit': 100,
        'color': '#6B8FA0',
        'initial_balance_cents': 850000,
        'balance_cents': 45690950,
        'archived': false,
      }),
    ];

Map<String, dynamic> _tryAccountRef(int id, String name, String color) => {
      'id': id,
      'name': name,
      'color': color,
      'currency': 'TRY',
      'subunit_to_unit': 100,
    };

/// Populated dashboard: big year totals (exercises the hero FittedBox), a pie
/// with a breakdown, a normal budget + an over-budget with **limit 0** (pace
/// division edge), subscriptions, and recent transactions incl. a GAU/null-
/// category income row and a transfer (category null, related_account set).
FinanceDashboard _dashboard() => FinanceDashboard.fromJson({
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'month': {'income_cents': 3578400, 'expense_cents': 200000, 'net_cents': 3378400},
      'year': {'income_cents': 23514508, 'expense_cents': 14582729},
      'six_month_series': {
        'labels': ['2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07'],
        'income_cents': [5722102, 4798002, 3851102, 4208801, 0, 0],
        'expense_cents': [3472290, 2953296, 2401205, 2439331, 0, 0],
      },
      'pie': [
        {
          'id': 34,
          'name': 'Market',
          'color': '#D4915A',
          'amount_cents': 120000,
          'breakdown': [
            {'id': 34, 'name': 'Market', 'amount_cents': 120000, 'is_root': true},
          ],
        },
        {
          'id': 39,
          'name': 'Eğlence',
          'color': '#8B5A00',
          'amount_cents': 80000,
          'breakdown': const [],
        },
      ],
      'budgets': [
        {
          'category': {'id': 39, 'name': 'Eğlence'},
          'color': '#8B5A00',
          'limit_cents': 200000,
          'spent_cents': 90000,
          'remaining_cents': 110000,
          'percent_used': 45.0,
          'pace_percent': 50.0,
          'projected_cents': 180000,
          'state': 'under',
        },
        {
          // Edge: limit 0 — pace/percent come pre-computed, projected > limit.
          'category': {'id': 34, 'name': 'Market'},
          'color': '#D4915A',
          'limit_cents': 0,
          'spent_cents': 5000,
          'remaining_cents': -5000,
          'percent_used': 0.0,
          'pace_percent': 0.0,
          'projected_cents': 8000,
          'state': 'over',
        },
      ],
      'upcoming_subscriptions': [
        {
          'id': 16,
          'name': 'Netflix',
          'amount_cents': 18999,
          'frequency': 'monthly',
          'next_charge_on': '2026-07-20',
          'account': _tryAccountRef(18, 'Maaş hesabı', '#6B8FA0'),
        },
      ],
      'recent_transactions': [
        {
          'id': 316,
          'kind': 'expense',
          'amount_cents': 13874,
          'date': '2026-05-25',
          'description': 'Restoran — Lokanta',
          'note': null,
          'account': _tryAccountRef(19, 'Kredi kartı', '#B85450'),
          'category': {
            'id': 35,
            'name': 'Restoran',
            'kind': 'expense',
            'color': '#B85450',
            'parent_id': null,
            'position': 0,
          },
          'related_account': null,
        },
        {
          // GAU income, category null (real row id 333).
          'id': 333,
          'kind': 'income',
          'amount_cents': 1,
          'date': '2026-05-15',
          'description': '1 gr altın alımı',
          'note': null,
          'account': {
            'id': 21,
            'name': 'Altın',
            'color': '#B8860B',
            'currency': 'GAU',
            'subunit_to_unit': 1,
          },
          'category': null,
          'related_account': null,
        },
        {
          // Transfer: category null, related_account set.
          'id': 400,
          'kind': 'transfer',
          'amount_cents': 50000,
          'date': '2026-05-14',
          'description': null,
          'note': null,
          'account': _tryAccountRef(17, 'Cüzdan', '#D4A574'),
          'category': null,
          'related_account': _tryAccountRef(20, 'Birikim', '#6B8E5A'),
        },
      ],
    });

/// Empty/edge dashboard: zero money, empty pie/budgets/subs/recent.
FinanceDashboard _emptyDashboard() => FinanceDashboard.fromJson(const {
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'month': {'income_cents': 0, 'expense_cents': 0, 'net_cents': 0},
      'year': {'income_cents': 0, 'expense_cents': 0},
      'six_month_series': {
        'labels': ['2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07'],
        'income_cents': [0, 0, 0, 0, 0, 0],
        'expense_cents': [0, 0, 0, 0, 0, 0],
      },
      'pie': [],
      'budgets': [],
      'upcoming_subscriptions': [],
      'recent_transactions': [],
    });

Transaction _tx(Map<String, dynamic> json) => Transaction.fromJson(json);

/// A feed of real /transactions rows incl. GAU/null-category + a transfer.
/// hasMore is false so the footer shows "Tümü yüklendi" (no infinite spinner).
TransactionsFeed _feed({required bool empty}) {
  final items = empty
      ? <Transaction>[]
      : [
          _tx({
            'id': 316,
            'kind': 'expense',
            'amount_cents': 13874,
            'date': '2026-05-25',
            'description': 'Restoran — Lokanta',
            'note': null,
            'account': _tryAccountRef(19, 'Kredi kartı', '#B85450'),
            'category': {
              'id': 35,
              'name': 'Restoran',
              'kind': 'expense',
              'color': '#B85450',
              'parent_id': null,
              'position': 0,
            },
            'related_account': null,
          }),
          _tx({
            'id': 333,
            'kind': 'income',
            'amount_cents': 1,
            'date': '2026-05-15',
            'description': '1 gr altın alımı',
            'note': null,
            'account': {
              'id': 21,
              'name': 'Altın',
              'color': '#B8860B',
              'currency': 'GAU',
              'subunit_to_unit': 1,
            },
            'category': null,
            'related_account': null,
          }),
          _tx({
            'id': 400,
            'kind': 'transfer',
            'amount_cents': 50000,
            'date': '2026-05-14',
            'description': null,
            'note': null,
            'account': _tryAccountRef(17, 'Cüzdan', '#D4A574'),
            'category': null,
            'related_account': _tryAccountRef(20, 'Birikim', '#6B8E5A'),
          }),
        ];
  return TransactionsFeed(
    items: items,
    meta: TransactionMeta.fromJson(const {
      'total_count': 3,
      'page': 1,
      'page_limit': 50,
      'filtered_income_cents': 65976019,
      'filtered_expense_cents': 35873475,
    }),
    hasMore: false,
    at: _at,
  );
}

/// Stub notifier: serves a fixed feed, no-ops every mutation so the family
/// provider never reaches Dio (the screens now pass filters as the family key).
class _StubTxNotifier extends TransactionsNotifier {
  _StubTxNotifier(this._fixture) : super(const TxFilters());
  final TransactionsFeed _fixture;

  @override
  Future<TransactionsFeed> build() async => _fixture;

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

// --- Harness ------------------------------------------------------------------

Widget _host(Widget child, List<dynamic> overrides) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr'), Locale('en')],
      locale: const Locale('tr'),
      home: child,
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() => initializeDateFormatting());

  group('FinanceScreen', () {
    testWidgets('renders populated dashboard without exceptions', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(
        const FinanceScreen(),
        [
          financeDashboardProvider.overrideWith((ref) => Fetched(_dashboard(), _at)),
          accountsProvider.overrideWith((ref) => Fetched(_accounts(), _at)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Top-of-screen content.
      expect(find.text('BU AY NET'), findsOneWidget);
      expect(find.text('Son 6 ay'), findsOneWidget);
      expect(find.text('Kategoriler (bu ay)'), findsOneWidget);
      // First carousel page is the GAU account (no decimals + "gr").
      expect(find.text('Altın'), findsOneWidget);
      expect(find.text('31 gr'), findsOneWidget);

      // Scroll the lazy ListView so the budgets card (incl. the limit-0 pace
      // row) and the recent rows (GAU/null-category + transfer) actually build.
      final list = find.byType(ListView);
      await tester.dragUntilVisible(
          find.text('Bütçeler'), list, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Bütçeler'), findsOneWidget);
      expect(find.text('aşıldı'), findsOneWidget); // over-budget (limit 0) pill

      await tester.dragUntilVisible(
          find.text('Restoran — Lokanta'), list, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Restoran — Lokanta'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('year scope with large totals does not overflow', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(
        const FinanceScreen(),
        [
          financeDashboardProvider.overrideWith((ref) => Fetched(_dashboard(), _at)),
          accountsProvider.overrideWith((ref) => Fetched(_accounts(), _at)),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yıl'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('BU YIL NET'), findsOneWidget);
    });

    testWidgets('empty state: no accounts, no spend', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(
        const FinanceScreen(),
        [
          financeDashboardProvider
              .overrideWith((ref) => Fetched(_emptyDashboard(), _at)),
          accountsProvider
              .overrideWith((ref) => Fetched(const <Account>[], _at)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('İlk hesabını ekle'), findsOneWidget);
      expect(find.text('Bu ay harcama yok'), findsOneWidget);

      // The empty "Son işlemler" card sits at the bottom of the list.
      await tester.dragUntilVisible(
          find.text('Henüz işlem yok'),
          find.byType(ListView),
          const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Henüz işlem yok'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('İşlemler', () {
    testWidgets('renders populated feed without exceptions', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(
        const TransactionsScreen(),
        [
          transactionsProvider
              .overrideWith2((filters) => _StubTxNotifier(_feed(empty: false))),
          accountsProvider.overrideWith((ref) => Fetched(_accounts(), _at)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('İşlemler'), findsWidgets);
      expect(find.text('Restoran — Lokanta'), findsOneWidget);
      // Transfer row falls back to its category-less title.
      expect(find.text('Transfer'), findsWidgets);
      // Summary line present.
      expect(find.textContaining('gelir · '), findsOneWidget);
    });

    testWidgets('empty feed shows "Henüz işlem yok"', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(
        const TransactionsScreen(),
        [
          transactionsProvider
              .overrideWith2((filters) => _StubTxNotifier(_feed(empty: true))),
          accountsProvider.overrideWith((ref) => Fetched(_accounts(), _at)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Henüz işlem yok'), findsOneWidget);
    });
  });
}
