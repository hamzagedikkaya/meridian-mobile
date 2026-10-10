@Tags(['golden'])
/// Bugün (Today).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-5.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';

import '../screens/today_harness.dart';
import 'golden_harness.dart';

const _en = <String, String>{
  'Sabah koşusu': 'Morning run',
  '2 litre su iç': 'Drink 2 L of water',
  '30 dakika kitap oku': 'Read for 30 minutes',
  'Meditasyon': 'Meditation',
  'Almanca çalış': 'Study German',
  'Vergi beyannamesini gönder': 'File the tax return',
  'İş': 'Work',
  'Sunum slaytlarını hazırla': 'Prepare the slide deck',
  'Market alışverişi yap': 'Do the grocery run',
  'Ev': 'Home',
  'Takım toplantısı': 'Team meeting',
  'Diş hekimi randevusu': 'Dentist appointment',
  'Annemin doğum günü': "Mum's birthday",
  '100 günde 100 kitap': '100 books in 100 days',
  'Sabah yürüyüşü': 'Morning walk',
  'Almanca A2 seviyesi': 'German A2 level',
  'İlk 5K koşusu': 'First 5K run',
};

String _fx(String tr) => fx(tr, _en);

// --- Fixtures -----------------------------------------------------------------

const _user = User(
  id: 1,
  displayName: 'Hamza Gedikkaya',
  initials: 'HG',
  email: 'hamza@meridian.local',
  currency: 'TRY',
  subunitToUnit: 100,
  locale: 'tr',
  themePreference: 'dark',
);

/// Rich /home payload for Bugün.
Map<String, dynamic> _homeJson() => {
  'currency': 'TRY',
  'subunit_to_unit': 100,
  'month_net_cents': 4275000, // +42.750,00 ₺
  'active_streaks': 5,
  'open_todos': 3,
  'overdue_count': 1,
  'today_events_count': 3,
  'habit_completion_pct': 82,
  'spending_7d': [
    {'date': ymd(daysAgo(6)), 'cents': 32000},
    {'date': ymd(daysAgo(5)), 'cents': 87500},
    {'date': ymd(daysAgo(4)), 'cents': 41000},
    {'date': ymd(daysAgo(3)), 'cents': 123000},
    {'date': ymd(daysAgo(2)), 'cents': 64000},
    {'date': ymd(daysAgo(1)), 'cents': 98000},
    {'date': ymd(goldenNow), 'cents': 52000},
  ],
  'today_habits': [
    {
      'id': 1,
      'name': _fx('Sabah koşusu'),
      'color': '#6B8E5A',
      'target_count': 1,
      'completed_today': true,
      'today_count': 1,
      'current_streak': 12,
    },
    {
      'id': 2,
      'name': _fx('2 litre su iç'),
      'color': '#6B8FA0',
      'target_count': 8,
      'completed_today': false,
      'today_count': 5,
      'current_streak': 6,
    },
    {
      'id': 3,
      'name': _fx('30 dakika kitap oku'),
      'color': '#B8860B',
      'target_count': 1,
      'completed_today': false,
      'today_count': 0,
      'current_streak': 3,
    },
    {
      'id': 4,
      'name': _fx('Meditasyon'),
      'color': '#8B5A00',
      'target_count': 1,
      'completed_today': true,
      'today_count': 1,
      'current_streak': 20,
    },
    {
      'id': 5,
      'name': _fx('Almanca çalış'),
      'color': '#B85450',
      'target_count': 1,
      'completed_today': false,
      'today_count': 0,
      'current_streak': 0,
    },
  ],
  'upcoming_todos': [
    {
      'id': 11,
      'title': _fx('Vergi beyannamesini gönder'),
      'status': 'pending',
      'priority': 'urgent',
      'due_at': '${ymd(daysAgo(1))}T17:00:00.000Z',
      'overdue': true,
      'position': 1,
      'todo_list': {'id': 1, 'name': _fx('İş'), 'color': '#6B8FA0'},
      'subtask_count': 2,
    },
    {
      'id': 12,
      'title': _fx('Sunum slaytlarını hazırla'),
      'status': 'pending',
      'priority': 'high',
      'due_at': '${ymd(goldenNow)}T15:30:00.000Z',
      'overdue': false,
      'position': 2,
      'todo_list': {'id': 1, 'name': _fx('İş'), 'color': '#6B8FA0'},
      'subtask_count': 0,
    },
    {
      'id': 13,
      'title': _fx('Market alışverişi yap'),
      'status': 'pending',
      'priority': 'low',
      'due_at': '${ymd(goldenNow)}T19:00:00.000Z',
      'overdue': false,
      'position': 3,
      'todo_list': {'id': 2, 'name': _fx('Ev'), 'color': '#6B8E5A'},
      'subtask_count': 0,
    },
  ],
  'today_events': [
    {
      'id': 21,
      'title': _fx('Takım toplantısı'),
      'start_at': '${ymd(goldenNow)}T09:30:00.000Z',
      'end_at': '${ymd(goldenNow)}T10:15:00.000Z',
      'all_day': false,
      'color': '#6B8FA0',
    },
    {
      'id': 22,
      'title': _fx('Diş hekimi randevusu'),
      'start_at': '${ymd(goldenNow)}T14:00:00.000Z',
      'end_at': '${ymd(goldenNow)}T14:45:00.000Z',
      'all_day': false,
      'color': '#B85450',
    },
    {
      'id': 23,
      'title': _fx('Annemin doğum günü'),
      'start_at': '${ymd(goldenNow)}T00:00:00.000Z',
      'end_at': '${ymd(goldenNow)}T00:00:00.000Z',
      'all_day': true,
      'color': '#B8860B',
    },
  ],
  'active_goals': [
    {
      'id': 31,
      'name': _fx('100 günde 100 kitap'),
      'color': '#6B8E5A',
      'progress_percent': 68.0,
    },
    {
      'id': 32,
      'name': _fx('Almanca A2 seviyesi'),
      'color': '#6B8FA0',
      'progress_percent': 35.0,
    },
    {
      'id': 33,
      'name': _fx('İlk 5K koşusu'),
      'color': '#B8860B',
      'progress_percent': 90.0,
    },
  ],
  'perfect_day': {
    'chain': [
      {'date': ymd(goldenNow), 'status': 'today_pending'},
    ],
    'current_streak': 5,
    'longest_streak': 12,
  },
};

