import 'date_utils.dart';
import 'json_read.dart';

/// Chain-day + perfect-day status (design §4.5 / api-samples statuses).
enum ChainStatus {
  completed,
  partial,
  todayPending,
  missed,
  perfect,
  noHabits;

  static ChainStatus fromApi(String value) {
    switch (value) {
      case 'completed':
        return ChainStatus.completed;
      case 'partial':
        return ChainStatus.partial;
      case 'today_pending':
        return ChainStatus.todayPending;
      case 'perfect':
        return ChainStatus.perfect;
      case 'no_habits':
        return ChainStatus.noHabits;
      case 'missed':
      default:
        return ChainStatus.missed;
    }
  }
}

class ChainDay {
  final DateTime date;
  final ChainStatus status;

  /// How much was done that day. The server sends it as an integer count on
  /// a partial day of a multi-count habit (`count` of `target_count`) and in
  /// the perfect-day chain (habits done); absent on other days.
  final int? completed;

  /// The day's target — the habit's `target_count`, or the habits that were
  /// active that day in the perfect-day chain. Present only with [completed].
  final int? possible;

  const ChainDay({
    required this.date,
    required this.status,
    this.completed,
    this.possible,
  });

  /// `completed`/`possible` arrive as integers, so they are read as counts;
  /// a boolean (an older or different payload) still parses, as 1 or 0,
  /// instead of failing the whole habit list.
  factory ChainDay.fromJson(Map<String, dynamic> json) => ChainDay(
        date: DateTime.parse(json['date'] as String),
        status: ChainStatus.fromApi('${json['status'] ?? 'missed'}'),
        completed: readIntOrNull(json['completed']),
        possible: readIntOrNull(json['possible']),
      );
}

class HabitToday {
  final DateTime date;
  final bool completed;
  final int count;

  const HabitToday({
    required this.date,
    required this.completed,
    required this.count,
  });

  factory HabitToday.fromJson(Map<String, dynamic> json) => HabitToday(
        date: DateTime.parse(json['date'] as String),
        completed: readBool(json['completed']),
        count: readInt(json['count']),
      );
}

/// A habit's log for one day: whether the day is done, and how many times.
typedef TodayLog = ({bool completed, int count});

/// The log a day is left with when it is set to [count] — what
/// `PUT /habits/:id/logs/:date` stores (meridian `Habit#set_log_count!`),
/// mirrored so a tap can show its result before the server answers.
///
/// A daily habit counts within the day: `0..target`, done at its target. A
/// weekly or monthly habit ([daily] false) counts *days* per period, so a day
/// is either done or not: any count above 0 marks it done and stores the
/// target, as the web checkbox does.
///
/// The request carries the count itself, worked out from what the user sees
/// when they tap, so a screen that is out of date can never flip a habit the
/// wrong way, and a retried or doubled request lands on the same state.
TodayLog loggedDay({
  required int count,
  required int target,
  bool daily = true,
}) {
  final top = target < 1 ? 1 : target;
  var next = count.clamp(0, top);
  if (next > 0 && !daily) next = top;
  return (completed: next >= top, count: next);
}

/// Weekly/monthly window; null for daily habits.
class HabitPeriod {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final int completedCount;
  final bool complete;

  const HabitPeriod({
    required this.rangeStart,
    required this.rangeEnd,
    required this.completedCount,
    required this.complete,
  });

  factory HabitPeriod.fromJson(Map<String, dynamic> json) => HabitPeriod(
        rangeStart: DateTime.parse(json['range_start'] as String),
        rangeEnd: DateTime.parse(json['range_end'] as String),
        completedCount: readInt(json['completed_count']),
        complete: readBool(json['complete']),
      );
}

/// A goal whose progress counts a habit's done days (`tracked_by_goals` of
/// `GET /habits/:id`): archiving the habit freezes it, deleting the habit
/// unlinks it.
class TrackingGoal {
  final int id;
  final String name;
  final String status;

  const TrackingGoal({
    required this.id,
    required this.name,
    required this.status,
  });

  factory TrackingGoal.fromJson(Map<String, dynamic> json) => TrackingGoal(
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'active',
      );
}

class Habit {
  final int id;
  final String name;
  final String description;
  final String frequency;
  final int targetCount;
  final String color;
  final int? goalId;
  final int currentStreak;
  final int longestStreak;
  final double completionRate30d;
  final HabitToday today;
  final HabitPeriod? period;
  final List<ChainDay> chain;

  /// Archived habits are frozen: they cannot be logged, leave the active
  /// list and Today, and are listed by `GET /habits?archived=true`.
  final bool archived;
  final DateTime? archivedAt;

