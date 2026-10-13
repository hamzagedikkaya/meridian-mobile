import 'date_utils.dart';
import 'habit.dart';
import 'json_read.dart';
import 'todo.dart';
import 'transaction.dart';

/// What a captured line named as an event (`suggestion` of an
/// `event_suggestion`): nothing was saved, and the app offers to save it.
class EventSuggestion {
  /// The line without its day word and time.
  final String title;

  /// The day, in the account's zone.
  final DateTime date;

  /// `"HH:MM"` (24 h), or null when no time was given.
  final String? time;

  /// The start as the account's wall clock; null without a time.
  final DateTime? startAt;
  final bool allDay;

  /// The day word as typed (`yarın`, `cuma`, …).
  final String? keyword;

  const EventSuggestion({
    required this.title,
    required this.date,
    this.time,
    this.startAt,
    required this.allDay,
    this.keyword,
  });

  static EventSuggestion? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final date = parseDateTime(json['date']);
    if (date == null) return null;
    final time = json['time'] as String?;
    return EventSuggestion(
      title: (json['title'] as String?) ?? '',
      date: DateTime(date.year, date.month, date.day),
      time: time,
      startAt: parseDateTime(json['start_at']),
      allDay: readBoolOrNull(json['all_day']) ?? time == null,
      keyword: json['keyword'] as String?,
    );
  }
}

/// `POST /quick_captures` → what the line turned into.
///
/// [saved] says whether anything was written. A line that names a day is
/// an event suggestion: nothing is saved, and [suggestion] holds what was
/// read from it. Otherwise [capturedType] says what was saved and [record]
/// is that record.
class QuickCaptureResult {
  final bool saved;

  /// `transaction`, `habit_log`, `todo` or `event_suggestion` — or a kind
  /// this version of the app does not know yet.
  final String capturedType;
  final int? recordId;

  /// The description, habit name or title — the line itself for an event
  /// suggestion.
  final String summary;

  /// The server's own sentence, in the account's language. The app words
  /// its confirmation itself (by [capturedType]); this is kept for a kind
  /// it does not know.
  final String? message;

  /// The saved record, as its own endpoints return it.
  final Map<String, dynamic>? record;
  final EventSuggestion? suggestion;

  const QuickCaptureResult({
    required this.saved,
    required this.capturedType,
    this.recordId,
    required this.summary,
    this.message,
    this.record,
    this.suggestion,
  });

  bool get isEventSuggestion => capturedType == 'event_suggestion';

  /// The transaction a money line saved; null for anything else, or a record
  /// that does not parse (the capture was saved either way).
  Transaction? get transaction => capturedType == 'transaction'
      ? _parsed(record, Transaction.fromJson)
      : null;

  /// The todo the line saved.
  Todo? get todo =>
      capturedType == 'todo' ? _parsed(record, Todo.fromJson) : null;

  /// The day a `habit: …` line logged.
  HabitDayLog? get habitLog =>
      capturedType == 'habit_log' ? HabitDayLog.fromJson(record) : null;

  /// A server from before G1 sends no `saved`: everything but an event
  /// suggestion was saved then.
  factory QuickCaptureResult.fromJson(Map<String, dynamic> json) {
    final type = (json['captured_type'] as String?) ?? '';
    return QuickCaptureResult(
      saved: readBoolOrNull(json['saved']) ?? type != 'event_suggestion',
      capturedType: type,
      recordId: readIntOrNull(json['record_id']),
      summary: (json['summary'] as String?) ?? '',
      message: json['message'] as String?,
      record: json['record'] is Map<String, dynamic>
          ? json['record'] as Map<String, dynamic>
          : null,
      suggestion: EventSuggestion.fromJson(json['suggestion']),
    );
  }

  static T? _parsed<T>(
    Map<String, dynamic>? json,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (json == null) return null;
    try {
      return parse(json);
    } catch (_) {
      return null;
    }
  }
}

// --- Quick add: what a line looks like (design-analysis §7.3) -----------------

/// What quick add can save a line as: the type chips after "Otomatik".
enum QuickAddKind { task, expense, income, event, habit }