HomeSummary _home() => HomeSummary.fromJson(_homeJson());

/// A new account: nothing yet.
HomeSummary _empty() => HomeSummary.fromJson({
  'currency': 'TRY',
  'subunit_to_unit': 100,
  'month_net_cents': 0,
  'active_streaks': 0,
  'open_todos': 0,
  'overdue_count': 0,
  'today_events_count': 0,
  'habit_completion_pct': 0,
  'spending_7d': const [],
  'today_habits': const [],
  'upcoming_todos': const [],
  'today_events': const [],
  'active_goals': const [],
  'perfect_day': {'chain': const [], 'current_streak': 0},
});

/// Every habit done, no todo left, the morning's one event over.
HomeSummary _allDone() {
  final json = _homeJson();
  json['today_habits'] = [
    for (final h in json['today_habits'] as List)
      {
        ...(h as Map<String, dynamic>),
        'completed_today': true,
        'today_count': h['target_count'],
      },
  ];
  json['upcoming_todos'] = const [];
  json['open_todos'] = 0;
  json['overdue_count'] = 0;
  json['today_events'] = [
    {
      'id': 24,
      'title': _fx('Sabah yürüyüşü'),
      'start_at': '${ymd(goldenNow)}T07:00:00.000Z',
      'end_at': '${ymd(goldenNow)}T07:45:00.000Z',
      'all_day': false,
      'color': '#6B8E5A',
    },
  ];
  json['today_events_count'] = 1;
  return HomeSummary.fromJson(json);
}

