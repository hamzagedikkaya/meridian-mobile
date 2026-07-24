import 'account.dart';
import 'date_utils.dart';

/// A finance category (shared shape between /finance_categories and the
/// `category` embedded in a transaction — the real payload includes kind +
/// position on both).
class TxCategory {
  final int id;
  final String name;
  final String kind;
  final String color;
  final int? parentId;
  final int position;

  const TxCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.color,
    this.parentId,
    required this.position,
  });

  factory TxCategory.fromJson(Map<String, dynamic> json) => TxCategory(
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        kind: (json['kind'] as String?) ?? 'expense',
        color: (json['color'] as String?) ?? '#B8860B',
        parentId: (json['parent_id'] as num?)?.toInt(),
        position: (json['position'] as num?)?.toInt() ?? 0,
      );
}

class Transaction {
  final int id;
  final String kind;
  final int amountCents;
  final DateTime date;
  final String? description;
  final String? note;
  final AccountRef account;
  final TxCategory? category;
  final AccountRef? relatedAccount;

  const Transaction({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.date,
    this.description,
    this.note,
    required this.account,
    this.category,
    this.relatedAccount,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json['id'] as int,
        kind: (json['kind'] as String?) ?? 'expense',
        amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
        date: DateTime.parse(json['date'] as String),
        description: json['description'] as String?,
        note: json['note'] as String?,
        account:
            AccountRef.fromJson(json['account'] as Map<String, dynamic>),
        category: json['category'] == null
            ? null
            : TxCategory.fromJson(json['category'] as Map<String, dynamic>),
        relatedAccount: json['related_account'] == null
            ? null
            : AccountRef.fromJson(
                json['related_account'] as Map<String, dynamic>),
      );
}

class TransactionMeta {
  final int totalCount;
  final int page;
  final int pageLimit;
  final int filteredIncomeCents;
  final int filteredExpenseCents;

  const TransactionMeta({
    required this.totalCount,
    required this.page,
    required this.pageLimit,
    required this.filteredIncomeCents,
    required this.filteredExpenseCents,
  });

  factory TransactionMeta.fromJson(Map<String, dynamic> json) => TransactionMeta(
        totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
        page: (json['page'] as num?)?.toInt() ?? 1,
        pageLimit: (json['page_limit'] as num?)?.toInt() ?? 50,
        filteredIncomeCents:
            (json['filtered_income_cents'] as num?)?.toInt() ?? 0,
        filteredExpenseCents:
            (json['filtered_expense_cents'] as num?)?.toInt() ?? 0,
      );
}

class TransactionsPage {
  final List<Transaction> items;
  final TransactionMeta meta;

  const TransactionsPage({required this.items, required this.meta});

  factory TransactionsPage.fromJson(Map<String, dynamic> json) =>
      TransactionsPage(
        items: ((json['transactions'] as List?) ?? const [])
            .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
            .toList(),
        meta: TransactionMeta.fromJson(
            (json['meta'] as Map<String, dynamic>?) ?? const {}),
      );
}

/// Create/update body — client sends `amount_cents` already multiplied by the
/// account's subunit.
class TransactionInput {
  final String kind;
  final int amountCents;
  final DateTime date;
  final String? description;
  final String? note;
  final int accountId;
  final int? financeCategoryId;
  final int? relatedAccountId;

  const TransactionInput({
    required this.kind,
    required this.amountCents,
    required this.date,
    this.description,
    this.note,
    required this.accountId,
    this.financeCategoryId,
    this.relatedAccountId,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'amount_cents': amountCents,
        'date': isoDate(date),
        'description': description,
        'note': note,
        'account_id': accountId,
        'finance_category_id': financeCategoryId,
        'related_account_id': relatedAccountId,
      };
}
