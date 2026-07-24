import 'event.dart';
import 'habit.dart';
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
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        color: (json['color'] as String?) ?? '#B8860B',
        targetCount: (json['target_count'] as num?)?.toInt() ?? 1,
        completedToday: (json['completed_today'] as bool?) ?? false,
        todayCount: (json['today_count'] as num?)?.toInt() ?? 0,
        currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
      );
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
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        color: (json['color'] as String?) ?? '#B8860B',
        progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0,
      );
}

class SpendingPoint {
  final DateTime date;
  final int cents;

  const SpendingPoint({required this.date, required this.cents});

  factory SpendingPoint.fromJson(Map<String, dynamic> json) => SpendingPoint(
        date: DateTime.parse(json['date'] as String),
        cents: (json['cents'] as num?)?.toInt() ?? 0,
      );
}

class HomeSummary {
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
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: (json['subunit_to_unit'] as num?)?.toInt() ?? 100,
        monthNetCents: (json['month_net_cents'] as num?)?.toInt() ?? 0,
        activeStreaks: (json['active_streaks'] as num?)?.toInt() ?? 0,
        openTodos: (json['open_todos'] as num?)?.toInt() ?? 0,
        overdueCount: (json['overdue_count'] as num?)?.toInt() ?? 0,
        todayEventsCount: (json['today_events_count'] as num?)?.toInt() ?? 0,
        habitCompletionPct:
            (json['habit_completion_pct'] as num?)?.toInt() ?? 0,
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
}
