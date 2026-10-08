import 'form_text.dart';
import 'json_read.dart';
import 'transaction.dart';

/// The kinds a finance category can have.
const categoryKinds = ['expense', 'income'];

/// One category and what a delete or a type change would touch
/// (GET /finance_categories/:id). The counts cover the category and its
/// subcategories.
class CategoryUsage {
  final TxCategory category;

  /// Subcategories, deleted with it.
  final int childrenCount;

  /// Transactions that would be left without a category.
  final int transactionsCount;

  /// Subscriptions that would lose their category.
  final int subscriptionsCount;

  /// Budgets deleted with it.
  final int budgetsCount;

  /// This category's own budget, if it has one.
  final int? budgetId;

  /// Whether its type (income/expense) can still change: only while it has
  /// no subcategories, transactions, budget or subscriptions.
  final bool kindEditable;

  const CategoryUsage({
    required this.category,
    required this.childrenCount,
    required this.transactionsCount,
    required this.subscriptionsCount,
    required this.budgetsCount,
    this.budgetId,
    required this.kindEditable,
  });

  factory CategoryUsage.fromJson(Map<String, dynamic> json) {
    final children = readInt(json['children_count']);
    final transactions = readInt(json['transactions_count']);
    final subscriptions = readInt(json['subscriptions_count']);
    final budgets = readInt(json['budgets_count']);
    return CategoryUsage(
      category: TxCategory.fromJson(json),
      childrenCount: children,
      transactionsCount: transactions,
      subscriptionsCount: subscriptions,
      budgetsCount: budgets,
      budgetId: readIntOrNull(json['budget_id']),
      kindEditable: readBoolOrNull(json['kind_editable']) ??
          (children + transactions + subscriptions + budgets == 0),
    );
  }

  /// Nothing would be touched by a delete but the category itself, so it
  /// can go with an undo instead of a confirmation.
  bool get unused =>
      childrenCount == 0 &&
      transactionsCount == 0 &&
      subscriptionsCount == 0 &&
      budgetsCount == 0;
}

/// What the category form sends (`POST /finance_categories`,
/// `PATCH /finance_categories/:id`).
///
/// [parentId] null makes it a top-level category; a subcategory's parent is
/// a top-level category of the same kind (the server checks it).
class CategoryInput {
  final String name;
  final String kind;
  final int? parentId;
  final String color;

  const CategoryInput({
    required this.name,
    required this.kind,
    this.parentId,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind,
        'parent_id': parentId,
        'color': color,
      };

  /// The body of an edit of [before]: only what changed — the name compared
  /// as the form sends it, trimmed ([formTextChanged]).
  Map<String, dynamic> changesFrom(TxCategory before) => {
        if (formTextChanged(name, before.name)) 'name': name.trim(),
        if (kind != before.kind) 'kind': kind,
        if (parentId != before.parentId) 'parent_id': parentId,
        if (color.toUpperCase() != before.color.toUpperCase()) 'color': color,
      };
}

/// The top-level categories of [kind] in [all], each followed by its
/// subcategories, in the server's order (position, then name) — how every
/// category list and picker shows them.
List<({TxCategory category, bool child})> categoryTree(
  Iterable<TxCategory> all, {
  String? kind,
}) {
  int byOrder(TxCategory a, TxCategory b) {
    final position = a.position.compareTo(b.position);
    return position != 0 ? position : a.name.compareTo(b.name);
  }

  final pool = [
    for (final c in all)
      if (kind == null || c.kind == kind) c,
  ];
  final roots = [
    for (final c in pool)
      if (c.parentId == null) c,
  ]..sort(byOrder);
  final rootIds = {for (final r in roots) r.id};
  final out = <({TxCategory category, bool child})>[];
  for (final root in roots) {
    out.add((category: root, child: false));
    final children = [
      for (final c in pool)
        if (c.parentId == root.id) c,
    ]..sort(byOrder);
    for (final child in children) {
      out.add((category: child, child: true));
    }
  }
  // A subcategory whose parent is not in the list (another kind, say, on an
  // older row) still shows, at the end.
  for (final c in pool) {
    if (c.parentId != null && !rootIds.contains(c.parentId)) {
      out.add((category: c, child: true));
    }
  }
  return out;
}
