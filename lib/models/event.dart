import 'date_utils.dart';

/// Calendar event (GET /events). The `/home` `today_events` payload is a subset
/// of these fields — fromJson tolerates the missing ones.
class Event {
  final int id;
  final String title;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool allDay;
  final String color;
  final String? eventType;
  final String? location;
  final int? durationMinutes;
  final List<DateTime> occurrences;

  const Event({
    required this.id,
    required this.title,
    this.startAt,
    this.endAt,
    required this.allDay,
    required this.color,
    this.eventType,
    this.location,
    this.durationMinutes,
    required this.occurrences,
  });

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        id: json['id'] as int,
        title: (json['title'] as String?) ?? '',
        startAt: parseDateTime(json['start_at']),
        endAt: parseDateTime(json['end_at']),
        allDay: (json['all_day'] as bool?) ?? false,
        color: (json['color'] as String?) ?? '#6B8FA0',
        eventType: json['event_type'] as String?,
        location: json['location'] as String?,
        durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
        occurrences: ((json['occurrences'] as List?) ?? const [])
            .map((e) => DateTime.parse(e as String))
            .toList(),
      );
}
