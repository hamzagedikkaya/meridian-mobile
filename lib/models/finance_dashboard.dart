import 'account.dart';
import 'date_utils.dart';
import 'json_read.dart';
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
    final income = readInt(json['income_cents']);
    final expense = readInt(json['expense_cents']);
    return MonthTotals(
      incomeCents: income,
      expenseCents: expense,
      netCents: readIntOrNull(json['net_cents']) ?? (income - expense),
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
            .map((e) => readInt(e))
            .toList(),
        expenseCents: ((json['expense_cents'] as List?) ?? const [])
            .map((e) => readInt(e))
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
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        amountCents: readInt(json['amount_cents']),
        isRoot: readBool(json['is_root']),
      );
}

class PieSlice {
  final int id;
  final String name;
  final String color;
  final int amountCents;
  final List<PieBreakdown> breakdown;

  /// The month's expenses without a category (every quick-capture expense
  /// among them), so the slices add up to the month's spending. Its id is
  /// 0, never a category's.
  final bool uncategorized;

  const PieSlice({
    required this.id,
    required this.name,
    required this.color,
    required this.amountCents,
    required this.breakdown,
    this.uncategorized = false,
  });

  factory PieSlice.fromJson(Map<String, dynamic> json) {
    final id = readIntOrNull(json['id']) ?? 0;
    return PieSlice(
      id: id,
      name: (json['name'] as String?) ?? '',
      color: (json['color'] as String?) ?? '#C9A45C',
      amountCents: readInt(json['amount_cents']),
      breakdown: ((json['breakdown'] as List?) ?? const [])
          .map((e) => PieBreakdown.fromJson(e as Map<String, dynamic>))
          .toList(),
      uncategorized: readBoolOrNull(json['uncategorized']) ?? id == 0,
    );
  }
}

/// A budget with its month-to-date spend (the budget object of
/// GET /budgets, its create/update answers and the dashboard's `budgets`).
/// Amounts are in the user's currency.
class BudgetStatus {
  /// The budget's id; 0 from a server that predates it.
  final int id;
  final int categoryId;
  final String categoryName;

  /// The colour to draw: the budget's own, else its category's.
  final String color;

  /// The budget's own colour, null when it follows its category.
  final String? customColor;
  final int limitCents;
  final int spentCents;
  final int remainingCents;

  /// How far spending is over the limit; 0 when it is not.
  final int overByCents;
  final double percentUsed;

  /// [percentUsed] capped at 100: the width of the bar.
  final double barPercent;
  final double pacePercent;
  final int projectedCents;
  final String state;

  const BudgetStatus({
    this.id = 0,
    required this.categoryId,
    required this.categoryName,
    required this.color,
    this.customColor,
    required this.limitCents,
    required this.spentCents,
    required this.remainingCents,
    this.overByCents = 0,
    required this.percentUsed,
    double? barPercent,
    required this.pacePercent,
    required this.projectedCents,
    required this.state,
  }) : barPercent = barPercent ?? (percentUsed > 100 ? 100 : percentUsed);

  factory BudgetStatus.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] as Map<String, dynamic>?) ?? const {};
    final limit = readInt(json['limit_cents']);
    final spent = readInt(json['spent_cents']);
    final percent = readDouble(json['percent_used']);
    return BudgetStatus(
      id: readIntOrNull(json['id']) ?? 0,
      categoryId: readIntOrNull(json['finance_category_id']) ??
          readInt(category['id']),
      categoryName: (category['name'] as String?) ?? '',
      color: (json['color'] as String?) ?? '#C9A45C',
      customColor: switch (json['custom_color']) {
        final String c when c.isNotEmpty => c,
        _ => null,
      },
      limitCents: limit,
      spentCents: spent,
      remainingCents: readInt(json['remaining_cents']),
      overByCents: readIntOrNull(json['over_by_cents']) ??
          (spent > limit ? spent - limit : 0),
      percentUsed: percent,
      barPercent: readDoubleOrNull(json['bar_percent']),
      pacePercent: readDouble(json['pace_percent']),
      projectedCents: readInt(json['projected_cents']),
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
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        amountCents: readInt(json['amount_cents']),
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
        subunitToUnit: readInt(json['subunit_to_unit'], fallback: 100),
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
