import 'json_read.dart';

/// One choice of the account form's currency picker (GET /currencies).
class CurrencyOption {
  /// The ISO code to send as `currency` (`TRY`, `GAU`, …).
  final String code;

  /// The server's name for it, in the account's language.
  final String name;
  final String symbol;

  /// Minor units per unit: what typed amounts are multiplied by.
  final int subunitToUnit;

  const CurrencyOption({
    required this.code,
    required this.name,
    required this.symbol,
    required this.subunitToUnit,
  });

  factory CurrencyOption.fromJson(Map<String, dynamic> json) {
    final code = ((json['code'] as String?) ?? '').toUpperCase();
    return CurrencyOption(
      code: code,
      name: (json['name'] as String?) ?? code,
      symbol: (json['symbol'] as String?) ?? code,
      subunitToUnit: readInt(json['subunit_to_unit'], fallback: 100),
    );
  }

  /// The currencies a new account can always be opened in — what the server
  /// offers (`CurrenciesController::OFFERED`) — for when its list cannot be
  /// loaded.
  static const offered = [
    CurrencyOption(code: 'TRY', name: 'TRY', symbol: '₺', subunitToUnit: 100),
    CurrencyOption(code: 'USD', name: 'USD', symbol: '\$', subunitToUnit: 100),
    CurrencyOption(code: 'EUR', name: 'EUR', symbol: '€', subunitToUnit: 100),
    CurrencyOption(code: 'GBP', name: 'GBP', symbol: '£', subunitToUnit: 100),
    CurrencyOption(code: 'GAU', name: 'GAU', symbol: 'gr', subunitToUnit: 1),
  ];
}

/// GET /currencies: the offered currencies, then any other one the user
/// already uses, and the one a new account starts in (the user's).
class CurrenciesBundle {
  final List<CurrencyOption> currencies;
  final String defaultCurrency;

  const CurrenciesBundle({
    required this.currencies,
    required this.defaultCurrency,
  });

  factory CurrenciesBundle.fromJson(Map<String, dynamic> json) =>
      CurrenciesBundle(
        currencies: [
          for (final raw in (json['currencies'] as List?) ?? const [])
            if (raw is Map<String, dynamic>) CurrencyOption.fromJson(raw),
        ],
        defaultCurrency:
            ((json['default_currency'] as String?) ?? 'TRY').toUpperCase(),
      );

  /// [code]'s entry, if the list has it.
  CurrencyOption? byCode(String code) {
    final upper = code.toUpperCase();
    for (final currency in currencies) {
      if (currency.code == upper) return currency;
    }
    return null;
  }
}