  /// The first day a log can be set for (the day it was created, in the
  /// account's zone): earlier chain days are "missed" only because the
  /// habit did not exist yet. Null from an older server.
  final DateTime? startDate;

  /// Detail only (`GET /habits/:id`): the days a delete would remove, the
  /// complete days a habit goal counts, and the goals that count it.
  /// Null when the payload is a list item.
  final int? loggedDaysCount;
  final int? completedDaysCount;
  final List<TrackingGoal>? trackedByGoals;

  const Habit({
    required this.id,
    required this.name,
    required this.description,
    required this.frequency,
    required this.targetCount,
    required this.color,
    this.goalId,
    required this.currentStreak,
    required this.longestStreak,
    required this.completionRate30d,
    required this.today,
    this.period,
    required this.chain,
    this.archived = false,
    this.archivedAt,
    this.startDate,
    this.loggedDaysCount,
    this.completedDaysCount,
    this.trackedByGoals,
  });

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        frequency: (json['frequency'] as String?) ?? 'daily',
        targetCount: readInt(json['target_count'], fallback: 1),
        color: (json['color'] as String?) ?? '#B8860B',
        goalId: readIntOrNull(json['goal_id']),
        currentStreak: readInt(json['current_streak']),
        longestStreak: readInt(json['longest_streak']),
        completionRate30d: readDouble(json['completion_rate_30d']),
        today: HabitToday.fromJson(
            (json['today'] as Map<String, dynamic>?) ?? const {'date': '1970-01-01'}),
        period: json['period'] == null
            ? null
            : HabitPeriod.fromJson(json['period'] as Map<String, dynamic>),
        chain: ((json['chain'] as List?) ?? const [])
            .map((e) => ChainDay.fromJson(e as Map<String, dynamic>))
            .toList(),
        archived: readBool(json['archived']) || json['archived_at'] != null,
        archivedAt: parseDateTime(json['archived_at']),
        startDate: parseDateTime(json['start_date']),
        loggedDaysCount: readIntOrNull(json['logged_days_count']),
        completedDaysCount: readIntOrNull(json['completed_days_count']),
        trackedByGoals: json['tracked_by_goals'] is List
            ? [
                for (final g in json['tracked_by_goals'] as List)
                  if (g is Map<String, dynamic>) TrackingGoal.fromJson(g),
              ]
            : null,
      );

  /// Whether [day] can be logged: from [startDate] (when known) through
  /// [today] — the server's today — and never on an archived habit
  /// (`future_date`, `before_habit_start`, `habit_archived`).
  bool canLog(DateTime day) {
    if (archived) return false;
    final d = dateOnly(day);
    if (d.isAfter(dateOnly(today.date))) return false;
    final start = startDate;
    return start == null || !d.isBefore(dateOnly(start));
  }

  /// Weekly and monthly habits count days per period, not times per day.
  bool get isDaily => frequency == 'daily';

  /// Whether a day is logged as a count (a daily habit with a target above
  /// one: the − n/target + pill) rather than done or not (the check ring).
  bool get countsWithinDay => isDaily && targetCount > 1;

  /// What setting today's count to [count] leaves the day at ([loggedDay]).
  TodayLog logFor(int count) =>
      loggedDay(count: count, target: targetCount, daily: isDaily);

  /// The count a tap on the check sets: none when the day shows done, the
  /// target otherwise.
  int get checkCount => today.completed ? 0 : targetCount;

  Habit copyWith({HabitToday? today, HabitPeriod? period}) => Habit(
        id: id,
        name: name,
        description: description,
        frequency: frequency,
        targetCount: targetCount,
        color: color,
        goalId: goalId,
        currentStreak: currentStreak,
        longestStreak: longestStreak,
        completionRate30d: completionRate30d,
        today: today ?? this.today,
        period: period ?? this.period,
        chain: chain,
        archived: archived,
        archivedAt: archivedAt,
        startDate: startDate,
        loggedDaysCount: loggedDaysCount,
        completedDaysCount: completedDaysCount,
        trackedByGoals: trackedByGoals,
      );

  /// This habit's [day] as the chain shows it, set to [count] — what a
  /// past-day log shows before the server answers (see [loggedDay]). Only
  /// the chain cell changes; streaks and rates come with the answer.
  Habit withDayCount(DateTime day, int count) {
    final d = dateOnly(day);
    final log = logFor(count);
    final isToday = d == dateOnly(today.date);
    ChainDay cell(ChainDay c) {
      if (dateOnly(c.date) != d) return c;
      final status = log.completed
          ? ChainStatus.completed
          : log.count > 0
              ? ChainStatus.partial
              : isToday
                  ? ChainStatus.todayPending
                  : ChainStatus.missed;
      return ChainDay(
        date: c.date,
        status: status,
        completed: status == ChainStatus.partial ? log.count : null,
        possible: status == ChainStatus.partial ? targetCount : null,
      );
    }

    final next = isToday ? withToday(log) : this;
    return Habit(
      id: id,
      name: name,
      description: description,
      frequency: frequency,
      targetCount: targetCount,
      color: color,
      goalId: goalId,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      completionRate30d: completionRate30d,
      today: next.today,
      period: next.period,
      chain: [for (final c in chain) cell(c)],
      archived: archived,
      archivedAt: archivedAt,
      startDate: startDate,
      loggedDaysCount: loggedDaysCount,
      completedDaysCount: completedDaysCount,
      trackedByGoals: trackedByGoals,
    );
  }

  /// The count [day] shows in the chain: the stored count of a partial day,
  /// the target for a complete one, 0 otherwise.
  int countOn(DateTime day) {
    final d = dateOnly(day);
    if (d == dateOnly(today.date)) return today.count;
    for (final c in chain) {
      if (dateOnly(c.date) != d) continue;
      return switch (c.status) {
        ChainStatus.completed || ChainStatus.perfect => targetCount,
        ChainStatus.partial => c.completed ?? 1,
        _ => 0,
      };
    }
    return 0;
  }

  /// This habit with today's log set to [log], before the server answers,
  /// and a weekly/monthly period count that follows the day's completion.
  /// Streaks and rates are left alone — the server's response replaces them.
  ///
  /// It sets rather than toggles: on a habit whose log already is [log] it
  /// changes nothing, so a pending tap can be applied to every refetch.
  Habit withToday(TodayLog log) {
    if (log.completed == today.completed && log.count == today.count) {
      return this;
    }
    var nextPeriod = period;
    if (nextPeriod != null && log.completed != today.completed) {
      final done = nextPeriod.completedCount + (log.completed ? 1 : -1);
      final clamped = done < 0 ? 0 : done;
      nextPeriod = HabitPeriod(
        rangeStart: nextPeriod.rangeStart,
        rangeEnd: nextPeriod.rangeEnd,
        completedCount: clamped,
        complete: clamped >= targetCount,
      );
    }
    return copyWith(
      today: HabitToday(
        date: today.date,
        completed: log.completed,
        count: log.count,
      ),
      period: nextPeriod,
    );
  }
}