/// The app's guess at what the server will make of [text] — shown on the
/// "Otomatik" chip ("Otomatik · Harcama") and on the add button before the
/// line is sent. Only a hint: the server decides (contract §11), and its
/// rules are mirrored here in the same order:
///
/// 1. a leading sign then a number, optionally with `₺` before it → money
///    (`-`, `−`, `–` an expense, `+` an income). After a plain `-` a space
///    makes a list item (`- 3 yumurta al`) unless a currency marks the
///    number (`- ₺250`, `- 250 TL`); another group of digits after the
///    number (a phone number, `+90 532 …`) is not money either;
/// 2. `habit:` / `alışkanlık:` (any case, with or without Turkish letters)
///    → a habit check-in;
/// 3. a whole day word (`yarın`, `cuma`, `tomorrow`, …) → an event. A
///    bare `pazar` (also "market") counts only with a lead-in (`bu`,
///    `gelecek`, …), `günü` or a time of day (`15:00`, `saat 9`, `9'da`,
///    `3pm`); a time without a day word does not make an event — the
///    server saves `dişçi 15:00` as a task;
/// 4. anything else → a task.
///
/// Null for a blank line.
QuickAddKind? guessQuickAddKind(String text) {
  final line = text.trim();
  if (line.isEmpty) return null;
  final money = _moneyKind(line);
  if (money != null) return money;
  final folded = _fold(line);
  if (_habitPrefix.hasMatch(folded)) return QuickAddKind.habit;
  if (_namesDay(folded)) return QuickAddKind.event;
  return QuickAddKind.task;
}

/// A money line taken apart for the transaction form: the first number in
/// [text] in minor units of a currency with [subunitToUnit] (null when there
/// is none, or it cannot be read), and the rest of the line — without the
/// sign, the number and a currency word right after it — as the
/// description. Numbers are read as the server reads them (contract §11):
/// a single separator is the decimal point unless a 1–3 digit lead not
/// starting with 0 is followed by exactly three digits (`1.500` is fifteen
/// hundred, `0,250` a quarter); with both separators the last one is the
/// decimal point.
({int? minorUnits, String description}) splitQuickAmount(
  String text, {
  int subunitToUnit = 100,
}) {
  final line = text.trim();
  final match = _firstAmount.firstMatch(line);
  if (match == null) return (minorUnits: null, description: line);
  final minor = _readMinorUnits(match.group(2)!, subunitToUnit);
  final rest = '${line.substring(0, match.start)} ${line.substring(match.end)}'
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'^[\s\-−–—+₺:,.·]+'), '');
  return (minorUnits: minor, description: rest);
}

/// A sign, the space after it, an optional `₺`, the number and the rest.
final _leadingSign = RegExp(r'^([\-−–+])(\s*)(₺\s*)?\d[\d.,]*(.*)$',
    unicode: true, dotAll: true);

/// A currency right after the number.
final _currencyAfter = RegExp(
  r'^\s*(?:₺|tl|try)(?![\p{L}])',
  caseSensitive: false,
  unicode: true,
);

/// Another group of digits after the number: a phone number.
final _moreDigits = RegExp(r'^\s+\(?\d');

/// The money kind of [line] when the server reads it as money (contract
/// §11 rule 2), else null.
QuickAddKind? _moneyKind(String line) {
  final match = _leadingSign.firstMatch(line);
  if (match == null) return null;
  final sign = match.group(1)!;
  final rest = match.group(4)!;
  final listItem = sign == '-' &&
      match.group(2)!.isNotEmpty &&
      match.group(3) == null &&
      !_currencyAfter.hasMatch(rest);
  if (listItem || _moreDigits.hasMatch(rest)) return null;
  return sign == '+' ? QuickAddKind.income : QuickAddKind.expense;
}

/// An optional sign and `₺`, the number, and a currency word right after it.
final _firstAmount = RegExp(
  r'([\-−–+]\s*)?(?:₺\s*)?(\d[\d.,]*\d|\d)(\s*(?:₺|tl|try)(?![\p{L}]))?',
  caseSensitive: false,
  unicode: true,
);

final _habitPrefix = RegExp(r'^(habit|aliskanlik)\s*:');

/// The most minor units an amount can have (the server's integer column).
const _maxMinorUnits = 2147483647;

