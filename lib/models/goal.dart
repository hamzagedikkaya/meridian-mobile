import 'date_utils.dart';
import 'json_read.dart';

class DeadlineBadge {
  /// "overdue" | "today" | "soon" | "far".
  final String state;
  final int days;

  const DeadlineBadge({required this.state, required this.days});

  factory DeadlineBadge.fromJson(Map<String, dynamic> json) => DeadlineBadge(
        state: (json['state'] as String?) ?? 'far',
        days: readInt(json['days']),
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

  /// The `related` value that names this link on a write: `"Account-12"`,
  /// `"Habit-7"`.
  String get ref => '$type-$id';

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
        id: readInt(json['id']),
        name: (json['name'] as String?) ?? '',
        currentStreak: readIntOrNull(json['current_streak']),
        completedDays: readIntOrNull(json['completed_days']),
        balanceCents: readIntOrNull(json['balance_cents']),
        currency: json['currency'] as String?,
        subunitToUnit: readIntOrNull(json['subunit_to_unit']),
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

  /// Days from today to [deadline]; negative once it passed, null without
  /// one.
  final int? daysRemaining;
  final DeadlineBadge? deadlineBadge;
  final double targetValue;
  final double currentValue;
  final double progressPercent;
  final GoalRelated? related;

  /// Where [currentValue] comes from: `manual` (logged by hand — the only
  /// kind `update_progress` takes), `account`, `income` or `habit`.
  final String progressSource;

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
    this.progressSource = 'manual',
  });

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        targetType: (json['target_type'] as String?) ?? 'custom',
        status: (json['status'] as String?) ?? 'active',
        color: (json['color'] as String?) ?? '#B8860B',
        unit: (json['unit'] as String?) ?? '',
        deadline: parseDateTime(json['deadline']),
        daysRemaining: readIntOrNull(json['days_remaining']),
        deadlineBadge: json['deadline_badge'] == null
            ? null
            : DeadlineBadge.fromJson(
                json['deadline_badge'] as Map<String, dynamic>),
        targetValue: readDouble(json['target_value']),
        currentValue: readDouble(json['current_value']),
        progressPercent: readDouble(json['progress_percent']),
        related: json['related'] == null
            ? null
            : GoalRelated.fromJson(json['related'] as Map<String, dynamic>),
        progressSource: (json['progress_source'] as String?) ??
            _sourceOf(json['target_type'], json['related']),
      );

  /// What an older server, without `progress_source`, computes from.
  static String _sourceOf(Object? type, Object? related) => switch (type) {
        'financial' => related == null ? 'income' : 'account',
        'habit' => related == null ? 'manual' : 'habit',
        _ => 'manual',
      };

  bool get isActive => status == 'active';
  bool get isAchieved => status == 'achieved';
  bool get isAbandoned => status == 'abandoned';

  /// Progress logged by hand: the step buttons, "enter a value" and "mark
  /// achieved" apply only to these (`progress_computed` otherwise).
  bool get isManual => progressSource == 'manual';

  /// Whether reopening needs a higher target first: the progress already
  /// reaches it (`target_reached`).
  bool get reachedTarget => currentValue >= targetValue;

  /// The `related` value naming the current link, `"none"` without one.
  String get relatedRef => related?.ref ?? 'none';
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

  /// The starting progress of a goal logged by hand.
  final num? currentValue;

  const GoalInput({
    required this.name,
    this.description,
    required this.targetType,
    required this.color,
    this.unit,
    this.deadline,
    this.targetValue,
    this.related = 'none',
    this.currentValue,
  });

  static String? _text(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// Progress logged by hand once this input is saved: a custom goal, or a
  /// habit goal without a habit.
  bool get _manualAfter =>
      targetType == 'custom' || (targetType == 'habit' && related == 'none');

  /// `POST /goals`: every field. A financial goal's empty unit is left out,
  /// so the server puts the account's currency there; any other goal's empty
  /// unit is sent as null — "10 kitap" without a unit is not "10 TRY".
  Map<String, dynamic> toJson() => {
        'name': name,
        'description': _text(description),
        'target_type': targetType,
        'color': color,
        if (targetType != 'financial' || _text(unit) != null)
          'unit': _text(unit),
        'deadline': deadline == null ? null : isoDate(deadline!),
        'target_value': targetValue,
        'related': related,
        if (currentValue != null) 'current_value': currentValue,
      };

  /// `PATCH /goals/:id`: only what differs from [before]. The server
  /// applies every key it gets, so the link (`related`) is sent only when it
  /// changed — never the "none" that would unlink a goal the form did not
  /// touch — and so is every other field. Empty when nothing changed.
  Map<String, dynamic> changesFrom(Goal before) {
    final deadlineBefore =
        before.deadline == null ? null : isoDate(before.deadline!);
    final deadlineNow = deadline == null ? null : isoDate(deadline!);
    return {
      if (name != before.name) 'name': name,
      if (_text(description) != _text(before.description))
        'description': _text(description),
      if (targetType != before.targetType) 'target_type': targetType,
      if (color.toUpperCase() != before.color.toUpperCase()) 'color': color,
      if (_text(unit) != _text(before.unit)) 'unit': _text(unit),
      if (deadlineNow != deadlineBefore) 'deadline': deadlineNow,
      if (targetValue != null && targetValue != before.targetValue)
        'target_value': targetValue,
      if (related != before.relatedRef) 'related': related,
      // Manual after the change: also a goal that just became one (its link
      // removed, or now a custom goal), whose typed start must not be lost.
      if (currentValue != null &&
          _manualAfter &&
          (!before.isManual || currentValue != before.currentValue))
        'current_value': currentValue,
    };
  }
}
