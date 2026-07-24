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
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        accountType: (json['account_type'] as String?) ?? 'cash',
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: (json['subunit_to_unit'] as num?)?.toInt() ?? 100,
        color: (json['color'] as String?) ?? '#B8860B',
        initialBalanceCents: (json['initial_balance_cents'] as num?)?.toInt() ?? 0,
        balanceCents: (json['balance_cents'] as num?)?.toInt() ?? 0,
        archived: (json['archived'] as bool?) ?? false,
      );
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
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        color: json['color'] as String?,
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: (json['subunit_to_unit'] as num?)?.toInt() ?? 100,
      );
}