class PerfectDay {
  final List<ChainDay> chain;
  final int currentStreak;
  final int longestStreak;

  const PerfectDay({
    required this.chain,
    required this.currentStreak,
    required this.longestStreak,
  });

  factory PerfectDay.fromJson(Map<String, dynamic> json) => PerfectDay(
        chain: ((json['chain'] as List?) ?? const [])
            .map((e) => ChainDay.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentStreak: readInt(json['current_streak']),
        longestStreak: readInt(json['longest_streak']),
      );
}

class HabitsBundle {
  final List<Habit> habits;
  final int completedToday;
  final int totalActive;
  final PerfectDay perfectDay;

  const HabitsBundle({
    required this.habits,
    required this.completedToday,
    required this.totalActive,
    required this.perfectDay,
  });

  factory HabitsBundle.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map<String, dynamic>?) ?? const {};
    return HabitsBundle(
      habits: ((json['habits'] as List?) ?? const [])
          .map((e) => Habit.fromJson(e as Map<String, dynamic>))
          .toList(),
      completedToday: readInt(meta['completed_today']),
      totalActive: readInt(meta['total_active']),
      perfectDay: PerfectDay.fromJson(
          (meta['perfect_day'] as Map<String, dynamic>?) ?? const {}),
    );
  }

  /// The list with today's log of habit [habitId] set to [log] (per
  /// [Habit.withToday]), and the "X / Y done" count recounted the way the
  /// server counts it (habits whose today is complete). Setting rather than
  /// toggling, it changes nothing — header included — on a list that already
  /// has that log. Unchanged when the habit is not listed.
  HabitsBundle withHabitToday(int habitId, TodayLog log) {
    final index = habits.indexWhere((h) => h.id == habitId);
    if (index < 0) return this;
    final habit = habits[index];
    final updated = habit.withToday(log);
    if (identical(updated, habit)) return this;
    final next = [...habits]..[index] = updated;
    return HabitsBundle(
      habits: next,
      completedToday: next.where((h) => h.today.completed).length,
      totalActive: totalActive,
      perfectDay: perfectDay,
    );
  }

  /// The day this list's "today" is — the server's, as the habits' `today`
  /// blocks give it. Null for an empty list.
  DateTime? get day => habits.firstOrNull?.today.date;

  /// Whether [result], the answer to a habit's log, is about the day this
  /// list shows. A tap sent just before midnight can be answered after the
  /// list has moved on to the new day, or the server's day can have moved on
  /// while the list still shows the old one.
  bool isDayOf(HabitLogResult result) {
    final listed = day;
    return listed == null || listed == result.habit.today.date;
  }

  /// Folds the answer to a habit's log in: the habit exactly as the server
  /// now has it and, with [header], the refreshed header too (done count,
  /// active count, perfect-day chain). Nothing else in the list can change by
  /// logging one habit.
  ///
  /// Pass `header: false` while other taps are still waiting for the server:
  /// this response knows nothing of them, so taking its header would step
  /// the done count back. The count is then recounted the way
  /// [withHabitToday] counts it, and the rest of the header stays.
  ///
  /// A response about another day than the list's (see [isDayOf]) leaves
  /// the list as it is: it would put one day's log on the other day's list.
  HabitsBundle merge(HabitLogResult result, {bool header = true}) {
    if (!isDayOf(result)) return this;
    final next = [
      for (final h in habits) h.id == result.habit.id ? result.habit : h,
    ];
    return HabitsBundle(
      habits: next,
      completedToday: header
          ? result.completedToday
          : next.where((h) => h.today.completed).length,
      totalActive: header ? result.totalActive : totalActive,
      perfectDay: header ? result.perfectDay : perfectDay,
    );
  }
}

