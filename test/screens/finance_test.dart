import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/models/subscription.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/l10n/app_l10n_tr.dart';
import 'package:meridian_mobile/ui/widgets/pace_line.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/finance/transaction_form_screen.dart';
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
          'id': 2,
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
    testWidgets('renders populated dashboard without exceptions, now first',
        (tester) async {
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
      // Top-of-screen content: the month's net, no month/year switch.
      expect(find.text('BU AY NET'), findsOneWidget);
      expect(find.text('Yıl'), findsNothing);
      expect(find.text('Ay'), findsNothing);
      // The year is one line under it.
      expect(find.text('Bu yıl +₺89.317,79'), findsOneWidget);
      // The first tile is the GAU account (no decimals + "gr").
      expect(find.text('Altın'), findsOneWidget);
      expect(find.text('31\u00A0gr'), findsWidgets);

      // Scroll the lazy ListView so every section builds, in its order.
      final list = find.byType(ListView).first;
      final order = <String>[
        'Yaklaşan ödemeler',
        'Bütçeler',
        'Son işlemler',
        'Kategoriler (bu ay)',
        'Son 6 ay',
      ];
      for (final title in order) {
        await tester.dragUntilVisible(
            find.text(title), list, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget, reason: title);
        if (title == 'Bütçeler') {
          // Over budget (limit 0): by how much, never an "exceeded" label,
          // and a way to change the limit.
          expect(find.text('₺50 fazla'), findsOneWidget);
          expect(find.text('Limiti düzenle'), findsOneWidget);
          // Spent against the limit.
          expect(find.text('₺900 / ₺2.000'), findsOneWidget);
        }
        if (title == 'Yaklaşan ödemeler') {
          // Netflix's date has passed: it can be marked paid.
          expect(find.text('Netflix'), findsOneWidget);
          expect(find.text('Ödendi'), findsOneWidget);
        }
      }

      await tester.dragUntilVisible(
          find.text('Restoran — Lokanta'), list, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(find.text('Restoran — Lokanta'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the sections stand in §7.5\'s order, top to bottom',
        (tester) async {
      // Tall enough for every section to be laid out at once.
      tester.view.physicalSize = const Size(390, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(
        const FinanceScreen(),
        [
          financeDashboardProvider.overrideWith((ref) => Fetched(_dashboard(), _at)),
          accountsProvider.overrideWith((ref) => Fetched(_accounts(), _at)),
        ],
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final order = <Finder>[
        find.text('BU AY NET'),
        find.text('Altın'), // the first account tile
        find.text('Yaklaşan ödemeler'),
        find.text('Bütçeler'),
        find.text('Son işlemler'),
        find.text('Kategoriler (bu ay)'),
        find.text('Son 6 ay'),
      ];
      double? above;
      for (final section in order) {
        expect(section, findsOneWidget, reason: '$section');
        final top = tester.getTopLeft(section).dy;
        if (above != null) {
          expect(top, greaterThan(above), reason: '$section');
        }
        above = top;
      }
    });

    testWidgets('first run: no account at all — one calm card, one step',
        (tester) async {
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
      expect(find.text('İlk hesabını oluştur'), findsOneWidget);
      expect(find.text('Nakit hesabıyla başla'), findsOneWidget);
      expect(find.text('Başka bir hesap ekle'), findsOneWidget);
      // Nothing else competes with it: no empty charts, no zero hero, no
      // transaction FAB (it would need an account first).
      expect(find.text('BU AY NET'), findsNothing);
      expect(find.text('Bu ay harcama yok'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('an account but no transaction yet: the setup card is the '
        'next step, and the only "add a transaction" on screen', (tester) async {
      // Wide: the test font draws every glyph a full em wide, and the empty
      // cards' two buttons sit beside their message.
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(
        const FinanceScreen(),
        [
          financeDashboardProvider
              .overrideWith((ref) => Fetched(_emptyDashboard(), _at)),
          accountsProvider.overrideWith(
              (ref) => Fetched(_accounts().take(1).toList(), _at)),
          subscriptionsProvider.overrideWith((ref) => Fetched(
              const SubscriptionsBundle(active: [], inactive: [], totals: []),
              _at)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Zero is "₺0", never "+₺0,00".
      expect(find.text('₺0'), findsWidgets);
      expect(find.textContaining('+₺0'), findsNothing);
      expect(find.text('Kurulum 1/4'), findsOneWidget);
      expect(find.text('İlk işlemini ekle'), findsOneWidget);
      // The FAB stays out while the card offers the same thing.
      final fab = find.byType(FloatingActionButton);
      expect(fab.hitTestable(), findsNothing);
      // The card carries the budget and subscription steps: their own
      // empty cards wait.
      expect(find.text('Bütçe ekle'), findsNothing);
      // The tiles end with "+ Hesap".
      expect(find.text('Hesap'), findsOneWidget);

      // "Gizle" puts the card away: the FAB is back, and so are the empty
      // budgets and subscriptions cards.
      await tester.tap(find.text('Gizle').first);
      await tester.pumpAndSettle();
      expect(find.text('Kurulum 1/4'), findsNothing);
      expect(fab.hitTestable(), findsOneWidget);
      await tester.dragUntilVisible(find.text('Bütçe ekle'),
          find.byType(ListView).first, const Offset(0, -200));
      expect(find.text('Bütçe ekle'), findsOneWidget);
      expect(find.text('Abonelik ekle'), findsOneWidget);
    });
  });

  group('the hero\'s sentence (§4.24)', () {
    const l = AppL10nTr();
    FinanceDashboard dash(Map<String, dynamic> extra) =>
        FinanceDashboard.fromJson({
          'currency': 'TRY',
          'subunit_to_unit': 100,
          'month': {'income_cents': 0, 'expense_cents': 800000, 'net_cents': -800000},
          'year': {'income_cents': 0, 'expense_cents': 800000},
          'six_month_series': {
            'labels': ['2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10'],
            'income_cents': [0, 0, 0, 0, 0, 0],
            'expense_cents': [0, 0, 0, 0, 0, 800000],
          },
          ...extra,
        });
    final oct10 = DateTime(2026, 10, 10);

    test('against the same day last month, with its series', () {
      final d = dash({
        'spend_cumulative_cents': [for (var i = 1; i <= 10; i++) i * 80000],
        'reference_cumulative_cents': [for (var i = 1; i <= 30; i++) i * 100000],
      });
      expect(financeInsight(l, d, oct10),
          'Geçen ayın aynı gününe göre ₺2.000 daha az harcadın');
    });

    test('a short month: the same day is its last', () {
      final d = dash({
        'spend_cumulative_cents': [for (var i = 1; i <= 31; i++) 900000],
        'reference_cumulative_cents': [for (var i = 1; i <= 28; i++) 800000],
      });
      expect(financeInsight(l, d, DateTime(2026, 3, 31)),
          'Geçen ayın aynı gününe göre ₺1.000 daha fazla harcadın');
    });

    test('nothing spent last month: no comparison', () {
      final d = dash({
        'spend_cumulative_cents': [for (var i = 1; i <= 10; i++) i * 80000],
        'reference_cumulative_cents': List.filled(30, 0),
      });
      expect(financeInsight(l, d, oct10),
          'Bu ay ₺8.000 harcadın · günde ortalama ₺800');
    });

    test('without the series (an older server): the pace against the five '
        'months before', () {
      final d = FinanceDashboard.fromJson({
        'currency': 'TRY',
        'subunit_to_unit': 100,
        'month': {'income_cents': 0, 'expense_cents': 1000000, 'net_cents': -1000000},
        'year': {'income_cents': 0, 'expense_cents': 1000000},
        'six_month_series': {
          'labels': ['2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10'],
          'income_cents': [0, 0, 0, 0, 0, 0],
          'expense_cents': [3000000, 0, 3000000, 3000000, 3000000, 1000000],
        },
      });
      // ₺10.000 in 10 days → ₺31.000 by the 31st, against the five
      // months' ₺24.000 (the month without spending counts as zero).
      expect(financeInsight(l, d, oct10),
          'Bu tempoyla ay sonu gider ₺31.000, 5 aylık ortalamanın %29 üstünde');
    });

    test('nothing spent yet', () {
      final d = FinanceDashboard.fromJson({
        'currency': 'TRY',
        'subunit_to_unit': 100,
        'month': {'income_cents': 0, 'expense_cents': 0, 'net_cents': 0},
        'year': {'income_cents': 0, 'expense_cents': 0},
      });
      expect(financeInsight(l, d, oct10), 'Bu ay harcama yok');
      expect(d.spendCumulativeCents, isNull);
      expect(d.totalsByCurrency, isNull);
    });
  });

  group('the hero\'s chart and notes', () {
    Future<void> pump(WidgetTester tester, Map<String, dynamic> extra,
        {List<Account>? accounts}) async {
      _phone(tester);
      final json = {
        'currency': 'TRY',
        'subunit_to_unit': 100,
        'month': {'income_cents': 0, 'expense_cents': 49750, 'net_cents': -49750},
        'year': {'income_cents': 0, 'expense_cents': 174750},
        ...extra,
      };
      // A fresh scope each time: the overrides are read once.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(
        const FinanceScreen(),
        [
          financeDashboardProvider.overrideWith(
              (ref) => Fetched(FinanceDashboard.fromJson(json), _at)),
          accountsProvider
              .overrideWith((ref) => Fetched(accounts ?? _accounts(), _at)),
          subscriptionsProvider.overrideWith((ref) => Fetched(
              const SubscriptionsBundle(active: [], inactive: [], totals: []),
              _at)),
        ],
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('the pace line needs the cumulative series', (tester) async {
      await pump(tester, const {});
      expect(find.byType(PaceLine), findsNothing);
      await pump(tester, {
        'spend_cumulative_cents': [41250, 41250, 49750, 49750],
        'reference_cumulative_cents': List.filled(30, 100000),
      });
      expect(find.byType(PaceLine), findsOneWidget);
    });

    testWidgets('accounts in another currency: what the totals do with them',
        (tester) async {
      // An older server adds them unconverted…
      await pump(tester, const {});
      expect(find.text('Bu toplam farklı para birimlerini dönüştürmeden içerir'),
          findsOneWidget);
      // …WP-15 leaves them out (and says so with `totals_by_currency`).
      await pump(tester, {
        'totals_by_currency': [
          {'currency': 'TRY', 'subunit_to_unit': 100,
            'month': {'income_cents': 0, 'expense_cents': 49750, 'net_cents': -49750},
            'year': {'income_cents': 0, 'expense_cents': 174750}},
          {'currency': 'GAU', 'subunit_to_unit': 1,
            'month': {'income_cents': 2, 'expense_cents': 0, 'net_cents': 2},
            'year': {'income_cents': 2, 'expense_cents': 0}},
        ],
      });
      expect(find.text('Diğer para birimleri bu toplama dahil değil'),
          findsOneWidget);
      // One currency only: no note.
      await pump(tester, const {}, accounts: _accounts().skip(1).toList());
      expect(find.textContaining('para birim'), findsNothing);
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
          // The screen keeps the category list loaded for its filter.
          categoriesProvider
              .overrideWith((ref) => Fetched(const <TxCategory>[], _at)),
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
          categoriesProvider
              .overrideWith((ref) => Fetched(const <TxCategory>[], _at)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Henüz işlem yok'), findsOneWidget);
    });
  });

  group('İşlem formu: closing it without saving', () {
    /// Opens the form the way Finans, İşlemler and Hesap detayı do, and
    /// collects what it resolves to.
    Future<List<Transaction?>> openForm(
      WidgetTester tester, {
      Transaction? existing,
    }) async {
      // A large phone: the test font draws every glyph a full em wide, so
      // the kind pill needs more room than it does in Inter.
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final results = <Transaction?>[];
      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  results.add(
                    await openTransactionForm(context, existing: existing),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        [
          currentUserProvider.overrideWithValue(null),
          accountsProvider.overrideWith((ref) => Fetched(_accounts(), _at)),
          categoriesProvider
              .overrideWith((ref) => Fetched(const <TxCategory>[], _at)),
        ],
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TransactionFormScreen), findsOneWidget);
      return results;
    }

    testWidgets('the close button closes a new form: no result, no error',
        (tester) async {
      final results = await openForm(tester);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TransactionFormScreen), findsNothing);
      expect(results, [null], reason: 'closed without saving');
    });

    testWidgets('the close button closes an edit form, and the system back '
        'works afterwards as before', (tester) async {
      final results = await openForm(
        tester,
        existing: _feed(empty: false).items.first,
      );
      expect(find.text('İşlemi Düzenle'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TransactionFormScreen), findsNothing);
      expect(results, [null]);

      // The navigator is not left stuck: the form opens and the back button
      // closes it again.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionFormScreen), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(TransactionFormScreen), findsNothing);
      expect(results, [null, null]);
    });
  });
}
