import 'package:intl/intl.dart';

const _symbols = {
  'TRY': '₺',
  'USD': '\$',
  'EUR': '€',
  'GBP': '£',
  'GAU': 'gr',
};

String currencySymbol(String currency) => _symbols[currency] ?? currency;

/// Digits after the decimal mark for a currency whose minor unit is
/// 1/[subunitToUnit] of the unit: 2 for TRY (100), 0 for gram gold (1),
/// 3 for a currency counted in thousandths.
int decimalsFor(int subunitToUnit) {
  var decimals = 0;
  for (var unit = subunitToUnit; unit >= 10; unit ~/= 10) {
    decimals++;
  }
  return decimals;
}

String _moneyPattern(int decimals) =>
    decimals == 0 ? '#,##0' : '#,##0.${'0' * decimals}';

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
  final major = cents.abs() / subunitToUnit;
  final pattern = _moneyPattern(decimalsFor(subunitToUnit));
  final number = NumberFormat(pattern, _loc(locale)).format(major);
  final sign = negative || cents < 0 ? '−' : (signed ? '+' : '');
  return '$sign$number ${currencySymbol(currency)}';
}

/// An amount as it is being typed on the keypad: [whole] grouped for the
/// language, then the language's decimal mark and [fraction] once the mark
/// has been typed (an empty [fraction] still shows the mark: "12,").
/// [negative] puts the minus in front, as [formatMoney] does.
String formatTypedAmount({
  required String whole,
  String? fraction,
  required String currency,
  bool negative = false,
  String? locale,
}) {
  final format = NumberFormat('#,##0', _loc(locale));
  final grouped = format.format(int.tryParse(whole) ?? 0);
  final decimals =
      fraction == null ? '' : '${format.symbols.DECIMAL_SEP}$fraction';
  return '${negative ? '−' : ''}$grouped$decimals ${currencySymbol(currency)}';
}

/// The language's decimal mark: "," in Turkish, "." in English — the label
/// of the keypad's decimal key.
String decimalMark({String? locale}) =>
    NumberFormat('#,##0.0', _loc(locale)).symbols.DECIMAL_SEP;

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

/// "Ekim 2026" / "October 2026": a calendar's month heading.
String formatMonthYear(DateTime date, {String? locale}) =>
    DateFormat.yMMMM(_loc(locale)).format(date);

DateTime? _appToday;

/// The calendar day the app counts as today: the account's, which is the
/// server's "today" — not necessarily this phone's date when the phone is in
/// another time zone. `CurrentDay` (data/current_day.dart) keeps it current
/// across midnight and resume, the way the localization delegate keeps
/// [Intl.defaultLocale]; until it has run (and in plain unit tests) it is the
/// device's date.
DateTime appToday() {
  final day = _appToday;
  if (day != null) return day;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Sets what [appToday] returns; null goes back to the device's date.
void setAppToday(DateTime? day) =>
    _appToday = day == null ? null : DateTime(day.year, day.month, day.day);

/// Signed day distance from today ([appToday], or the date of [now]): 0
/// today, -1 yesterday, +1 tomorrow. Shared by every relative-date string in
/// `lib/l10n/`.
///
/// Counted in calendar days, so the 23- or 25-hour day of a daylight-saving
/// change is still one day.
int dayDelta(DateTime date, {DateTime? now}) {
  final today = now ?? appToday();
  final a = DateTime.utc(today.year, today.month, today.day);
  final b = DateTime.utc(date.year, date.month, date.day);
  return b.difference(a).inDays;
}
