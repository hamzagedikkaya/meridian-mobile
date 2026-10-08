import 'event.dart';
import 'habit.dart';
import 'json_read.dart';
import 'todo.dart';

/// Compact habit shape used only on /home (no chain/description).
class HomeHabit {
  final int id;
  final String name;
  final String color;
  final int targetCount;
  final bool completedToday;
  final int todayCount;
  final int currentStreak;

  const HomeHabit({
    required this.id,
    required this.name,
    required this.color,
    required this.targetCount,
    required this.completedToday,
    required this.todayCount,
    required this.currentStreak,
  });

  factory HomeHabit.fromJson(Map<String, dynamic> json) => HomeHabit(
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        color: (json['color'] as String?) ?? '#B8860B',
        targetCount: readInt(json['target_count'], fallback: 1),
        completedToday: readBool(json['completed_today']),
        todayCount: readInt(json['today_count']),
        currentStreak: readInt(json['current_streak']),
      );

  /// What setting today's count to [count] leaves the day at ([loggedDay]).
  /// `/home` does not say how often the habit repeats; [daily] comes from
  /// the Habits list when it is loaded, and is assumed otherwise.
  TodayLog logFor(int count, {bool daily = true}) =>
      loggedDay(count: count, target: targetCount, daily: daily);

  /// This row with today's log set to [log], before the server answers. The
  /// streak waits for the refetch. Unchanged when the log already is [log].
  HomeHabit withToday(TodayLog log) {
    if (log.completed == completedToday && log.count == todayCount) {
      return this;
    }
    return HomeHabit(
      id: id,
      name: name,
      color: color,
      targetCount: targetCount,
      completedToday: log.completed,
      todayCount: log.count,
      currentStreak: currentStreak,
    );
  }
}

/// Compact goal shape used only on /home.
class HomeGoal {
  final int id;
  final String name;
  final String color;
  final double progressPercent;

  const HomeGoal({
    required this.id,
    required this.name,
    required this.color,
    required this.progressPercent,
  });

  factory HomeGoal.fromJson(Map<String, dynamic> json) => HomeGoal(
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        color: (json['color'] as String?) ?? '#B8860B',
        progressPercent: readDouble(json['progress_percent']),
      );
}

class SpendingPoint {
  final DateTime date;
  final int cents;

  const SpendingPoint({required this.date, required this.cents});

  factory SpendingPoint.fromJson(Map<String, dynamic> json) => SpendingPoint(
        date: DateTime.parse(json['date'] as String),
        cents: readInt(json['cents']),
      );
}

class HomeSummary {
  /// The account's local date this payload was computed for (the server's
  /// "today"); null from a server that predates G1.
  final DateTime? today;
  final String currency;
  final int subunitToUnit;
  final int monthNetCents;
  final int activeStreaks;
  final int openTodos;
  final int overdueCount;
  final int todayEventsCount;
  final int habitCompletionPct;
  final List<SpendingPoint> spending7d;
  final List<HomeHabit> todayHabits;
  final List<Todo> upcomingTodos;
  final List<Event> todayEvents;
  final List<HomeGoal> activeGoals;
  final PerfectDay perfectDay;

  const HomeSummary({
    this.today,
    required this.currency,
    required this.subunitToUnit,
    required this.monthNetCents,
    required this.activeStreaks,
    required this.openTodos,
    required this.overdueCount,
    required this.todayEventsCount,
    required this.habitCompletionPct,
    required this.spending7d,
    required this.todayHabits,
    required this.upcomingTodos,
    required this.todayEvents,
    required this.activeGoals,
    required this.perfectDay,
  });

