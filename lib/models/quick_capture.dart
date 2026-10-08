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
