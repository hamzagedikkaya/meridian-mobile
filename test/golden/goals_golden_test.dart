@Tags(['golden'])
/// Hedefler (Goals).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-12.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/goal.dart';
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
      'description': '',
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
      'related': null,
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

void main() {
  setUpGoldens();

  // WP-12: switch to `variants: GoldenVariant.withLargeText` once the screen
  // lays out at 200 % text without overflow (§8.3); today it does not.
  goldenScreen('goals', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const GoalsScreen(),
      [goalsProvider.overrideWith((ref) async => Fetched(_goals(), goldenNow))],
    ));
    await tester.pumpAndSettle();
  });
}
