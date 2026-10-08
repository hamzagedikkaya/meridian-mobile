import 'date_utils.dart';
import 'finance_dashboard.dart';
import 'json_read.dart';

/// GET /budgets: every budget with its month-to-date spend, and the
/// categories a new budget can go on.
class BudgetsBundle {
  /// The user's currency: budgets are kept in it.
  final String currency;
  final int subunitToUnit;

  /// The day the spend is counted up to (the user's today).
  final DateTime? asOf;
  final List<BudgetStatus> budgets;

  /// The expense top-level categories without a budget, in category order:
  /// what the create sheet offers.
  final List<int> budgetableCategoryIds;

  const BudgetsBundle({
    required this.currency,
    required this.subunitToUnit,
    this.asOf,
    required this.budgets,
    required this.budgetableCategoryIds,
  });

  factory BudgetsBundle.fromJson(Map<String, dynamic> json) => BudgetsBundle(
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: readInt(json['subunit_to_unit'], fallback: 100),
        asOf: parseDateTime(json['as_of']),
        budgets: [
          for (final raw in (json['budgets'] as List?) ?? const [])
            if (raw is Map<String, dynamic>) BudgetStatus.fromJson(raw),
        ],
        budgetableCategoryIds: [
          for (final raw in (json['budgetable_category_ids'] as List?) ??
              const [])
            ?readIntOrNull(raw),
        ],
      );
}

/// What the budget sheet sends (`POST /budgets`, `PATCH /budgets/:id`):
/// a monthly limit above 0 in minor units of the user's currency, on an
/// expense top-level category that has no budget yet.
class BudgetInput {
  final int categoryId;
  final int monthlyLimitCents;

  const BudgetInput({
    required this.categoryId,
    required this.monthlyLimitCents,
  });

  Map<String, dynamic> toJson() => {
        'finance_category_id': categoryId,
        'monthly_limit_cents': monthlyLimitCents,
      };

  /// The body of an edit of [before]: only what changed.
  Map<String, dynamic> changesFrom(BudgetStatus before) => {
        if (categoryId != before.categoryId) 'finance_category_id': categoryId,
        if (monthlyLimitCents != before.limitCents)
          'monthly_limit_cents': monthlyLimitCents,
      };
}
