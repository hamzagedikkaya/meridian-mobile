import 'date_utils.dart';
import 'json_read.dart';

/// The kinds of event the server takes (`event_type`, contract §10.1).
const eventTypes = ['personal', 'work', 'health', 'finance', 'other'];

/// Calendar event (GET /events). The `/home` `today_events` payload is a subset
/// of these fields — fromJson tolerates the missing ones.
class Event {
  final int id;
  final String title;

  /// For a series, its first occurrence (the anchor), possibly on an earlier
  /// day than the one shown: a series is placed by [occurrences], at the
  /// time of day of this (contract §10.2).
  final DateTime? startAt;
  final DateTime? endAt;
  final bool allDay;
  final String color;
  final String? eventType;
  final String? location;
  final int? durationMinutes;
  final List<DateTime> occurrences;

  /// A series expanded from [recurrenceRule] (`recurring`, G3). Editing or
  /// deleting it changes every occurrence.
  final bool recurring;

  /// Only in the full event (`GET /events/:id`, and the answer to a save).
  final String? description;

  /// The RRULE body in the server's normal form (`FREQ=WEEKLY;BYDAY=TU`,
  /// its `UNTIL` as a UTC instant); only in the full event, null when it
  /// does not repeat.
  final String? recurrenceRule;

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
    this.recurring = false,
    this.description,
    this.recurrenceRule,
  });

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        id: readId(json['id']),
        title: (json['title'] as String?) ?? '',
        startAt: parseDateTime(json['start_at']),
        endAt: parseDateTime(json['end_at']),
        allDay: readBool(json['all_day']),
        color: (json['color'] as String?) ?? '#6B8FA0',
        eventType: json['event_type'] as String?,
        location: json['location'] as String?,
        durationMinutes: readIntOrNull(json['duration_minutes']),
        occurrences: ((json['occurrences'] as List?) ?? const [])
            .map((e) => parseDateTime(e))
            .whereType<DateTime>()
            .map(dateOnly)
            .toList(),
        recurring: readBool(json['recurring']) ||
            ((json['recurrence_rule'] as String?)?.isNotEmpty ?? false),
        description: json['description'] as String?,
        recurrenceRule: switch (json['recurrence_rule']) {
          final String rule when rule.trim().isNotEmpty => rule.trim(),
          _ => null,
        },
      );

  /// The day it starts on (the anchor's day for a series).
  DateTime? get startDay => startAt == null ? null : dateOnly(startAt!);

  /// The days it spans, for an all-day event: its first and last day.
  DateTime? get endDay => endAt == null ? null : dateOnly(endAt!);

  /// When the occurrence on [day] starts: at the time of day of [startAt]
  /// (00:00 for an all-day event).
  DateTime occurrenceStart(DateTime day) {
    final start = startAt;
    if (allDay || start == null) return dateOnly(day);
    return DateTime(day.year, day.month, day.day, start.hour, start.minute);
  }

  /// When the occurrence on [day] ends, [durationMinutes] after it starts;
  /// null without an end, and for an all-day event (shown by its days).
  DateTime? occurrenceEnd(DateTime day) {
    final minutes = durationMinutes;
    if (allDay || minutes == null || startAt == null) return null;
    return occurrenceStart(day).add(Duration(minutes: minutes));
  }

  /// Minutes since midnight of its start — how a day's events are ordered
  /// (all-day ones first). A series sorts by the time of day of its anchor,
  /// never by the anchor's date (contract §3, `today_events`).
  int get minuteOfDay {
    final start = startAt;
    if (allDay || start == null) return -1;
    return start.hour * 60 + start.minute;
  }
}

/// Create/update body for an event (contract §10).
///
/// Times are sent as the account's wall clock without an offset (the server
/// reads them in the account's zone); an all-day event sends bare dates,
/// and its end is its last day (null: one day). A recurring event is one
/// row: a save changes the whole series (contract §10.2).
class EventInput {
  final String title;
  final bool allDay;

  /// The start (wall clock); only its date counts when [allDay].
  final DateTime start;

  /// The end, or null for none (for [allDay], a one-day event).
  final DateTime? end;
  final String? location;
  final String? description;
  final String color;
  final String eventType;

  /// The RRULE body, or null when it does not repeat.
  final String? recurrenceRule;

  const EventInput({
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.location,
    this.description,
    this.color = '#B8860B',
    this.eventType = 'personal',
    this.recurrenceRule,
  });

  static String? _text(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? get _end {
    final end = this.end;
    if (end == null) return null;
    // A one-day all-day event has no end: the server spans its start's day.
    if (allDay && dateOnly(end) == dateOnly(start)) return null;
    return eventWireTime(end, allDay: allDay);
  }

  String? get _rule => _text(recurrenceRule);

  /// The body of `POST /events`.
  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'start_at': eventWireTime(start, allDay: allDay),
        if (_end != null) 'end_at': _end,
        'all_day': allDay,
        if (_text(location) != null) 'location': _text(location),
        if (_text(description) != null) 'description': _text(description),
        'color': color,
        'event_type': eventType,
        if (_rule != null) 'recurrence_rule': _rule,
      };

