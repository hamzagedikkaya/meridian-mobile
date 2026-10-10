/// How the Agenda lays its days out (design-analysis §7.4): every event's
/// occurrences in a window, todos and events merged day by day, and the
/// groups of the "Yaklaşan" and "Tamamlanan" views. Pure: no widgets, no
/// providers, so the rules are tested on their own.
library;

import '../../../core/formats.dart';
import '../../../data/providers.dart' show EventWindow;
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/event.dart';
import '../../../models/todo.dart';

/// One occurrence of an event: the day it takes place on.
typedef Occurrence = ({DateTime day, Event event});

/// Every occurrence of [events] within [window], by day, then all-day
/// events first and the rest by their time of day (a series by its own
/// time of day, never by its first occurrence's date: contract §3). An
/// event without `occurrences` (`/home`'s) occurs on [fallbackDay].
List<Occurrence> occurrencesIn(
  Iterable<Event> events,
  EventWindow window, {
  DateTime? fallbackDay,
}) {
  final out = <Occurrence>[];
  for (final event in events) {
    final days = event.occurrences.isNotEmpty
        ? event.occurrences
        : [?(fallbackDay ?? event.startDay)];
    for (final day in days) {
      final on = dateOnly(day);
      if (window.contains(on)) out.add((day: on, event: event));
    }
  }
  out.sort((a, b) {
    final byDay = a.day.compareTo(b.day);
    if (byDay != 0) return byDay;
    final byTime = a.event.minuteOfDay.compareTo(b.event.minuteOfDay);
    if (byTime != 0) return byTime;
    return a.event.title.compareTo(b.event.title);
  });
  return out;
}

/// "Bugün · 4 Ekim", "Yarın · 5 Ekim", "Salı · 6 Ekim" — a day's heading in
/// a list of todos or events.
String dayHeading(AppL10n l, DateTime day, DateTime today) {
  final withYear = day.year != today.year;
  final date = formatDate(day, withYear: withYear);
  final delta = calendarDaysBetween(today, day);
  if (delta >= -1 && delta <= 1) return '${l.relativeDay(day)} · $date';
  return '${formatWeekday(day)} · $date';
}

/// Whole calendar days from [from] to [to] — a 23- or 25-hour day is still
/// one.
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// One row of an agenda day: a todo, or an event's occurrence.
sealed class AgendaEntry {
  const AgendaEntry();
}

final class TodoEntry extends AgendaEntry {
  final Todo todo;
  const TodoEntry(this.todo);
}

final class EventEntry extends AgendaEntry {
  final Occurrence occurrence;
  const EventEntry(this.occurrence);

  Event get event => occurrence.event;
  DateTime get day => occurrence.day;
}

/// Which kind of group a day of the agenda is.
enum AgendaGroupKind {
  /// Open todos already due: shown first, only when there are any.
  overdue,

  /// Today: always shown, empty or not.
  today,

  /// Tomorrow and the five days after it: shown when they hold something.
  day,

  /// Everything from a week ahead on: todos and the window's events.
  later,
}

/// A heading and its rows.
class AgendaGroup {
  final AgendaGroupKind kind;

  /// The day it is about; null for [AgendaGroupKind.overdue] and
  /// [AgendaGroupKind.later].
  final DateTime? day;
  final List<AgendaEntry> entries;

  const AgendaGroup(this.kind, this.day, this.entries);

  Iterable<Todo> get todos => entries.whereType<TodoEntry>().map((e) => e.todo);
}

/// The days the "Yaklaşan" view names one by one: today, tomorrow and the
/// five after it. Further out is "Sonra".
const agendaNamedDays = 7;

