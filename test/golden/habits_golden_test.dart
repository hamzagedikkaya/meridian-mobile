@Tags(['golden'])
/// Alışkanlıklar (Habits): the tab (with its habits, empty, all done), a
/// habit's detail sheet, the day's log sheet, the form and the archive.
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-11.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/ui/screens/habits/archived_habits_screen.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_detail_sheet.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_form.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_log_sheet.dart';
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
  'Günde 2 litre, 30 gün': '2 litres a day, 30 days',
  'Gitar çal': 'Play the guitar',
  'Günlük yaz': 'Write a journal',
};

String _fx(String tr) => fx(tr, _en);

// --- Fixtures -----------------------------------------------------------------

/// A chain of [statuses.length] days ending today.
List<Map<String, dynamic>> _chain(List<String> statuses) {
  final n = statuses.length;
  return [
    for (var i = 0; i < n; i++)
      {'date': ymd(daysAgo(n - 1 - i)), 'status': statuses[i]},
  ];
}

/// [days] days ending today, done most days, partial now and then, a
/// missed day every so often, today [today].
List<Map<String, dynamic>> _history(
  int days, {
  String today = 'today_pending',
}) => _chain([
  for (var i = days - 1; i >= 0; i--)
    if (i == 0)
      today
    else if (i % 9 == 4)
      'missed'
    else if (i % 7 == 3)
      'partial'
    else
      'completed',
]);

Map<String, dynamic> _habit({
  required int id,
  required String name,
  String description = '',
  String frequency = 'daily',
  int target = 1,
  required String color,
  int streak = 0,
  int record = 0,
  double rate = 0,
  bool done = false,
  int count = 0,
  required List<Map<String, dynamic>> chain,
  Map<String, dynamic>? period,
}) => {
  'id': id,
  'name': _fx(name),
  'description': description.isEmpty ? '' : _fx(description),
  'frequency': frequency,
  'target_count': target,
  'color': color,
  'goal_id': null,
  'archived': false,
  'archived_at': null,
  'start_date': ymd(daysAgo(120)),
  'current_streak': streak,
  'longest_streak': record,
  'completion_rate_30d': rate,
  'today': {'date': ymd(goldenNow), 'completed': done, 'count': count},
  'chain': chain,
  'period': ?period,
};

Map<String, dynamic> _water({List<Map<String, dynamic>>? chain}) => _habit(
  id: 2,
  name: '2 litre su iç',
  description: 'Gün içinde 8 bardak',
  target: 8,
  color: '#6B8FA0',
  streak: 6,
  record: 15,
  rate: 70,
  count: 5,
  chain:
      chain ??
      _chain([
        'completed',
        'missed',
        'completed',
        'completed',
        'completed',
        'missed',
        'completed',
        'completed',
        'completed',
        'missed',
        'completed',
        'completed',
        'completed',
        'partial',
      ]),
);

HabitsBundle _habits() => HabitsBundle.fromJson({
  'habits': [
    _habit(
      id: 1,
      name: 'Sabah koşusu',
      description: 'Her sabah 3 km',
      color: '#6B8E5A',
      streak: 12,
      record: 21,
      rate: 86,
      done: true,
      count: 1,
      chain: _chain([
        'completed',
        'completed',
        'missed',
        'completed',
        'completed',
        'completed',
        'completed',
        'missed',
        'completed',
        'completed',
        'completed',
        'completed',
        'completed',
        'completed',
      ]),
    ),
    _water(),
    _habit(
      id: 3,
      name: 'Spor salonu',
      description: 'Haftada 3 gün',
      frequency: 'weekly',
      target: 3,
      color: '#B85450',
      streak: 4,
      record: 9,
      rate: 60,
      chain: _chain([
        'missed',
        'completed',
        'missed',
        'completed',
        'missed',
        'missed',
        'completed',
        'missed',
        'completed',
        'missed',
        'completed',
        'missed',
        'missed',
        'today_pending',
      ]),
      period: {
        'range_start': ymd(daysAgo(6)),
        'range_end': ymd(goldenNow),
        'completed_count': 2,
        'complete': false,
      },
    ),
    _habit(
      id: 4,
      name: 'Meditasyon',
      description: '10 dakika',
      color: '#8B5A00',
      streak: 20,
      record: 20,
      rate: 100,
      done: true,
      count: 1,
      chain: _chain(List.filled(14, 'completed')),
    ),
    _habit(
      id: 5,
      name: 'Almanca çalış',
      description: 'Duolingo',
      color: '#7A5C9E',
      record: 11,
      rate: 30,
      chain: _chain([
        'missed',
        'completed',
        'missed',
        'missed',
        'completed',
        'missed',
        'missed',
        'completed',
        'missed',
        'missed',
        'missed',
        'completed',
        'missed',
        'today_pending',
      ]),
    ),
  ],
  'meta': {
    'completed_today': 2,
    'total_active': 5,
    'perfect_day': {
      'chain': _chain([
        'perfect',
        'completed',
        'partial',
        'perfect',
        'missed',
        'perfect',
        'perfect',
        'no_habits',
        'perfect',
        'partial',
        'perfect',
        'perfect',
        'perfect',
        'today_pending',
      ]),
      'current_streak': 3,
      'longest_streak': 12,
    },
  },
});

HabitsBundle _empty() => HabitsBundle.fromJson({
  'habits': const [],
  'meta': {
    'completed_today': 0,
    'total_active': 0,
    'perfect_day': {
      'chain': const [],
      'current_streak': 0,
      'longest_streak': 0,
    },
  },
});