/// Today's habits are all daily ones (`/home` does not say; the Habits list
/// does).
final _cadence = habitCadenceProvider.overrideWithBuild(
  (ref, _) => const {1: true, 2: true, 3: true, 4: true, 5: true},
);

List<Override> _reads({
  List<Map<String, dynamic>> accounts = const [],
  List<Map<String, dynamic>> journal = const [],
  List<Map<String, dynamic>>? events,
}) => todayReadOverrides(
  at: goldenNow,
  accounts: accounts,
  journal: journal,
  events: events,
);

/// Each shot starts as a device that never saw the first-run card.
Future<void> _freshDevice() async {
  await goldenPrefs.remove('today.start.active');
  await goldenPrefs.remove('today.start.dismissed');
}

void main() {
  setUpGoldens();
  setUp(_freshDevice);

  goldenScreen('today', variants: GoldenVariant.withLargeText, (
    tester,
    _,
  ) async {
    await tester.pumpWidget(
      goldenHost(const TodayScreen(), [
        homeProvider.overrideWithBuild((ref, _) => Fetched(_home(), goldenNow)),
        _cadence,
        currentUserProvider.overrideWithValue(_user),
        sharedPrefsProvider.overrideWithValue(goldenPrefs),
        ..._reads(
          accounts: [todayAccountJson()],
          events: _homeJson()['today_events'] as List<Map<String, dynamic>>,
        ),
      ]),
    );
    await tester.pumpAndSettle();
  });

  // A new account: the first-run card, the Today card's add row and the
  // goals' ghost row — no "0" anywhere.
  goldenScreen('today_first_run', variants: [GoldenVariant.trDark], (
    tester,
    _,
  ) async {
    await tester.pumpWidget(
      goldenHost(const TodayScreen(), [
        homeProvider.overrideWithBuild(
          (ref, _) => Fetched(_empty(), goldenNow),
        ),
        currentUserProvider.overrideWithValue(_user),
        sharedPrefsProvider.overrideWithValue(goldenPrefs),
        ..._reads(events: const []),
      ]),
    );
    await tester.pumpAndSettle();
  });

  // Every habit done ("Hepsi tamam"), the day's plan empty, today's entry
  // written.
  goldenScreen('today_all_done', variants: [GoldenVariant.trDark], (
    tester,
    _,
  ) async {
    await tester.pumpWidget(
      goldenHost(const TodayScreen(), [
        homeProvider.overrideWithBuild(
          (ref, _) => Fetched(_allDone(), goldenNow),
        ),
        _cadence,
        currentUserProvider.overrideWithValue(_user),
        sharedPrefsProvider.overrideWithValue(goldenPrefs),
        ..._reads(
          accounts: [todayAccountJson()],
          journal: [todayJournalEntryJson(ymd(goldenNow))],
          events: [
            for (final e in _allDone().todayEvents)
              {
                'id': e.id,
                'title': e.title,
                'start_at': '${ymd(goldenNow)}T07:00:00.000Z',
                'end_at': '${ymd(goldenNow)}T07:45:00.000Z',
                'all_day': false,
                'color': e.color,
              },
          ],
        ),
      ]),
    );
    await tester.pumpAndSettle();
  });

  // The server out of reach after a first load: the banner over what is
  // known.
  goldenScreen('today_offline', variants: [GoldenVariant.trDark], (
    tester,
    _,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      goldenHost(const TodayScreen(), [
        homeProvider.overrideWithBuild((ref, _) {
          if (++builds > 1) {
            throw ApiException(ApiErrorKind.network);
          }
          return Fetched(_home(), goldenNow);
        }),
        _cadence,
        currentUserProvider.overrideWithValue(_user),
        sharedPrefsProvider.overrideWithValue(goldenPrefs),
        ..._reads(
          accounts: [todayAccountJson()],
          events: _homeJson()['today_events'] as List<Map<String, dynamic>>,
        ),
      ]),
    );
    await tester.pumpAndSettle();
    ProviderScope.containerOf(
      tester.element(find.byType(TodayScreen)),
    ).invalidate(homeProvider);
    await tester.pumpAndSettle();
  });
}