int? _readMinorUnits(String number, int subunitToUnit) {
  final s = number.replaceFirst(RegExp(r'[.,]+$'), '');
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  String whole;
  var fraction = '';
  if (lastDot >= 0 && lastComma >= 0) {
    final mark = lastDot > lastComma ? lastDot : lastComma;
    whole = s.substring(0, mark).replaceAll(RegExp('[.,]'), '');
    fraction = s.substring(mark + 1);
  } else if (lastDot >= 0 || lastComma >= 0) {
    final sep = lastDot >= 0 ? '.' : ',';
    final parts = s.split(sep);
    final grouped =
        RegExp(r'^[1-9]\d{0,2}$').hasMatch(parts.first) &&
        parts.skip(1).every((p) => p.length == 3);
    if (grouped) {
      whole = parts.join();
    } else if (parts.length == 2) {
      whole = parts.first;
      fraction = parts.last;
    } else {
      return null; // An inconsistent grouping (`1.25.0`).
    }
  } else {
    whole = s;
  }
  if (!RegExp(r'^\d+$').hasMatch(whole) ||
      (fraction.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fraction))) {
    return null;
  }
  var decimals = 0;
  for (var unit = subunitToUnit; unit > 1; unit ~/= 10) {
    decimals++;
  }
  // More decimals than the currency has would be refused (`too_precise`):
  // the form gets what it can show, and the user sees it there.
  final cut = fraction.length > decimals
      ? fraction.substring(0, decimals)
      : fraction.padRight(decimals, '0');
  final minor = int.tryParse('$whole$cut');
  if (minor == null || minor <= 0 || minor > _maxMinorUnits) return null;
  return minor;
}

/// Lower case, without Turkish letters or accents: `Alışkanlık` and
/// `ALISKANLIK` read the same.
String _fold(String text) {
  const plain = {
    'İ': 'i',
    'I': 'i',
    'ı': 'i',
    'Ş': 's',
    'ş': 's',
    'Ç': 'c',
    'ç': 'c',
    'Ğ': 'g',
    'ğ': 'g',
    'Ö': 'o',
    'ö': 'o',
    'Ü': 'u',
    'ü': 'u',
    'Â': 'a',
    'â': 'a',
    'Î': 'i',
    'î': 'i',
    'Û': 'u',
    'û': 'u',
  };
  final out = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    out.write(plain[ch] ?? ch.toLowerCase());
  }
  return out.toString();
}

const _dayWords = {
  'yarin',
  'tomorrow',
  'pazartesi',
  'sali',
  'carsamba',
  'persembe',
  'cuma',
  'cumartesi',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
};

const _leadIns = {'bu', 'gelecek', 'onumuzdeki', 'next', 'this', 'on'};

/// A whole day word: punctuation around it is dropped, and words joined
/// by `-` or `/` (`perşembe-cuma`) are words of their own, but a suffix
/// (`yarınki`, `Cuma'ya`) makes it another word. A bare `pazar` — no
/// lead-in, no `günü` — is Sunday only when the line also has a time.
bool _namesDay(String folded) {
  final words = [
    for (final raw in folded.split(RegExp(r'[\s\-–—/]+')))
      raw.replaceAll(RegExp(r'^[.,;:!?()"“”]+|[.,;:!?()"“”]+$'), ''),
  ];
  var barePazar = false;
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    if (_dayWords.contains(word)) return true;
    if (word == 'pazar') {
      final before = i > 0 ? words[i - 1] : '';
      final after = i + 1 < words.length ? words[i + 1] : '';
      if (_leadIns.contains(before) || after == 'gunu') return true;
      barePazar = true;
    }
  }
  return barePazar && _hasTime(folded);
}

final _clock = RegExp(
  r'(?<![\d.,])([01]?\d|2[0-3])[:.]([0-5]\d)(?![\d.,])(?!\s*(?:₺|tl|try)(?![\p{L}]))',
  unicode: true,
);
final _saat = RegExp(r'(?:^|\s)saat\s*\d{1,2}(?!\d)');
final _suffixedHour = RegExp(
  r"(?:^|\s)\d{1,2}['’][dt][ae]n?(?![\p{L}])",
  unicode: true,
);
final _amPm = RegExp(r'(?:^|\s)\d{1,2}\s?(?:am|pm)(?![\p{L}])', unicode: true);

bool _hasTime(String folded) =>
    _clock.hasMatch(folded) ||
    _saat.hasMatch(folded) ||
    _suffixedHour.hasMatch(folded) ||
    _amPm.hasMatch(folded);
