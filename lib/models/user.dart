class User {
  final int id;
  final String displayName;
  final String initials;
  final String email;
  final String currency;
  final int subunitToUnit;
  final String locale;
  final String themePreference;

  const User({
    required this.id,
    required this.displayName,
    required this.initials,
    required this.email,
    required this.currency,
    required this.subunitToUnit,
    required this.locale,
    required this.themePreference,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        displayName: (json['display_name'] ?? json['name']) as String,
        initials: (json['initials'] as String?) ?? '',
        email: json['email'] as String,
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: (json['subunit_to_unit'] as int?) ?? 100,
        locale: (json['locale'] as String?) ?? 'tr',
        themePreference: (json['theme_preference'] as String?) ?? 'system',
      );
}
