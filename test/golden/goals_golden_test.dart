@Tags(['golden'])
/// Hedefler (Goals).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-12.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_form.dart';
import 'package:meridian_mobile/ui/screens/goals/goals_screen.dart';

import 'golden_harness.dart';

const _en = <String, String>{
  '100 günde 100 kitap oku': 'Read 100 books in 100 days',
  'kitap': 'books',
  'Almanca A2 seviyesine ulaş': 'Reach German A2',
  'ders': 'lessons',
  'İlk 5K koşuma hazırlan': 'Train for my first 5K',
  'antrenman': 'workouts',
  'Acil vergi ödemesi': 'Urgent tax payment',
  '3 ayda 50.000 ₺ biriktir': 'Save 50,000 ₺ in 3 months',
  'Haftada iki ders, yaz bitmeden sınava hazır.':
      'Two lessons a week, ready for the exam by summer.',
  'Sabah koşusu': 'Morning run',
};

String _fx(String tr) => fx(tr, _en);

// --- Fixtures -----------------------------------------------------------------

Map<String, dynamic> _goalJson({
  required int id,
  required String name,
  String targetType = 'custom',
  String status = 'active',
  required String color,
  String unit = '',
  String description = '',
  String progressSource = 'manual',
  Map<String, dynamic>? related,
  String? deadline,
  required int daysRemaining,
  Map<String, dynamic>? badge,
  required num targetValue,
  required num currentValue,
  required num progress,
}) =>
    {
      'id': id,
      'name': name,
      'description': description,
      'target_type': targetType,
      'status': status,
      'color': color,
      'unit': unit,
      'deadline': deadline,
      'days_remaining': daysRemaining,
      'deadline_badge': badge,
      'target_value': targetValue,
      'current_value': currentValue,
      'progress_percent': progress,
      'progress_source': progressSource,
      'related': related,
    };

GoalsBundle _goals() => GoalsBundle.fromJson({
      'active': [
        _goalJson(id: 31, name: _fx('100 günde 100 kitap oku'), targetType: 'habit', color: '#6B8E5A', unit: _fx('kitap'), deadline: ymd(daysAhead(53)), daysRemaining: 53, badge: {'state': 'far', 'days': 53}, targetValue: 100, currentValue: 20, progress: 20),
        _goalJson(id: 32, name: _fx('Almanca A2 seviyesine ulaş'), targetType: 'custom', color: '#6B8FA0', unit: _fx('ders'), deadline: ymd(daysAhead(5)), daysRemaining: 5, badge: {'state': 'soon', 'days': 5}, targetValue: 50, currentValue: 24, progress: 48),
        _goalJson(id: 33, name: _fx('İlk 5K koşuma hazırlan'), targetType: 'habit', color: '#B8860B', unit: _fx('antrenman'), deadline: ymd(goldenNow), daysRemaining: 0, badge: {'state': 'today', 'days': 0}, targetValue: 40, currentValue: 30, progress: 75),
        _goalJson(id: 34, name: _fx('Acil vergi ödemesi'), targetType: 'financial', color: '#B85450', unit: 'TRY', deadline: ymd(daysAgo(3)), daysRemaining: -3, badge: {'state': 'overdue', 'days': 3}, targetValue: 50000, currentValue: 47500, progress: 96),
      ],
      'achieved': [
        _goalJson(id: 30, name: _fx('3 ayda 50.000 ₺ biriktir'), targetType: 'financial', status: 'achieved', color: '#B8860B', unit: 'TRY', deadline: null, daysRemaining: 0, badge: null, targetValue: 50000, currentValue: 52000, progress: 100),
      ],
      'abandoned': const [],
    });

const _emptyGoals = GoalsBundle(active: [], achieved: [], abandoned: []);

/// A goal logged by hand: the stepper, "Değer gir", "Tamamlandı olarak
/// işaretle".
Goal _manualGoal() => Goal.fromJson(_goalJson(
      id: 32,
      name: _fx('Almanca A2 seviyesine ulaş'),
      description: _fx('Haftada iki ders, yaz bitmeden sınava hazır.'),
      color: '#6B8FA0',
      unit: _fx('ders'),
      deadline: ymd(daysAhead(5)),
      daysRemaining: 5,
      badge: {'state': 'soon', 'days': 5},
      targetValue: 50,
      currentValue: 24,
      progress: 48,
    ));

/// A goal its habit counts: the habit with its streak, "Bugünü işaretle".
Goal _habitGoal() => Goal.fromJson(_goalJson(
      id: 33,
      name: _fx('İlk 5K koşuma hazırlan'),
      targetType: 'habit',
      color: '#B8860B',
      unit: _fx('antrenman'),
      progressSource: 'habit',
      related: {
        'type': 'Habit',
        'id': 1,
        'name': _fx('Sabah koşusu'),
        'current_streak': 12,
        'completed_days': 30,
      },
      deadline: ymd(daysAhead(53)),
      daysRemaining: 53,
      badge: {'state': 'far', 'days': 53},
      targetValue: 40,
      currentValue: 30,
      progress: 75,
    ));

HabitsBundle _habits() => HabitsBundle.fromJson({
      'habits': [
        {'id': 1, 'name': _fx('Sabah koşusu'), 'description': '', 'frequency': 'daily', 'target_count': 1, 'color': '#6B8E5A', 'goal_id': 33, 'current_streak': 12, 'longest_streak': 21, 'completion_rate_30d': 0.86, 'today': {'date': ymd(goldenNow), 'completed': false, 'count': 0}, 'chain': const []},
      ],
      'meta': {'completed_today': 0, 'total_active': 1},
    });

/// The detail of [goal], loaded, opened from the grid with its preview.
Future<void> _detail(WidgetTester tester, Goal goal) async {
  await tester.pumpWidget(goldenHost(
    GoalDetailScreen(goalId: goal.id, preview: goal),
    [
      sharedPrefsProvider.overrideWithValue(goldenPrefs),
      goalDetailProvider(goal.id)
          .overrideWith((ref) async => Fetched(goal, goldenNow)),
      habitsProvider.overrideWithBuild(
        (ref, _) async => Fetched(_habits(), goldenNow),
      ),
    ],
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpGoldens();

  goldenScreen('goals', variants: GoldenVariant.withLargeText,
      (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const GoalsScreen(),
      [goalsProvider.overrideWith((ref) async => Fetched(_goals(), goldenNow))],
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('goals_empty', variants: GoldenVariant.withLargeText,
      (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const GoalsScreen(),
      [
        goalsProvider
            .overrideWith((ref) async => Fetched(_emptyGoals, goldenNow)),
      ],
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('goal_detail_manual', variants: GoldenVariant.withLargeText,
      (tester, _) => _detail(tester, _manualGoal()));

  goldenScreen('goal_detail_habit', variants: GoldenVariant.withLargeText,
      (tester, _) => _detail(tester, _habitGoal()));

  // An edit: every field filled, "Daha fazla" open for the description.
  goldenScreen('goal_form', variants: GoldenVariant.withLargeText,
      (tester, _) async {
    await tester.pumpWidget(goldenHost(
      GoalFormScreen(goal: _manualGoal()),
      [
        sharedPrefsProvider.overrideWithValue(goldenPrefs),
        currentUserProvider.overrideWithValue(null),
        accountsProvider.overrideWith(
          (ref) async => Fetched(const <Account>[], goldenNow),
        ),
        habitsProvider.overrideWithBuild(
          (ref, _) async => Fetched(_habits(), goldenNow),
        ),
      ],
    ));
    await tester.pumpAndSettle();
  });
}
