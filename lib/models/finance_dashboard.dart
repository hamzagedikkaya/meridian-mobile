import 'account.dart';
import 'date_utils.dart';
import 'transaction.dart';

/// Income/expense/net for a period. Reused for both `month` and `year`
/// (the real `year` block omits net → computed as income − expense).
class MonthTotals {
  final int incomeCents;
  final int expenseCents;
  final int netCents;

  const MonthTotals({
    required this.incomeCents,
    required this.expenseCents,
    required this.netCents,
  });

  factory MonthTotals.fromJson(Map<String, dynamic> json) {
    final income = (json['income_cents'] as num?)?.toInt() ?? 0;
    final expense = (json['expense_cents'] as num?)?.toInt() ?? 0;
    return MonthTotals(
      incomeCents: income,
      expenseCents: expense,
      netCents: (json['net_cents'] as num?)?.toInt() ?? (income - expense),
    );
  }
}

class SixMonthSeries {
  final List<String> labels;
  final List<int> incomeCents;
  final List<int> expenseCents;

  const SixMonthSeries({
    required this.labels,
    required this.incomeCents,
    required this.expenseCents,
  });

  factory SixMonthSeries.fromJson(Map<String, dynamic> json) => SixMonthSeries(
        labels: ((json['labels'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        incomeCents: ((json['income_cents'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        expenseCents: ((json['expense_cents'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
      );
}

class PieBreakdown {
  final int id;
  final String name;
  final int amountCents;
  final bool isRoot;

  const PieBreakdown({
    required this.id,
    required this.name,
    required this.amountCents,
    required this.isRoot,
  });

  factory PieBreakdown.fromJson(Map<String, dynamic> json) => PieBreakdown(
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
        isRoot: (json['is_root'] as bool?) ?? false,
      );
}

class PieSlice {
  final int id;
  final String name;
  final String color;
  final int amountCents;
  final List<PieBreakdown> breakdown;

  const PieSlice({
    required this.id,
    required this.name,
    required this.color,
    required this.amountCents,
    required this.breakdown,
  });

  factory PieSlice.fromJson(Map<String, dynamic> json) => PieSlice(
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        color: (json['color'] as String?) ?? '#C9A45C',
        amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
        breakdown: ((json['breakdown'] as List?) ?? const [])
            .map((e) => PieBreakdown.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class BudgetStatus {
  final int categoryId;
  final String categoryName;
  final String color;
  final int limitCents;
  final int spentCents;
  final int remainingCents;
  final double percentUsed;
  final double pacePercent;
  final int projectedCents;
  final String state;

  const BudgetStatus({
    required this.categoryId,
    required this.categoryName,
    required this.color,
    required this.limitCents,
    required this.spentCents,
    required this.remainingCents,
    required this.percentUsed,
    required this.pacePercent,
    required this.projectedCents,
    required this.state,
  });

  factory BudgetStatus.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] as Map<String, dynamic>?) ?? const {};
    return BudgetStatus(
      categoryId: (category['id'] as num?)?.toInt() ?? 0,
      categoryName: (category['name'] as String?) ?? '',
      color: (json['color'] as String?) ?? '#C9A45C',
      limitCents: (json['limit_cents'] as num?)?.toInt() ?? 0,
      spentCents: (json['spent_cents'] as num?)?.toInt() ?? 0,
      remainingCents: (json['remaining_cents'] as num?)?.toInt() ?? 0,
      percentUsed: (json['percent_used'] as num?)?.toDouble() ?? 0,
      pacePercent: (json['pace_percent'] as num?)?.toDouble() ?? 0,
      projectedCents: (json['projected_cents'] as num?)?.toInt() ?? 0,
      state: (json['state'] as String?) ?? 'under',
    );
  }
}

class SubscriptionItem {
  final int id;
  final String name;
  final int amountCents;
  final String frequency;
  final DateTime? nextChargeOn;
  final AccountRef account;

  const SubscriptionItem({
    required this.id,
    required this.name,
    required this.amountCents,
    required this.frequency,
    this.nextChargeOn,
    required this.account,
  });

  factory SubscriptionItem.fromJson(Map<String, dynamic> json) =>
      SubscriptionItem(
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
        frequency: (json['frequency'] as String?) ?? 'monthly',
        nextChargeOn: parseDateTime(json['next_charge_on']),
        account: AccountRef.fromJson(json['account'] as Map<String, dynamic>),
      );
}

class FinanceDashboard {
  final String currency;
  final int subunitToUnit;
  final MonthTotals month;
  final MonthTotals year;
  final SixMonthSeries sixMonthSeries;
  final List<PieSlice> pie;
  final List<BudgetStatus> budgets;
  final List<SubscriptionItem> upcomingSubscriptions;
  final List<Transaction> recentTransactions;

  const FinanceDashboard({
    required this.currency,
    required this.subunitToUnit,
    required this.month,
    required this.year,
    required this.sixMonthSeries,
    required this.pie,
    required this.budgets,
    required this.upcomingSubscriptions,
    required this.recentTransactions,
  });

  factory FinanceDashboard.fromJson(Map<String, dynamic> json) =>
      FinanceDashboard(
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: (json['subunit_to_unit'] as num?)?.toInt() ?? 100,
        month: MonthTotals.fromJson(
            (json['month'] as Map<String, dynamic>?) ?? const {}),
        year: MonthTotals.fromJson(
            (json['year'] as Map<String, dynamic>?) ?? const {}),
        sixMonthSeries: SixMonthSeries.fromJson(
            (json['six_month_series'] as Map<String, dynamic>?) ?? const {}),
        pie: ((json['pie'] as List?) ?? const [])
            .map((e) => PieSlice.fromJson(e as Map<String, dynamic>))
            .toList(),
        budgets: ((json['budgets'] as List?) ?? const [])
            .map((e) => BudgetStatus.fromJson(e as Map<String, dynamic>))
            .toList(),
        upcomingSubscriptions:
            ((json['upcoming_subscriptions'] as List?) ?? const [])
                .map((e) => SubscriptionItem.fromJson(e as Map<String, dynamic>))
                .toList(),
        recentTransactions: ((json['recent_transactions'] as List?) ?? const [])
            .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