  factory HomeSummary.fromJson(Map<String, dynamic> json) => HomeSummary(
        today: DateTime.tryParse('${json['today']}'),
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: readInt(json['subunit_to_unit'], fallback: 100),
        monthNetCents: readInt(json['month_net_cents']),
        activeStreaks: readInt(json['active_streaks']),
        openTodos: readInt(json['open_todos']),
        overdueCount: readInt(json['overdue_count']),
        todayEventsCount: readInt(json['today_events_count']),
        habitCompletionPct: readInt(json['habit_completion_pct']),
        spending7d: ((json['spending_7d'] as List?) ?? const [])
            .map((e) => SpendingPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        todayHabits: ((json['today_habits'] as List?) ?? const [])
            .map((e) => HomeHabit.fromJson(e as Map<String, dynamic>))
            .toList(),
        upcomingTodos: ((json['upcoming_todos'] as List?) ?? const [])
            .map((e) => Todo.fromJson(e as Map<String, dynamic>))
            .toList(),
        todayEvents: ((json['today_events'] as List?) ?? const [])
            .map((e) => Event.fromJson(e as Map<String, dynamic>))
            .toList(),
        activeGoals: ((json['active_goals'] as List?) ?? const [])
            .map((e) => HomeGoal.fromJson(e as Map<String, dynamic>))
            .toList(),
        perfectDay: PerfectDay.fromJson(
            (json['perfect_day'] as Map<String, dynamic>?) ?? const {}),
      );

  HomeSummary copyWith({
    int? openTodos,
    int? overdueCount,
    List<HomeHabit>? todayHabits,
    List<Todo>? upcomingTodos,
  }) =>
      HomeSummary(
        today: today,
        currency: currency,
        subunitToUnit: subunitToUnit,
        monthNetCents: monthNetCents,
        activeStreaks: activeStreaks,
        openTodos: openTodos ?? this.openTodos,
        overdueCount: overdueCount ?? this.overdueCount,
        todayEventsCount: todayEventsCount,
        habitCompletionPct: habitCompletionPct,
        spending7d: spending7d,
        todayHabits: todayHabits ?? this.todayHabits,
        upcomingTodos: upcomingTodos ?? this.upcomingTodos,
        todayEvents: todayEvents,
        activeGoals: activeGoals,
        perfectDay: perfectDay,
      );

  /// Today's habit [habitId] with its log for today set to [log]. Setting
  /// rather than toggling, it changes nothing on a summary that already has
  /// that log — a refetch answered after the server applied the tap — so a
  /// pending tap can be applied to every refetch. Unchanged when the habit
  /// is not on Today.
  HomeSummary withHabitToday(int habitId, TodayLog log) {
    final index = todayHabits.indexWhere((h) => h.id == habitId);
    if (index < 0) return this;
    final row = todayHabits[index];
    final updated = row.withToday(log);
    if (identical(updated, row)) return this;
    return copyWith(todayHabits: [...todayHabits]..[index] = updated);
  }

  /// Whether [result], the answer to a habit's log, is about the day this
  /// summary shows — not so for a tap that straddled midnight. Always true
  /// for a summary without a date (a server from before G1).
  bool isDayOf(HabitLogResult result) {
    final day = today;
    return day == null || day == result.habit.today.date;
  }

  /// Today's row of the habit in [result], the answer to its log, as the
  /// server now has it: its log for today and its streak. Setting rather
  /// than flipping, it changes nothing when applied again. The numbers
  /// derived from every habit (completion %, active streaks, the perfect
  /// day) wait for the refetch. Unchanged when the habit is not on Today, or
  /// when the answer is about another day than this summary ([isDayOf]).
  HomeSummary merge(HabitLogResult result) {
    final habit = result.habit;
    if (!isDayOf(result)) return this;
    if (!todayHabits.any((h) => h.id == habit.id)) return this;
    return copyWith(todayHabits: [
      for (final h in todayHabits)
        h.id == habit.id
            ? HomeHabit(
                id: h.id,
                name: h.name,
                color: h.color,
                targetCount: h.targetCount,
                completedToday: habit.today.completed,
                todayCount: habit.today.count,
                currentStreak: habit.currentStreak,
              )
            : h,
    ]);
  }

  /// Todo [todoId] with its status set to [status]; when that moves it
  /// between open and done, the open and overdue counts — the overdue one
  /// feeds the Today tab's badge — move by one with it. The row stays listed,
  /// checked, until the refetch drops it.
  ///
  /// Setting rather than toggling, it changes nothing on a summary that
  /// already has the todo at [status] — a refetch answered after the server
  /// applied the tap — so a pending tap can be applied to every refetch.
  /// Unchanged when the todo is not on Today.
  HomeSummary withTodoStatus(int todoId, String status) {
    final index = upcomingTodos.indexWhere((t) => t.id == todoId);
    if (index < 0) return this;
    final todo = upcomingTodos[index];
    if (todo.status == status) return this;
    final nowDone = status == 'done';
    final step = nowDone == todo.isDone ? 0 : (nowDone ? -1 : 1);
    int moved(int value) => value + step < 0 ? 0 : value + step;
    return copyWith(
      upcomingTodos: [...upcomingTodos]
        ..[index] = todo.copyWith(status: status),
      openTodos: moved(openTodos),
      overdueCount: todo.overdue ? moved(overdueCount) : overdueCount,
    );
  }

  /// [todo] reopened: set back to open where it is listed, or — when a
  /// refetch has already dropped it from Today's open todos — put back at
  /// [index], with the open and overdue counts moving with it. Setting
  /// rather than toggling, it changes nothing on a summary that already
  /// lists it open.
  HomeSummary withTodoReopened(Todo todo, {required int index}) {
    if (upcomingTodos.any((t) => t.id == todo.id)) {
      return withTodoStatus(todo.id, 'pending');
    }
    final open = todo.copyWith(status: 'pending');
    return copyWith(
      upcomingTodos: [...upcomingTodos]
        ..insert(index.clamp(0, upcomingTodos.length), open),
      openTodos: openTodos + 1,
      overdueCount: todo.overdue ? overdueCount + 1 : overdueCount,
    );
  }
}
