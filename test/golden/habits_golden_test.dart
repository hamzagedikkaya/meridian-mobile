@Tags(['golden'])
/// Alışkanlıklar (Habits).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-11.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/ui/screens/habits/habits_screen.dart';

import 'golden_harness.dart';

const _en = <String, String>{
  'Sabah koşusu': 'Morning run',
  'Her sabah 3 km': '3 km every morning',
  '2 litre su iç': 'Drink 2 L of water',
  'Gün içinde 8 bardak': '8 glasses through the day',
  'Spor salonu': 'Gym',
  'Haftada 3 gün': '3 days a week',
  'Meditasyon': 'Meditation',
  '10 dakika': '10 minutes',
  'Almanca çalış': 'Study German',
};

String _fx(String tr) => fx(tr, _en);

// --- Fixtures -----------------------------------------------------------------

/// Build a chain of [statuses.length] days ending today.
List<Map<String, dynamic>> _chain(List<String> statuses) {
  final n = statuses.length;
  return [
    for (var i = 0; i < n; i++)
      {'date': ymd(daysAgo(n - 1 - i)), 'status': statuses[i]},
  ];
}

HabitsBundle _habits() => HabitsBundle.fromJson({
      'habits': [
        {'id': 1, 'name': _fx('Sabah koşusu'), 'description': _fx('Her sabah 3 km'), 'frequency': 'daily', 'target_count': 1, 'color': '#6B8E5A', 'goal_id': null, 'current_streak': 12, 'longest_streak': 21, 'completion_rate_30d': 0.86, 'today': {'date': ymd(goldenNow), 'completed': true, 'count': 1}, 'chain': _chain(['completed', 'completed', 'missed', 'completed', 'completed', 'completed', 'completed', 'missed', 'completed', 'completed', 'completed', 'completed', 'completed', 'completed'])},
        {'id': 2, 'name': _fx('2 litre su iç'), 'description': _fx('Gün içinde 8 bardak'), 'frequency': 'daily', 'target_count': 8, 'color': '#6B8FA0', 'goal_id': null, 'current_streak': 6, 'longest_streak': 15, 'completion_rate_30d': 0.70, 'today': {'date': ymd(goldenNow), 'completed': false, 'count': 5}, 'chain': _chain(['completed', 'missed', 'completed', 'completed', 'completed', 'missed', 'completed', 'completed', 'completed', 'missed', 'completed', 'completed', 'completed', 'today_pending'])},
        {'id': 3, 'name': _fx('Spor salonu'), 'description': _fx('Haftada 3 gün'), 'frequency': 'weekly', 'target_count': 3, 'color': '#B85450', 'goal_id': null, 'current_streak': 4, 'longest_streak': 9, 'completion_rate_30d': 0.60, 'today': {'date': ymd(goldenNow), 'completed': false, 'count': 0}, 'chain': [{'date': ymd(goldenNow), 'status': 'today_pending'}], 'period': {'range_start': ymd(daysAgo(5)), 'range_end': ymd(daysAhead(1)), 'completed_count': 2, 'complete': false}},
        {'id': 4, 'name': _fx('Meditasyon'), 'description': _fx('10 dakika'), 'frequency': 'daily', 'target_count': 1, 'color': '#8B5A00', 'goal_id': null, 'current_streak': 20, 'longest_streak': 20, 'completion_rate_30d': 1.0, 'today': {'date': ymd(goldenNow), 'completed': true, 'count': 1}, 'chain': _chain(List.filled(14, 'completed'))},
        {'id': 5, 'name': _fx('Almanca çalış'), 'description': 'Duolingo', 'frequency': 'daily', 'target_count': 1, 'color': '#B8860B', 'goal_id': null, 'current_streak': 0, 'longest_streak': 11, 'completion_rate_30d': 0.30, 'today': {'date': ymd(goldenNow), 'completed': false, 'count': 0}, 'chain': _chain(['missed', 'completed', 'missed', 'missed', 'completed', 'missed', 'missed', 'completed', 'missed', 'missed', 'missed', 'completed', 'missed', 'missed'])},
      ],
      'meta': {
        'completed_today': 2,
        'total_active': 5,
        'perfect_day': {
          'chain': _chain(['perfect', 'completed', 'partial', 'perfect', 'missed', 'completed', 'perfect', 'no_habits', 'completed', 'partial', 'perfect', 'completed', 'perfect', 'today_pending']),
          'current_streak': 3,
          'longest_streak': 12,
        },
      },
    });

void main() {
  setUpGoldens();

  // WP-11: switch to `variants: GoldenVariant.withLargeText` once the screen
  // lays out at 200 % text without overflow (§8.3); today it does not.
  goldenScreen('habits', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const HabitsScreen(),
      [
        habitsProvider.overrideWithBuild(
          (ref, _) async => Fetched(_habits(), goldenNow),
        ),
      ],
    ));
    await tester.pumpAndSettle();
  });
}
