import 'date_utils.dart';
import 'json_read.dart';

/// The account types the server takes (`account_type`), in the order the
/// form offers them.
const accountTypes = ['cash', 'bank', 'credit_card', 'savings', 'crypto'];

/// A full account (GET /accounts). Money stays in *_cents; format per
/// [subunitToUnit] — GAU uses 1 ("412 gr"), TRY uses 100.
class Account {
  final int id;
  final String name;
  final String accountType;
  final String currency;
  final int subunitToUnit;
  final String color;
  final int initialBalanceCents;
  final int balanceCents;
  final bool archived;

  /// When it was archived; null for an active account.
  final DateTime? archivedAt;

  const Account({
    required this.id,
    required this.name,
    required this.accountType,
    required this.currency,
    required this.subunitToUnit,
    required this.color,
    required this.initialBalanceCents,
    required this.balanceCents,
    required this.archived,
    this.archivedAt,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        accountType: (json['account_type'] as String?) ?? 'cash',
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: readInt(json['subunit_to_unit'], fallback: 100),
        color: (json['color'] as String?) ?? '#B8860B',
        initialBalanceCents: readInt(json['initial_balance_cents']),
        balanceCents: readInt(json['balance_cents']),
        archived: readBool(json['archived']),
        archivedAt: parseDateTime(json['archived_at']),
      );
}

/// One account with what its edit and delete screens need to know
/// (GET /accounts/:id): what is recorded on it, and so whether it can be
/// deleted and whether its currency can still change.
class AccountDetail {
  final Account account;

  /// Transactions stored on the account, every kind.
  final int transactionsCount;

  /// Transfers on other accounts into this one.
  final int incomingTransfersCount;

  /// Subscriptions charged to it, active or paused: a delete takes them too.
  final int subscriptionsCount;

  /// Goals that track its balance: a delete unlinks them.
  final int linkedGoalsCount;

  /// No transaction touches it, so the server deletes it (otherwise it can
  /// only be archived).
  final bool deletable;

  /// Nothing is recorded in its currency yet, so the currency can change.
  final bool currencyEditable;

  const AccountDetail({
    required this.account,
    required this.transactionsCount,
    required this.incomingTransfersCount,
    required this.subscriptionsCount,
    required this.linkedGoalsCount,
    required this.deletable,
    required this.currencyEditable,
  });

  factory AccountDetail.fromJson(Map<String, dynamic> json) {
    final transactions = readInt(json['transactions_count']);
    final incoming = readInt(json['incoming_transfers_count']);
    final subscriptions = readInt(json['subscriptions_count']);
    final deletable =
        readBoolOrNull(json['deletable']) ?? (transactions + incoming == 0);
    return AccountDetail(
      account: Account.fromJson(json),
      transactionsCount: transactions,
      incomingTransfersCount: incoming,
      subscriptionsCount: subscriptions,
      linkedGoalsCount: readInt(json['linked_goals_count']),
      deletable: deletable,
      currencyEditable: readBoolOrNull(json['currency_editable']) ??
          (deletable && subscriptions == 0),
    );
  }
}

/// What the account form sends (`POST /accounts`, `PATCH /accounts/:id`).
///
/// The opening balance is in minor units of [currency] and may be negative
/// (a card's debt): a stored starting point, not a transaction.
class AccountInput {
  final String name;
  final String accountType;

  /// Null on a create leaves it to the server: the user's currency.
  final String? currency;
  final int initialBalanceCents;
  final String color;

  const AccountInput({
    required this.name,
    required this.accountType,
    this.currency,
    this.initialBalanceCents = 0,
    required this.color,
  });

  /// The body of a create: every field.
  Map<String, dynamic> toJson() => {
        'name': name,
        'account_type': accountType,
        if (currency != null) 'currency': currency,
        'initial_balance_cents': initialBalanceCents,
        'color': color,
      };

  /// The body of an edit of [before]: only what changed, so an edit never
  /// rewrites a field the form did not touch. A currency change carries the
  /// opening balance with it, re-read in the new currency (contract: the
  /// server asks for both in one request).
  Map<String, dynamic> changesFrom(Account before) {
    final currencyChanged = currency != null &&
        currency!.toUpperCase() != before.currency.toUpperCase();
    return {
      if (name != before.name) 'name': name,
      if (accountType != before.accountType) 'account_type': accountType,
      if (currencyChanged) 'currency': currency,
      if (currencyChanged || initialBalanceCents != before.initialBalanceCents)
        'initial_balance_cents': initialBalanceCents,
      if (color.toUpperCase() != before.color.toUpperCase()) 'color': color,
    };
  }
}

/// Lightweight account embedded in transactions/subscriptions.
/// `related_account` only guarantees {id, name}; currency/subunit fall back.
class AccountRef {
  final int id;
  final String name;
  final String? color;
  final String currency;
  final int subunitToUnit;

  const AccountRef({
    required this.id,
    required this.name,
    this.color,
    required this.currency,
    required this.subunitToUnit,
  });

  factory AccountRef.fromJson(Map<String, dynamic> json) => AccountRef(
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        color: json['color'] as String?,
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: readInt(json['subunit_to_unit'], fallback: 100),
      );
}
