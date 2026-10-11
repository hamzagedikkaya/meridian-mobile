@Tags(['golden'])
/// Abonelikler, Kategoriler and the budget sheet (design-analysis §7.8,
/// §7.9).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-10.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/budget.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/models/subscription.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/ui/screens/finance/budget_sheet.dart';
import 'package:meridian_mobile/ui/screens/finance/categories_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/subscriptions_screen.dart';

import 'golden_harness.dart';

const _en = <String, String>{
  'Maaş hesabı': 'Salary account',
  'Kredi kartı': 'Credit card',
  'Kira': 'Rent',
  'Market': 'Groceries',
  'Atıştırmalık': 'Snacks',
  'Faturalar': 'Bills',
  'Ulaşım': 'Transport',
  'Eğlence': 'Entertainment',
  'Diğer': 'Other',
  'Maaş': 'Salary',
  'Serbest gelir': 'Freelance',
  'Spor salonu': 'Gym',
  'Bulut depolama': 'Cloud storage',
  'Gazete': 'Newspaper',
  'Elektrik': 'Electricity',
};

String _fx(String tr) => fx(tr, _en);

// --- Fixtures -----------------------------------------------------------------

Map<String, dynamic> _acct(int id, String name, String color) => {
      'id': id,
      'name': _fx(name),
      'color': color,
      'currency': 'TRY',
      'subunit_to_unit': 100,
    };

Map<String, dynamic> _cat(int id, String name, String color,
        {String kind = 'expense', int? parent, int position = 0}) =>
    {
      'id': id,
      'name': _fx(name),
      'kind': kind,
      'color': color,
      'parent_id': parent,
      'position': position,
    };

Map<String, dynamic> _sub(
  int id,
  String name, {
  required int amount,
  String frequency = 'monthly',
  DateTime? next,
  bool active = true,
  String color = '#B8860B',
  Map<String, dynamic>? category,
}) =>
    {
      'id': id,
      'name': _fx(name),
      'vendor': null,
      'amount_cents': amount,
      'frequency': frequency,
      'next_charge_on': next == null ? null : ymd(next),
      'start_date': '2026-01-15',
      'end_date': null,
      'active': active,
      'color': color,
      'note': null,
      'monthly_amount_cents': frequency == 'yearly' ? amount ~/ 12 : amount,
      'yearly_amount_cents': frequency == 'yearly' ? amount : amount * 12,
      'account': _acct(2, 'Maaş hesabı', '#6B8FA0'),
      'category': category,
    };

SubscriptionsBundle _subscriptions() => SubscriptionsBundle.fromJson({
      'active': [
        _sub(81, 'Elektrik', amount: 84250, next: daysAgo(3),
            category: _cat(67, 'Faturalar', '#6B8FA0')),
        _sub(82, 'Spotify', amount: 5999, next: daysAhead(4),
            color: '#1DB954'),
        _sub(83, 'Netflix', amount: 22999, next: daysAhead(9),
            color: '#B85450'),
        _sub(84, 'Spor salonu', amount: 150000, next: daysAhead(20),
            category: _cat(63, 'Eğlence', '#8B5A00')),
        _sub(85, 'Bulut depolama', amount: 119999, frequency: 'yearly',
            next: DateTime(2027, 3, 12), color: '#6B8E5A'),
      ],
      'inactive': [
        _sub(86, 'Gazete', amount: 9900, active: false),
      ],
      'totals': [
        {'currency': 'TRY', 'subunit_to_unit': 100, 'monthly_cents': 273246, 'yearly_cents': 3278952},
      ],
    });

List<TxCategory> _categories() => [
      for (final json in [
        _cat(61, 'Market', '#D4915A', position: 1),
        _cat(68, 'Atıştırmalık', '#C9A227', parent: 61),
        _cat(70, 'Kira', '#6B8FA0', position: 2),
        _cat(67, 'Faturalar', '#7D8FB8', position: 3),
        _cat(62, 'Ulaşım', '#B85450', position: 4),
        _cat(63, 'Eğlence', '#8B5A00', position: 5),
        _cat(69, 'Diğer', '#A09B8E', position: 6),
        _cat(60, 'Maaş', '#6B8E5A', kind: 'income', position: 1),
        _cat(66, 'Serbest gelir', '#5A8E8B', kind: 'income', position: 2),
      ])
        TxCategory.fromJson(json),
    ];

FinanceDashboard _dashboard() => FinanceDashboard.fromJson({
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'month': {'income_cents': 5780000, 'expense_cents': 3320000, 'net_cents': 2460000},
      'year': {'income_cents': 68400000, 'expense_cents': 47200000},
      'six_month_series': {'labels': [], 'income_cents': [], 'expense_cents': []},
      'pie': [
        {'id': 70, 'name': _fx('Kira'), 'color': '#6B8FA0', 'amount_cents': 1800000, 'breakdown': const []},
        {'id': 61, 'name': _fx('Market'), 'color': '#D4915A', 'amount_cents': 1240000, 'breakdown': const []},
        {'id': 62, 'name': _fx('Ulaşım'), 'color': '#B85450', 'amount_cents': 480000, 'breakdown': const []},
        {'id': 63, 'name': _fx('Eğlence'), 'color': '#8B5A00', 'amount_cents': 62050, 'breakdown': const []},
      ],
      'budgets': const [],
      'upcoming_subscriptions': const [],
      'recent_transactions': const [],
    });

BudgetsBundle _budgets() => BudgetsBundle.fromJson({
      'currency': 'TRY',
      'subunit_to_unit': 100,
      'as_of': ymd(goldenNow),
      'budgets': const [],
      'budgetable_category_ids': [61, 70, 67, 62, 63],
    });

/// A page under the budget sheet: opens it once its first frame is up.
class _BudgetLauncher extends StatefulWidget {
  const _BudgetLauncher();

  @override
  State<_BudgetLauncher> createState() => _BudgetLauncherState();
}

class _BudgetLauncherState extends State<_BudgetLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => showBudgetSheet(context));
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

void main() {
  setUpGoldens();

  goldenScreen('subscriptions', variants: GoldenVariant.withLargeText,
      (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const SubscriptionsScreen(),
      [
        subscriptionsProvider
            .overrideWith((ref) => Fetched(_subscriptions(), goldenNow)),
      ],
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('categories', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const CategoriesScreen(),
      [
        categoriesProvider
            .overrideWith((ref) => Fetched(_categories(), goldenNow)),
        financeDashboardProvider
            .overrideWith((ref) => Fetched(_dashboard(), goldenNow)),
      ],
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('budget_sheet', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const _BudgetLauncher(),
      [
        budgetsProvider.overrideWith((ref) => Fetched(_budgets(), goldenNow)),
        categoriesProvider
            .overrideWith((ref) => Fetched(_categories(), goldenNow)),
      ],
    ));
    await tester.pumpAndSettle();
  });
}
