import 'package:flutter/material.dart';

import '../../../core/formats.dart';
import '../../../data/providers.dart' show TxFilters;
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
