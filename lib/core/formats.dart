import 'package:intl/intl.dart';

const _symbols = {'TRY': '₺', 'USD': '\$', 'EUR': '€', 'GAU': 'gr'};

String currencySymbol(String currency) => _symbols[currency] ?? currency;

/// Numbers and dates follow the UI language. [Intl.defaultLocale] is set by the
/// `AppL10n` delegate whenever the locale changes, so nothing has to thread a
/// locale through the widget tree; tests can still pass one explicitly.
///
/// Anything that is *copy* — "Bugün", "3 gün sonra", "%82" — lives in
/// `lib/l10n/` instead. This file only shapes values.
String _loc([String? locale]) => locale ?? Intl.defaultLocale ?? 'tr';

/// The only place money math lives (docs/design.md §2.4).
/// GAU has subunitToUnit 1 → "412 gr"; TRY 100 → "1.234,56 ₺" (tr) or
/// "1,234.56 ₺" (en).
String formatMoney(
  int cents,
  String currency,
  int subunitToUnit, {
  bool signed = false,
  bool negative = false,
  String? locale,
}) {
  final decimals = subunitToUnit == 1 ? 0 : 2;
  final major = cents.abs() / subunitToUnit;
  final pattern = decimals == 0 ? '#,##0' : '#,##0.00';
  final number = NumberFormat(pattern, _loc(locale)).format(major);
  final sign = negative || cents < 0 ? '−' : (signed ? '+' : '');
  return '$sign$number ${currencySymbol(currency)}';
}

/// One-decimal number in the locale's notation ("1,5" in Turkish, "1.5" in
/// English) — used by the chart-axis abbreviations.
String formatDecimal(num value, {int decimals = 1, String? locale}) {
  final pattern = decimals == 0 ? '#,##0' : '#,##0.${'0' * decimals}';
  return NumberFormat(pattern, _loc(locale)).format(value);
}

/// Percentage digits only — the `%` sign goes where the language puts it, so
/// `AppL10n.percent` wraps this.
String formatPercentNumber(num value) => value.round().toString();

String formatDate(DateTime date, {bool withYear = false, String? locale}) {
  final l = _loc(locale);
  return (withYear ? DateFormat.yMMMMd(l) : DateFormat.MMMMd(l)).format(date);
}

String formatWeekday(DateTime date, {String? locale}) =>
    DateFormat.EEEE(_loc(locale)).format(date);

String formatWeekdayShort(DateTime date, {String? locale}) =>
    DateFormat.E(_loc(locale)).format(date);

/// 24-hour clock in every language — the design keeps time columns tabular.
String formatTime(DateTime time) => DateFormat('HH:mm').format(time.toLocal());

String formatMonthShort(DateTime date, {String? locale}) =>
    DateFormat.MMM(_loc(locale)).format(date);

/// Signed day distance from today: 0 today, -1 yesterday, +1 tomorrow.
/// Shared by every relative-date string in `lib/l10n/`.
int dayDelta(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final a = DateTime(today.year, today.month, today.day);
  final b = DateTime(date.year, date.month, date.day);
  return b.difference(a).inDays;
}
