import 'package:intl/intl.dart';

const _symbols = {'TRY': '₺', 'USD': '\$', 'EUR': '€', 'GAU': 'gr'};

String currencySymbol(String currency) => _symbols[currency] ?? currency;

/// The only place money math lives (docs/design.md §2.4).
/// GAU has subunitToUnit 1 → "412 gr"; TRY 100 → "1.234,56 ₺".
String formatMoney(
  int cents,
  String currency,
  int subunitToUnit, {
  bool signed = false,
  bool negative = false,
}) {
  final decimals = subunitToUnit == 1 ? 0 : 2;
  final major = cents.abs() / subunitToUnit;
  final pattern = decimals == 0 ? '#,##0' : '#,##0.00';
  final number = NumberFormat(pattern, 'tr_TR').format(major);
  final sign = negative || cents < 0 ? '−' : (signed ? '+' : '');
  return '$sign$number ${currencySymbol(currency)}';
}

String formatDate(DateTime date, {bool withYear = false}) =>
    DateFormat(withYear ? 'd MMMM y' : 'd MMMM', 'tr_TR').format(date);

String formatWeekday(DateTime date) => DateFormat('EEEE', 'tr_TR').format(date);

String formatTime(DateTime time) => DateFormat('HH:mm').format(time.toLocal());

String formatMonthShort(DateTime date) => DateFormat('MMM', 'tr_TR').format(date);

/// "Bugün", "Dün", or "12 Temmuz".
String relativeDay(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(date.year, date.month, date.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Bugün';
  if (diff == 1) return 'Dün';
  if (diff == -1) return 'Yarın';
  return formatDate(date, withYear: that.year != today.year);
}

/// "3 gün sonra", "bugün", "2 gün önce" — for subscriptions/deadlines.
String relativeDays(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(date.year, date.month, date.day);
  final diff = that.difference(today).inDays;
  if (diff == 0) return 'bugün';
  if (diff > 0) return '$diff gün sonra';
  return '${-diff} gün önce';
}

String greetingForHour(int hour) {
  if (hour >= 5 && hour < 12) return 'İyi sabahlar';
  if (hour >= 12 && hour < 18) return 'İyi günler';
  if (hour >= 18 && hour < 23) return 'İyi akşamlar';
  return 'İyi geceler';
}