/// One day's log of a habit, as the server stored it.
class HabitDayLog {
  final DateTime date;
  final int count;
  final bool completed;

  const HabitDayLog({
    required this.date,
    required this.count,
    required this.completed,
  });

  static HabitDayLog? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final date = DateTime.tryParse('${json['date']}');
    if (date == null) return null;
    return HabitDayLog(
      date: date,
      count: readInt(json['count']),
      completed: readBool(json['completed']),
    );
  }
}

/// The answer to a habit's log (`PUT /habits/:id/logs/:date`): the habit as
/// `GET /habits` lists it — its `today` block is the server's today, whichever
/// day was set — the list's header, and the day that was set ([log]).
class HabitLogResult {
  final Habit habit;
  final int completedToday;
  final int totalActive;
  final PerfectDay perfectDay;
  final HabitDayLog? log;

  const HabitLogResult({
    required this.habit,
    required this.completedToday,
    required this.totalActive,
    required this.perfectDay,
    this.log,
  });

  factory HabitLogResult.fromJson(Map<String, dynamic> json) {
    final habitJson = (json['habit'] as Map<String, dynamic>?) ?? json;
    final meta = (json['meta'] as Map<String, dynamic>?) ?? const {};
    return HabitLogResult(
      habit: Habit.fromJson(habitJson),
      completedToday: readInt(meta['completed_today']),
      totalActive: readInt(meta['total_active']),
      perfectDay: PerfectDay.fromJson(
          (meta['perfect_day'] as Map<String, dynamic>?) ?? const {}),
      log: HabitDayLog.fromJson(json['log']),
    );
  }
}

/// Create/update body for a habit.
class HabitInput {
  final String name;
  final String frequency;
  final int targetCount;
  final String color;
  final String? description;
  final int? goalId;

  const HabitInput({
    required this.name,
    required this.frequency,
    required this.targetCount,
    required this.color,
    this.description,
    this.goalId,
  });

  String? get _description {
    final text = description?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// `POST /habits`: every field.
  Map<String, dynamic> toJson() => {
        'name': name,
        'frequency': frequency,
        'target_count': targetCount,
        'color': color,
        'description': _description,
        'goal_id': goalId,
      };

  /// `PATCH /habits/:id`: only what differs from [before] — the server
  /// applies every key it gets, nulls included, so a field the form left
  /// alone (a description written on the web, the goal it serves) is never
  /// sent back over a newer value. Empty when nothing changed.
  Map<String, dynamic> changesFrom(Habit before) {
    final previousDescription =
        before.description.trim().isEmpty ? null : before.description.trim();
    return {
      if (name != before.name) 'name': name,
      if (frequency != before.frequency) 'frequency': frequency,
      if (targetCount != before.targetCount) 'target_count': targetCount,
      if (color.toUpperCase() != before.color.toUpperCase()) 'color': color,
      if (_description != previousDescription) 'description': _description,
      if (goalId != before.goalId) 'goal_id': goalId,
    };
  }
}
