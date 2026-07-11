class Account {
  final int id;
  final String name;
  final String accountType;
  final String currency;
  final int subunitToUnit;
  final String color;
  final int balanceCents;

  Account({
    required this.id,
    required this.name,
    required this.accountType,
    required this.currency,
    required this.subunitToUnit,
    required this.color,
    required this.balanceCents,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as int,
      name: json['name'] as String,
      accountType: json['account_type'] as String,
      currency: json['currency'] as String,
      subunitToUnit: (json['subunit_to_unit'] as int?) ?? 100,
      color: (json['color'] as String?) ?? '#B8860B',
      balanceCents: json['balance_cents'] as int,
    );
  }

  String get formattedBalance {
    final major = balanceCents / subunitToUnit;
    final decimals = subunitToUnit == 1 ? 0 : 2;
    return '${major.toStringAsFixed(decimals)} $currency';
  }
}