  /// The body of `PATCH /events/:id`: only what differs from [before].
  ///
  /// A change to the times sends start and end together: the server does
  /// not move the end with the start, so a later start alone could fall
  /// after the old end (contract §10, `PATCH`).
  Map<String, dynamic> changesFrom(Event before) {
    final out = <String, dynamic>{};
    if (title.trim() != before.title.trim()) out['title'] = title.trim();
    final beforeStart = before.startAt;
    final beforeEnd = before.endAt;
    final beforeEndWire = beforeEnd == null ||
            (before.allDay &&
                beforeStart != null &&
                dateOnly(beforeEnd) == dateOnly(beforeStart))
        ? null
        : eventWireTime(beforeEnd, allDay: before.allDay);
    final timesChanged = allDay != before.allDay ||
        beforeStart == null ||
        eventWireTime(start, allDay: allDay) !=
            eventWireTime(beforeStart, allDay: before.allDay) ||
        _end != beforeEndWire;
    if (allDay != before.allDay) out['all_day'] = allDay;
    if (timesChanged) {
      out['start_at'] = eventWireTime(start, allDay: allDay);
      out['end_at'] = _end;
    }
    if (_text(location) != _text(before.location)) {
      out['location'] = _text(location);
    }
    if (_text(description) != _text(before.description)) {
      out['description'] = _text(description);
    }
    if (color.toUpperCase() != before.color.toUpperCase()) out['color'] = color;
    if (eventType != (before.eventType ?? 'personal')) {
      out['event_type'] = eventType;
    }
    if (_rule != _text(before.recurrenceRule)) {
      out['recurrence_rule'] = _rule;
    }
    return out;
  }
}

/// [time] as an event's `start_at` / `end_at`: `YYYY-MM-DD` for an all-day
/// event, otherwise `YYYY-MM-DDThh:mm` — the account's wall clock, which the
/// server reads in the account's zone (contract §1.3).
String eventWireTime(DateTime time, {required bool allDay}) {
  final day = isoDate(time);
  if (allDay) return day;
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  return '${day}T$hh:$mm';
}

/// The repetitions the event form offers (contract §10.3); [custom] is a
/// rule set on the web that none of them describes, kept as it is.
enum RecurrencePreset { none, daily, weekdays, weekly, monthly, yearly, custom }

/// A recurrence rule, read for the form and the detail sheet.
class Recurrence {
  final RecurrencePreset preset;

  /// The last day it occurs on (`UNTIL`), as the account's date.
  final DateTime? until;

  /// How many times it occurs (`COUNT`).
  final int? count;

  /// The rule as the server stores it; null when it does not repeat.
  final String? rule;

  const Recurrence._(this.preset, {this.until, this.count, this.rule});

  static const none = Recurrence._(RecurrencePreset.none);

