import 'package:intl/intl.dart';

/// Currencies whose sign goes in front of the number, without a space:
/// `₺1.234,56`, `−$250.00` (design-analysis §3.7).
const _symbols = {
  'TRY': '₺',
  'USD': '\$',
  'EUR': '€',
  'GBP': '£',
};

/// The no-break space between a number and a code or unit (`CHF 1.234,56`,
/// `412 gr`). Never U+0020 (the line could break inside an amount) and never
/// U+202F (Fraunces has no glyph for it).
const nbsp = '\u00A0';

/// The minus sign (U+2212) every negative amount carries — never a hyphen.
const minusSign = '\u2212';

/// Gram gold is counted in grams: "gr" in Turkish, "g" in English.
String _gramUnit(String? locale) => _loc(locale) == 'en' ? 'g' : 'gr';

/// What stands for [currency] next to a number: ₺ \$ € £, the gram unit
/// for GAU, otherwise the ISO code itself.
String currencySymbol(String currency, {String? locale}) =>
    _symbols[currency] ?? (currency == 'GAU' ? _gramUnit(locale) : currency);

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

/// Which sign an amount carries (design-analysis §3.7). An exact zero never
/// carries one, whatever is asked: it is always "₺0".
enum MoneySign {
  /// A minus when the amount is below zero, nothing otherwise.
  auto,

  /// "+" above zero and "−" below: income and expense rows, nets.
  always,

  /// "−" in front of the magnitude: an expense stored as a positive amount.
  negative,

  /// No sign at all: the magnitude.
  none,
}

/// Whether the minor units are written.
enum MoneyDecimals {
  /// Always, to the currency's precision: `₺42.750,00`.
  always,

  /// Only when there are any: `₺42.750`, `₺42.750,50` — chips, tiles and the
  /// income/expense line.
  auto,
}

/// The sign character for [cents] under [sign] ('' for none).
String _signOf(int cents, MoneySign sign) {
  if (cents == 0) return '';
  return switch (sign) {
    MoneySign.auto => cents < 0 ? minusSign : '',
    MoneySign.always => cents < 0 ? minusSign : '+',
    MoneySign.negative => minusSign,
    MoneySign.none => '',
  };
}

/// [number] written in [currency]: ₺ \$ € £ in front with no space, the
/// gram unit after it and any other code before it, each across a no-break
/// space; [sign] always comes first ("−₺250,00", "−CHF 250,00").
String _withCurrency(String sign, String number, String currency,
    String? locale) {
  final symbol = _symbols[currency];
  if (symbol != null) return '$sign$symbol$number';
  if (currency == 'GAU') return '$sign$number$nbsp${_gramUnit(locale)}';
  return '$sign$currency$nbsp$number';
}

/// The only place money math lives (design-analysis §3.7):
///
/// | | tr | en |
/// |---|---|---|
/// | amount | `₺1.234,56` | `₺1,234.56` |
/// | [MoneySign.always] income | `+₺1.500,00` | `+₺1,500.00` |
/// | expense | `−₺250,00` | `−₺250.00` |
/// | exact zero (every variant) | `₺0` | `₺0` |
/// | [MoneyDecimals.auto] | `₺42.750`, `₺42.750,50` | `₺42,750` |
/// | gram gold (subunit 1) | `412 gr` | `412 g` |
/// | a code without a symbol | `CHF 1.234,56` | `CHF 1,234.56` |
///
/// [signed] and [negative] are the older spelling of [MoneySign.always] and
/// [MoneySign.negative]; [sign] wins when it is not [MoneySign.auto].
String formatMoney(
  int cents,
  String currency,
  int subunitToUnit, {
  MoneySign sign = MoneySign.auto,
  MoneyDecimals decimals = MoneyDecimals.always,
  bool signed = false,
  bool negative = false,
  String? locale,
}) {
  final effective = sign != MoneySign.auto
      ? sign
      : negative
          ? MoneySign.negative
          : signed
              ? MoneySign.always
              : MoneySign.auto;
  final loc = _loc(locale);
  if (cents == 0) return _withCurrency('', '0', currency, loc);
  final major = cents.abs() / subunitToUnit;
  final whole = cents.abs() % subunitToUnit == 0;
  final digits = decimals == MoneyDecimals.auto && whole
      ? 0
      : decimalsFor(subunitToUnit);
  final number = NumberFormat(_moneyPattern(digits), loc).format(major);
  return _withCurrency(_signOf(cents, effective), number, currency, loc);
}

/// Where [formatMoneyCompact] starts abbreviating, in major units.
const compactMoneyThreshold = 10000;

/// Thousands, millions, billions: "B / Mn / Mr" in Turkish, "K / M / B" in
/// English — number notation, like the decimal mark, so it lives here.
const _compactSuffixes = {
  'tr': ['B', 'Mn', 'Mr'],
  'en': ['K', 'M', 'B'],
};

/// Money for narrow slots — axes, tiles, day totals (§3.7): below
/// [compactMoneyThreshold] the full amount with [MoneyDecimals.auto]
/// (`₺9.999`), from there one decimal and a magnitude, a trailing zero
/// decimal dropped: `₺47,5B`, `₺1,2Mn`, `₺3,4Mr` (tr) · `₺47.5K`, `₺1.2M`,
/// `₺3.4B` (en).
String formatMoneyCompact(
  int cents,
  String currency,
  int subunitToUnit, {
  MoneySign sign = MoneySign.auto,
  String? locale,
}) {
  final loc = _loc(locale);
  final major = cents.abs() / subunitToUnit;
  if (major < compactMoneyThreshold) {
    return formatMoney(cents, currency, subunitToUnit,
        sign: sign, decimals: MoneyDecimals.auto, locale: loc);
  }
  final suffixes = _compactSuffixes[loc] ?? _compactSuffixes['en']!;
  final format = NumberFormat('#,##0.#', loc);
  var step = 0;
  var scaled = major / 1000;
  // Rounds up into the next magnitude (999.96K → 1M, not "1.000K").
  while (step < suffixes.length - 1 &&
      (scaled * 10).round() / 10 >= 1000) {
    scaled /= 1000;
    step++;
  }
  final number = '${format.format(scaled)}${suffixes[step]}';
  return _withCurrency(_signOf(cents, sign), number, currency, loc);
}

/// An amount as it is being typed on the keypad: [whole] grouped for the
/// language, then the language's decimal mark and [fraction] once the mark
/// has been typed (an empty [fraction] still shows the mark: "12,").
/// [negative] puts the minus in front, as [formatMoney] does: "₺1.250,5",
/// "₺12,", "−₺12".
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
  return _withCurrency(
      negative ? minusSign : '', '$grouped$decimals', currency, _loc(locale));
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

/// A percentage, tabular digits and the sign where the language puts it:
/// `%62` in Turkish, `62%` in English (§3.7).
String formatPercent(num value, {String? locale}) {
  final digits = formatPercentNumber(value);
  return _loc(locale) == 'en' ? '$digits%' : '%$digits';
}

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
