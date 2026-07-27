import 'package:flutter/material.dart';

/// Parse a "#RRGGBB" / "#AARRGGBB" hex string into a [Color], with a gold
/// fallback for malformed values.
Color hexColor(String? hex, {Color fallback = const Color(0xFFC9A45C)}) {
  if (hex == null) return fallback;
  var value = hex.trim().replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return fallback;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? fallback : Color(parsed);
}

/// Turkish label for an account_type (design §4.4).
String accountTypeLabel(String type) => switch (type) {
      'cash' => 'Nakit',
      'bank' => 'Banka',
      'credit_card' => 'Kredi Kartı',
      'savings' => 'Birikim',
      'crypto' => 'Kripto',
      _ => 'Hesap',
    };

/// "2026-02" → "Şub" (Turkish short month) for the six-month bar labels.
const _trShortMonths = [
  'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
  'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
];

String shortMonthLabel(String yyyyMm) {
  final parts = yyyyMm.split('-');
  if (parts.length < 2) return yyyyMm;
  final m = int.tryParse(parts[1]);
  if (m == null || m < 1 || m > 12) return yyyyMm;
  return _trShortMonths[m - 1];
}

/// Turkish label for a subscription/transaction frequency.
String frequencyLabel(String frequency) => switch (frequency) {
      'daily' => 'Günlük',
      'weekly' => 'Haftalık',
      'monthly' => 'Aylık',
      'yearly' => 'Yıllık',
      _ => frequency,
    };