/// The "Yaklaşan" view (§7.4): [todos] — the open ones, with any checked
/// off a moment ago still among them — and the [occurrences] of the event
/// window, merged day by day on the account's [today]:
///
/// 1. **Gecikmiş**: open todos already due (the server's `overdue`), only
///    when there are any;
/// 2. **Bugün**: always, empty or not;
/// 3. tomorrow and the next five days, each only with something in it;
/// 4. **Sonra**: todos due a week or more ahead, and the window's events
///    from then on.
///
/// Within a day: all-day events first, then timed events and todos by their
/// time, then todos due on the day without a time (in the order given).
/// Todos without a date are the inbox's, not listed here.
List<AgendaGroup> upcomingGroups({
  required List<Todo> todos,
  required List<Occurrence> occurrences,
  required DateTime today,
}) {
  final day0 = dateOnly(today);
  final overdue = <AgendaEntry>[];
  final byDay = <int, List<AgendaEntry>>{};
  final later = <AgendaEntry>[];
  DateTime dayOf(AgendaEntry e) => switch (e) {
    TodoEntry(:final todo) => todo.dueDay!,
    EventEntry(:final day) => day,
  };

  void place(AgendaEntry entry, DateTime day) {
    final delta = calendarDaysBetween(day0, day);
    if (delta >= agendaNamedDays) {
      later.add(entry);
    } else {
      byDay.putIfAbsent(delta, () => []).add(entry);
    }
  }

  for (final todo in todos) {
    final due = todo.dueDay;
    if (due == null) continue;
    // The server's flag: a row ticked off stays put until the refetch
    // drops it (only open todos are ever overdue).
    if (todo.overdue || due.isBefore(day0)) {
      overdue.add(TodoEntry(todo));
    } else {
      place(TodoEntry(todo), due);
    }
  }
  for (final o in occurrences) {
    if (o.day.isBefore(day0)) continue;
    place(EventEntry(o), o.day);
  }

  final groups = <AgendaGroup>[
    if (overdue.isNotEmpty) AgendaGroup(AgendaGroupKind.overdue, null, overdue),
    AgendaGroup(AgendaGroupKind.today, day0, inDayOrder(byDay[0] ?? const [])),
    for (var delta = 1; delta < agendaNamedDays; delta++)
      if (byDay[delta] case final entries? when entries.isNotEmpty)
        AgendaGroup(
          AgendaGroupKind.day,
          DateTime(day0.year, day0.month, day0.day + delta),
          inDayOrder(entries),
        ),
  ];
  if (later.isNotEmpty) {
    // By day, then as within a day.
    final days = <DateTime, List<AgendaEntry>>{};
    for (final e in later) {
      days.putIfAbsent(dayOf(e), () => []).add(e);
    }
    final ordered = days.keys.toList()..sort();
    groups.add(
      AgendaGroup(AgendaGroupKind.later, null, [
        for (final d in ordered) ...inDayOrder(days[d]!),
      ]),
    );
  }
  return groups;
}

/// A day's rows in agenda order: all-day events, then timed events and
/// todos by their time of day, then todos with only a date. Stable: rows
/// that tie keep the order given.
List<AgendaEntry> inDayOrder(List<AgendaEntry> entries) {
  int rank(AgendaEntry e) => switch (e) {
    EventEntry(:final event) => event.minuteOfDay < 0 ? 0 : 1,
    TodoEntry(:final todo) => parseDueTime(todo.dueTime) == null ? 2 : 1,
  };
  int minute(AgendaEntry e) => switch (e) {
    EventEntry(:final event) => event.minuteOfDay,
    TodoEntry(:final todo) => switch (parseDueTime(todo.dueTime)) {
      (:final hour, :final minute) => hour * 60 + minute,
      null => 0,
    },
  };
  final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])];
  indexed.sort((a, b) {
    final byRank = rank(a.$2).compareTo(rank(b.$2));
    if (byRank != 0) return byRank;
    final byMinute = minute(a.$2).compareTo(minute(b.$2));
    if (byMinute != 0) return byMinute;
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, e) in indexed) e];
}

/// The "Tamamlanan" view: finished [todos], newest first as given, under
/// the day each was finished on (those without a finish time last).
List<({DateTime? day, List<Todo> todos})> doneGroups(List<Todo> todos) {
  final byDay = <DateTime?, List<Todo>>{};
  for (final todo in todos) {
    final at = todo.completedAt;
    byDay.putIfAbsent(at == null ? null : dateOnly(at), () => []).add(todo);
  }
  final dated = [
    for (final MapEntry(:key, :value) in byDay.entries)
      if (key != null) (day: key, todos: value),
  ]..sort((a, b) => b.day.compareTo(a.day));
  return [...dated, if (byDay[null] case final rest?) (day: null, todos: rest)];
}
