import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formats.dart';
import '../../../core/session.dart';
import '../../../data/providers.dart' show TxFilters;
import '../../../models/account.dart';
import '../../../models/date_utils.dart';
import '../../../theme/entity_color.dart';

/// The İşlemler route with [filters] in its query — how Finance drills
/// into a category, the uncategorized spending or a month.
String transactionsLocation(TxFilters filters) {
  final query = <String, String>{
    if (filters.kind != null) 'kind': filters.kind!,
    if (filters.accountId != null) 'account': '${filters.accountId}',
    if (filters.uncategorized)
      'category': 'none'
    else if (filters.categoryId != null)
      'category': '${filters.categoryId}',
    if (filters.from != null) 'from': isoDate(filters.from!),
    if (filters.to != null) 'to': isoDate(filters.to!),
  };
  return Uri(path: '/finance/transactions', queryParameters: query.isEmpty ? null : query)
      .toString();
}

/// The filters [transactionsLocation] wrote into a query; what cannot be
/// read is left out.
TxFilters filtersFromQuery(Map<String, String> query) {
  final category = query['category'];
  final from = DateTime.tryParse(query['from'] ?? '');
  final to = DateTime.tryParse(query['to'] ?? '');
  final kind = query['kind'];
  return TxFilters(
    kind: const ['income', 'expense', 'transfer'].contains(kind) ? kind : null,
    accountId: int.tryParse(query['account'] ?? ''),
    categoryId: category == 'none' ? null : int.tryParse(category ?? ''),
    uncategorized: category == 'none',
    // Both or neither: the server applies a range only with both ends.
    from: from != null && to != null ? dateOnly(from) : null,
    to: from != null && to != null ? dateOnly(to) : null,
  );
}

/// This month, from the 1st to its last day, for [today].
({DateTime from, DateTime to}) monthOf(DateTime today) => (
      from: DateTime(today.year, today.month, 1),
      to: DateTime(today.year, today.month + 1, 0),
    );

/// Parse a "#RRGGBB" / "#AARRGGBB" hex string into a [Color], with a gold
/// fallback for malformed values. New code draws record colours through
/// `entityTone` (theme/entity_color).
Color hexColor(String? hex, {Color fallback = const Color(0xFFC9A45C)}) =>
    parseEntityHex(hex, fallback: fallback);

/// "2026-02" → "Şub" / "Feb" for the six-month bar labels, in the UI language.
/// Account-type and frequency labels are copy and live in `AppL10n`.
String shortMonthLabel(String yyyyMm) {
  final parts = yyyyMm.split('-');
  if (parts.length < 2) return yyyyMm;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return yyyyMm;
  return formatMonthShort(DateTime(year, month));
}

/// The icon of an account type (design-analysis §7.6).
IconData accountTypeIcon(String type) => switch (type) {
      'cash' => Icons.payments_outlined,
      'bank' => Icons.account_balance_outlined,
      'credit_card' => Icons.credit_card_rounded,
      'savings' => Icons.savings_outlined,
      'crypto' => Icons.currency_bitcoin_rounded,
      _ => Icons.account_balance_wallet_outlined,
    };

/// One currency's sum of balances.
typedef CurrencySum = ({String currency, int subunitToUnit, int cents});

/// [accounts]' balances added up per currency — never across currencies
/// (contract §1.7): [first] (the user's currency) leads, the rest follow by
/// code.
List<CurrencySum> balancesByCurrency(
  Iterable<Account> accounts, {
  String? first,
}) {
  final sums = <String, CurrencySum>{};
  for (final a in accounts) {
    final code = a.currency.toUpperCase();
    final sum = sums[code];
    sums[code] = (
      currency: code,
      subunitToUnit: a.subunitToUnit,
      cents: (sum?.cents ?? 0) + a.balanceCents,
    );
  }
  final lead = first?.toUpperCase();
  return sums.values.toList()
    ..sort((a, b) {
      if (a.currency == lead) return -1;
      if (b.currency == lead) return 1;
      return a.currency.compareTo(b.currency);
    });
}

/// [sums] in one line: "₺36.250 · 412 gr".
String formatCurrencySums(List<CurrencySum> sums) => [
      for (final s in sums)
        formatMoney(
          s.cents,
          s.currency,
          s.subunitToUnit,
          decimals: MoneyDecimals.auto,
        ),
    ].join(' · ');

/// The account new transactions start on, as this device remembers it
/// ([PrefKeys.lastAccountId]); null without one (or without preferences, in
/// tests).
int? defaultAccountId(WidgetRef ref) {
  try {
    return ref.read(sharedPrefsProvider).getInt(PrefKeys.lastAccountId);
  } catch (_) {
    return null;
  }
}

/// Makes [id] the account new transactions start on — or, with [id] null,
/// forgets [unless] as the default when it is the one.
void setDefaultAccountId(WidgetRef ref, int? id, {int? unless}) {
  try {
    final prefs = ref.read(sharedPrefsProvider);
    if (id != null) {
      prefs.setInt(PrefKeys.lastAccountId, id);
    } else if (unless != null &&
        prefs.getInt(PrefKeys.lastAccountId) == unless) {
      prefs.remove(PrefKeys.lastAccountId);
    }
  } catch (_) {
    // No preferences (a test without them): nothing to remember.
  }
}