HabitsBundle _allDone() => HabitsBundle.fromJson({
  'habits': [
    _habit(
      id: 1,
      name: 'Sabah koşusu',
      description: 'Her sabah 3 km',
      color: '#6B8E5A',
      streak: 13,
      record: 21,
      rate: 87,
      done: true,
      count: 1,
      chain: _history(14, today: 'completed'),
    ),
    _habit(
      id: 4,
      name: 'Meditasyon',
      description: '10 dakika',
      color: '#8B5A00',
      streak: 21,
      record: 21,
      rate: 100,
      done: true,
      count: 1,
      chain: _chain(List.filled(14, 'completed')),
    ),
    {
      ..._water(chain: _history(14, today: 'completed')),
      'today': {'date': ymd(goldenNow), 'completed': true, 'count': 8},
      'current_streak': 7,
    },
  ],
  'meta': {
    'completed_today': 3,
    'total_active': 3,
    'perfect_day': {
      'chain': _chain([
        'perfect',
        'perfect',
        'partial',
        'perfect',
        'perfect',
        'perfect',
        'perfect',
        'perfect',
        'perfect',
        'partial',
        'perfect',
        'perfect',
        'perfect',
        'perfect',
      ]),
      'current_streak': 4,
      'longest_streak': 12,
    },
  },
});

/// Water's detail: 84 days of history and a goal that counts it.
Habit _waterDetail() => Habit.fromJson({
  ..._water(chain: _history(120)),
  'logged_days_count': 104,
  'completed_days_count': 92,
  'tracked_by_goals': [
    {'id': 31, 'name': _fx('Günde 2 litre, 30 gün'), 'status': 'active'},
  ],
});

List<Habit> _archived() => [
  Habit.fromJson({
    ..._habit(
      id: 11,
      name: 'Gitar çal',
      color: '#C98F6B',
      record: 9,
      rate: 12,
      chain: _history(14),
    ),
    'archived': true,
    'archived_at': '${ymd(daysAgo(6))}T18:00:00.000+03:00',
  }),
  Habit.fromJson({
    ..._habit(
      id: 12,
      name: 'Günlük yaz',
      frequency: 'weekly',
      target: 3,
      color: '#5A9E8B',
      record: 4,
      rate: 20,
      chain: _history(14),
    ),
    'archived': true,
    'archived_at': '2026-03-14T18:00:00.000+03:00',
  }),
];

/// `/home` as far as the log sheet reads it: today and water's count.
HomeSummary _home() => HomeSummary.fromJson({
  'today': ymd(goldenNow),
  'today_habits': [
    {
      'id': 2,
      'name': _fx('2 litre su iç'),
      'color': '#6B8FA0',
      'target_count': 8,
      'completed_today': false,
      'today_count': 5,
      'current_streak': 6,
    },
  ],
});

List<Override> _lists(HabitsBundle bundle) => [
  habitsProvider.overrideWithBuild(
    (ref, _) async => Fetched(bundle, goldenNow),
  ),
  homeProvider.overrideWithBuild((ref, _) async => Fetched(_home(), goldenNow)),
  habitCadenceProvider.overrideWithBuild(
    (ref, _) => const {1: true, 2: true, 4: true, 5: true},
  ),
  habitDetailProvider.overrideWith(
    (ref, id) async => Fetched(_waterDetail(), goldenNow),
  ),
];

/// A blank screen whose button opens [open] — a sheet shot over it.
Widget _opener(void Function(BuildContext context) open) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpGoldens();

  goldenScreen('habits', variants: GoldenVariant.withLargeText, (
    tester,
    _,
  ) async {
    await tester.pumpWidget(
      goldenHost(const HabitsScreen(), _lists(_habits())),
    );
    await tester.pumpAndSettle();
  });

  goldenScreen('habits_empty', (tester, _) async {
    await tester.pumpWidget(goldenHost(const HabitsScreen(), _lists(_empty())));
    await tester.pumpAndSettle();
  });

  goldenScreen('habits_all_done', (tester, _) async {
    await tester.pumpWidget(
      goldenHost(const HabitsScreen(), _lists(_allDone())),
    );
    await tester.pumpAndSettle();
  });

  goldenScreen('habit_detail', (tester, _) async {
    await tester.pumpWidget(
      goldenHost(
        _opener((context) => showHabitDetailSheet(context, _waterDetail())),
        _lists(_habits()),
      ),
    );
    await _openSheet(tester);
    // Dragged up to its full 92 %.
    await tester.drag(
      find.text(_fx('Gün içinde 8 bardak')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
  });

  goldenScreen('habit_log_sheet', (tester, _) async {
    await tester.pumpWidget(
      goldenHost(
        _opener((context) => showHabitLogSheet(context, habitId: 2)),
        _lists(_habits()),
      ),
    );
    await _openSheet(tester);
  });

  goldenScreen('habit_form', (tester, _) async {
    await tester.pumpWidget(
      goldenHost(HabitFormScreen(habit: _waterDetail()), _lists(_habits())),
    );
    await tester.pumpAndSettle();
  });

  // With 200 % text too: its rows put the actions under the name (§8.3).
  goldenScreen('habits_archived', variants: GoldenVariant.withLargeText, (
    tester,
    _,
  ) async {
    await tester.pumpWidget(
      goldenHost(const ArchivedHabitsScreen(), [
        ..._lists(_habits()),
        archivedHabitsProvider.overrideWith(
          (ref) async => Fetched(_archived(), goldenNow),
        ),
      ]),
    );
    await tester.pumpAndSettle();
  });
}
