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
  final bool? completed;
  final bool? possible;

  const ChainDay({
    required this.date,
    required this.status,
    this.completed,
    this.possible,
  });

  factory ChainDay.fromJson(Map<String, dynamic> json) => ChainDay(
        date: DateTime.parse(json['date'] as String),
        status: ChainStatus.fromApi((json['status'] as String?) ?? 'missed'),
        completed: json['completed'] as bool?,
        possible: json['possible'] as bool?,
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
        completed: (json['completed'] as bool?) ?? false,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
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
        completedCount: (json['completed_count'] as num?)?.toInt() ?? 0,
        complete: (json['complete'] as bool?) ?? false,
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
  });

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
        id: (json['id'] as num).toInt(),
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        frequency: (json['frequency'] as String?) ?? 'daily',
        targetCount: (json['target_count'] as num?)?.toInt() ?? 1,
        color: (json['color'] as String?) ?? '#B8860B',
        goalId: (json['goal_id'] as num?)?.toInt(),
        currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
        longestStreak: (json['longest_streak'] as num?)?.toInt() ?? 0,
        completionRate30d:
            (json['completion_rate_30d'] as num?)?.toDouble() ?? 0,
        today: HabitToday.fromJson(
            (json['today'] as Map<String, dynamic>?) ?? const {'date': '1970-01-01'}),
        period: json['period'] == null
            ? null
            : HabitPeriod.fromJson(json['period'] as Map<String, dynamic>),
        chain: ((json['chain'] as List?) ?? const [])
            .map((e) => ChainDay.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
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
        currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
        longestStreak: (json['longest_streak'] as num?)?.toInt() ?? 0,
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
      completedToday: (meta['completed_today'] as num?)?.toInt() ?? 0,
      totalActive: (meta['total_active'] as num?)?.toInt() ?? 0,
      perfectDay: PerfectDay.fromJson(
          (meta['perfect_day'] as Map<String, dynamic>?) ?? const {}),
    );
  }
}

/// PATCH /habits/:id/toggle_today → updated habit + refreshed header meta.
class ToggleResult {
  final Habit habit;
  final int completedToday;
  final int totalActive;
  final PerfectDay perfectDay;

  const ToggleResult({
    required this.habit,
    required this.completedToday,
    required this.totalActive,
    required this.perfectDay,
  });

  factory ToggleResult.fromJson(Map<String, dynamic> json) {
    final habitJson = (json['habit'] as Map<String, dynamic>?) ?? json;
    final meta = (json['meta'] as Map<String, dynamic>?) ?? const {};
    return ToggleResult(
      habit: Habit.fromJson(habitJson),
      completedToday: (meta['completed_today'] as num?)?.toInt() ?? 0,
      totalActive: (meta['total_active'] as num?)?.toInt() ?? 0,
      perfectDay: PerfectDay.fromJson(
          (meta['perfect_day'] as Map<String, dynamic>?) ?? const {}),
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

  Map<String, dynamic> toJson() => {
        'name': name,
        'frequency': frequency,
        'target_count': targetCount,
        'color': color,
        'description': description,
        'goal_id': goalId,
      };
}