  static const _weekdays = {'MO', 'TU', 'WE', 'TH', 'FR'};
  static const _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  /// Reads [rule] — the server's normal form, or anything the server takes
  /// — for an event that starts on [anchor]. [utcOffset] is the account's
  /// offset, to read an `UNTIL` stored as a UTC instant as the account's day
  /// (null: this device's zone).
  factory Recurrence.parse(
    String? rule, {
    DateTime? anchor,
    Duration? utcOffset,
  }) {
    final text = rule?.trim() ?? '';
    if (text.isEmpty) return none;
    final parts = <String, String>{};
    for (final part in text.toUpperCase().replaceFirst('RRULE:', '').split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      parts[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
    }
    final until = _untilDay(parts.remove('UNTIL'), utcOffset);
    final count = int.tryParse(parts.remove('COUNT') ?? '');
    if (parts['INTERVAL'] == '1') parts.remove('INTERVAL');
    if (parts['WKST'] == 'MO') parts.remove('WKST');
    final freq = parts.remove('FREQ');
    final byDay = parts.remove('BYDAY');
    final byMonthDay = parts.remove('BYMONTHDAY');
    final byMonth = parts.remove('BYMONTH');
    final weekday = anchor == null ? null : _days[anchor.weekday - 1];
    final preset = parts.isNotEmpty
        ? RecurrencePreset.custom
        : switch (freq) {
            'DAILY' when byDay == null && byMonthDay == null && byMonth == null =>
              RecurrencePreset.daily,
            'WEEKLY'
                when byMonthDay == null &&
                    byMonth == null &&
                    byDay != null &&
                    byDay.split(',').toSet().containsAll(_weekdays) &&
                    byDay.split(',').length == 5 =>
              RecurrencePreset.weekdays,
            'WEEKLY'
                when byMonthDay == null &&
                    byMonth == null &&
                    (byDay == null || byDay == weekday) =>
              RecurrencePreset.weekly,
            // An explicit day that some months lack (29–31) skips those
            // months; the plain preset would fall on their last day
            // instead (contract §10.3), so it is kept as written.
            'MONTHLY'
                when byDay == null &&
                    byMonth == null &&
                    (byMonthDay == null ||
                        (byMonthDay == '${anchor?.day}' && anchor!.day < 29)) =>
              RecurrencePreset.monthly,
            'YEARLY'
                when byDay == null &&
                    (byMonth == null || byMonth == '${anchor?.month}') &&
                    (byMonthDay == null ||
                        (byMonthDay == '${anchor?.day}' &&
                            !(anchor!.month == 2 && anchor.day == 29))) =>
              RecurrencePreset.yearly,
            _ => RecurrencePreset.custom,
          };
    return Recurrence._(preset, until: until, count: count, rule: text);
  }

  /// The rule for [preset], ending on [until] (inclusive) when given, else
  /// after [count] times when given. Null for [RecurrencePreset.none];
  /// [RecurrencePreset.custom] has no rule of its own (the form keeps the
  /// stored one).
  static String? ruleFor(
    RecurrencePreset preset, {
    DateTime? until,
    int? count,
  }) {
    final base = switch (preset) {
      RecurrencePreset.none || RecurrencePreset.custom => null,
      RecurrencePreset.daily => 'FREQ=DAILY',
      RecurrencePreset.weekdays => 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
      // On the start's weekday / day of month / date, which an RRULE
      // without BY-parts follows: moving the start moves the series.
      RecurrencePreset.weekly => 'FREQ=WEEKLY',
      RecurrencePreset.monthly => 'FREQ=MONTHLY',
      RecurrencePreset.yearly => 'FREQ=YEARLY',
    };
    if (base == null) return null;
    if (until != null) return '$base;UNTIL=${_untilWire(until)}';
    return count == null ? base : '$base;COUNT=$count';
  }

  /// The first day [rule] occurs on, for a series anchored on [anchorDay]:
  /// the anchor itself, unless a daily or weekly rule's `BYDAY` of plain
  /// weekdays leaves it out ("Hafta içi her gün" begun on a Sunday) — then
  /// the next day it names. Any other rule is taken to start on its anchor.
  static DateTime firstDay(String? rule, DateTime anchorDay) {
    final day = DateTime(anchorDay.year, anchorDay.month, anchorDay.day);
    final parts = <String, String>{};
    for (final part
        in (rule ?? '').toUpperCase().replaceFirst('RRULE:', '').split(';')) {
      final eq = part.indexOf('=');
      if (eq > 0) parts[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
    }
    final freq = parts['FREQ'];
    final byDay = parts['BYDAY']?.split(',').map((d) => d.trim()).toSet();
    if ((freq != 'DAILY' && freq != 'WEEKLY') ||
        byDay == null ||
        byDay.isEmpty ||
        !_days.toSet().containsAll(byDay)) {
      return day;
    }
    for (var i = 0; i < 7; i++) {
      final next = DateTime(day.year, day.month, day.day + i);
      if (byDay.contains(_days[next.weekday - 1])) return next;
    }
    return day;
  }

  /// [rule] ending on [lastDay] (inclusive): its `UNTIL` / `COUNT` replaced —
  /// "this and following" ends the series the day before the tapped
  /// occurrence (contract §10.2).
  static String endingOn(String rule, DateTime lastDay) {
    final kept = [
      for (final part in rule.split(';'))
        if (part.trim().isNotEmpty &&
            !part.toUpperCase().startsWith('UNTIL=') &&
            !part.toUpperCase().startsWith('COUNT='))
          part.trim(),
    ];
    return [...kept, 'UNTIL=${_untilWire(lastDay)}'].join(';');
  }

  static String _untilWire(DateTime day) => isoDate(day).replaceAll('-', '');

  /// `20261231`, `20261231T235959` (the account's wall clock) or
  /// `20261231T205959Z` (UTC) → the account's date.
  static DateTime? _untilDay(String? value, Duration? utcOffset) {
    if (value == null) return null;
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$')
        .firstMatch(value);
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i) ?? '0');
    if (m.group(7) == null) return DateTime(g(1), g(2), g(3));
    final utc = DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
    final local = utcOffset == null ? utc.toLocal() : utc.add(utcOffset);
    // [utcOffset] is the account's offset now, not on that day: across a
    // daylight-saving change a bare date's 23:59:59 reads as 00:59:59 (or
    // 00:29:59) the next day. It is still the day before.
    if (utcOffset != null &&
        local.hour == 0 &&
        local.minute % 30 == 29 &&
        local.second == 59) {
      return DateTime(local.year, local.month, local.day - 1);
    }
    return DateTime(local.year, local.month, local.day);
  }
}
