import 'account.dart';
import 'date_utils.dart';
import 'form_text.dart';
import 'json_read.dart';

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
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        kind: (json['kind'] as String?) ?? 'expense',
        color: (json['color'] as String?) ?? '#B8860B',
        parentId: readIntOrNull(json['parent_id']),
        position: readInt(json['position']),
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
        id: readId(json['id']),
        kind: (json['kind'] as String?) ?? 'expense',
        amountCents: readInt(json['amount_cents']),
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

/// The other row of a linked pair (GET /transactions/:id). The web can save
/// an expense on one account together with an income on another — buying
/// gold with cash — and the second row is the first one's child.
class LinkedTransaction {
  final int id;
  final String kind;
  final int amountCents;
  final DateTime date;
  final String? description;
  final AccountRef account;

  /// `child`: it is deleted together with the transaction it is linked to.
  /// `parent`: it stays when that one is deleted.
  final String relation;

  const LinkedTransaction({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.date,
    this.description,
    required this.account,
    required this.relation,
  });

  factory LinkedTransaction.fromJson(Map<String, dynamic> json) =>
      LinkedTransaction(
        id: readId(json['id']),
        kind: (json['kind'] as String?) ?? 'expense',
        amountCents: readInt(json['amount_cents']),
        date: parseDateTime(json['date']) ?? DateTime(1970),
        description: json['description'] as String?,
        account: AccountRef.fromJson(
            (json['account'] as Map<String, dynamic>?) ?? const {'id': 0}),
        relation: (json['relation'] as String?) ?? 'parent',
      );

  /// Deleting the transaction it is linked to deletes this one too.
  bool get isChild => relation == 'child';
}

/// One transaction as GET /transactions/:id answers it: the row, and the
/// other row of its linked pair when it has one.
class TransactionDetail {
  final Transaction transaction;

  /// Set when this transaction is the child of a pair.
  final int? parentTransactionId;
  final LinkedTransaction? linked;

  const TransactionDetail({
    required this.transaction,
    this.parentTransactionId,
    this.linked,
  });

  factory TransactionDetail.fromJson(Map<String, dynamic> json) =>
      TransactionDetail(
        transaction: Transaction.fromJson(json),
        parentTransactionId: readIntOrNull(json['parent_transaction_id']),
        linked: json['linked'] is Map<String, dynamic>
            ? LinkedTransaction.fromJson(json['linked'] as Map<String, dynamic>)
            : null,
      );

  /// Deleting this transaction also deletes [linked] (the server's
  /// `dependent: :destroy`), which an undo could not bring back.
  bool get deletesLinked => linked?.isChild ?? false;
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
        totalCount: readInt(json['total_count']),
        page: readInt(json['page'], fallback: 1),
        pageLimit: readInt(json['page_limit'], fallback: 50),
        filteredIncomeCents: readInt(json['filtered_income_cents']),
        filteredExpenseCents: readInt(json['filtered_expense_cents']),
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
///
/// A null [financeCategoryId] is an uncategorized income or expense
/// ("Kategorisiz"); a transfer has none and names [relatedAccountId].
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

  /// The body of a create. The optional fields are left out when empty,
  /// which the server reads as none (an uncategorized row, no note).
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'amount_cents': amountCents,
        'date': isoDate(date),
        'account_id': accountId,
        if (description != null) 'description': description,
        if (note != null) 'note': note,
        if (financeCategoryId != null) 'finance_category_id': financeCategoryId,
        if (relatedAccountId != null) 'related_account_id': relatedAccountId,
      };

  /// The body of an edit of [before]: only the keys that changed, a cleared
  /// field as null. So an edit never touches what the form did not change —
  /// a note written on the web survives an edit of the amount. Text is
  /// compared as the form sends it ([formTextChanged]): a note the web saved
  /// with a trailing newline is not rewritten by a save that left it alone.
  Map<String, dynamic> changesFrom(Transaction before) {
    final day = isoDate(date);
    return {
      if (kind != before.kind) 'kind': kind,
      if (amountCents != before.amountCents) 'amount_cents': amountCents,
      if (day != isoDate(before.date)) 'date': day,
      if (formTextChanged(description, before.description))
        'description': asFormText(description),
      if (formTextChanged(note, before.note)) 'note': asFormText(note),
      if (accountId != before.account.id) 'account_id': accountId,
      if (financeCategoryId != before.category?.id)
        'finance_category_id': financeCategoryId,
      if (relatedAccountId != before.relatedAccount?.id)
        'related_account_id': relatedAccountId,
    };
  }
}
