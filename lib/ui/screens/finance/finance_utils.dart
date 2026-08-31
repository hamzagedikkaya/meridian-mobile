import 'package:flutter/material.dart';

import '../../../core/formats.dart';

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
