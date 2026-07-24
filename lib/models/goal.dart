import 'date_utils.dart';

class DeadlineBadge {
  /// "overdue" | "today" | "soon" | "far".
  final String state;
  final int days;

  const DeadlineBadge({required this.state, required this.days});

  factory DeadlineBadge.fromJson(Map<String, dynamic> json) => DeadlineBadge(
        state: (json['state'] as String?) ?? 'far',
        days: (json['days'] as num?)?.toInt() ?? 0,
      );
}

/// Composite target: an Account, a Habit, or null. Only the fields relevant to
/// `type` are populated.
class GoalRelated {
  final String type;
  final int id;
  final String name;
  final int? currentStreak;
  final int? completedDays;
  final int? balanceCents;
  final String? currency;
  final int? subunitToUnit;

  const GoalRelated({
    required this.type,
    required this.id,
    required this.name,
    this.currentStreak,
    this.completedDays,
    this.balanceCents,
    this.currency,
    this.subunitToUnit,
  });

  factory GoalRelated.fromJson(Map<String, dynamic> json) => GoalRelated(
        type: (json['type'] as String?) ?? '',
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        currentStreak: (json['current_streak'] as num?)?.toInt(),
        completedDays: (json['completed_days'] as num?)?.toInt(),
        balanceCents: (json['balance_cents'] as num?)?.toInt(),
        currency: json['currency'] as String?,
        subunitToUnit: (json['subunit_to_unit'] as num?)?.toInt(),
      );
}

class Goal {
  final int id;
  final String name;
  final String description;
  final String targetType;
  final String status;
  final String color;
  final String unit;
  final DateTime? deadline;
  final int daysRemaining;
  final DeadlineBadge? deadlineBadge;
  final double targetValue;
  final double currentValue;
  final double progressPercent;
  final GoalRelated? related;

  const Goal({
    required this.id,
    required this.name,
    required this.description,
    required this.targetType,
    required this.status,
    required this.color,
    required this.unit,
    this.deadline,
    required this.daysRemaining,
    this.deadlineBadge,
    required this.targetValue,
    required this.currentValue,
    required this.progressPercent,
    this.related,
  });

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: (json['id'] as num).toInt(),
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        targetType: (json['target_type'] as String?) ?? 'custom',
        status: (json['status'] as String?) ?? 'active',
        color: (json['color'] as String?) ?? '#B8860B',
        unit: (json['unit'] as String?) ?? '',
        deadline: parseDateTime(json['deadline']),
        daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 0,
        deadlineBadge: json['deadline_badge'] == null
            ? null
            : DeadlineBadge.fromJson(
                json['deadline_badge'] as Map<String, dynamic>),
        targetValue: (json['target_value'] as num?)?.toDouble() ?? 0,
        currentValue: (json['current_value'] as num?)?.toDouble() ?? 0,
        progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0,
        related: json['related'] == null
            ? null
            : GoalRelated.fromJson(json['related'] as Map<String, dynamic>),
      );
}

class GoalsBundle {
  final List<Goal> active;
  final List<Goal> achieved;
  final List<Goal> abandoned;

  const GoalsBundle({
    required this.active,
    required this.achieved,
    required this.abandoned,
  });

  factory GoalsBundle.fromJson(Map<String, dynamic> json) => GoalsBundle(
        active: _list(json['active']),
        achieved: _list(json['achieved']),
        abandoned: _list(json['abandoned']),
      );

  static List<Goal> _list(Object? raw) => ((raw as List?) ?? const [])
      .map((e) => Goal.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Create/update body — `related` is the composite "Account-12" | "Habit-7" | "none".
class GoalInput {
  final String name;
  final String? description;
  final String targetType;
  final String color;
  final String? unit;
  final DateTime? deadline;
  final num? targetValue;
  final String related;

  const GoalInput({
    required this.name,
    this.description,
    required this.targetType,
    required this.color,
    this.unit,
    this.deadline,
    this.targetValue,
    this.related = 'none',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'target_type': targetType,
        'color': color,
        'unit': unit,
        'deadline': deadline == null ? null : isoDate(deadline!),
        'target_value': targetValue,
        'related': related,
      };
}
