@Tags(['golden'])
/// Günlük (Journal).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-13.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/journal.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_screen.dart';

import 'golden_harness.dart';

const _en = <String, String>{
  'Harika bir gün': 'A great day',
  'Sabah yoga ile başladım, öğleden sonra ekiple güzel bir toplantı yaptık. Akşam ailemle yemek yedik — enerjim gün boyu yüksek kaldı.': 'Started with yoga, had a good session with the team in the afternoon. Dinner with family — my energy stayed high all day.',
  'Güneşli': 'Sunny',
  'spor': 'sport',
  'aile': 'family',
  'Sakin bir akşam': 'A quiet evening',
  'Yağmurlu bir gündü. İçeride kalıp uzun süredir okumak istediğim kitabı bitirdim.': 'A rainy day. Stayed in and finally finished the book I had been meaning to read.',
  'Yağmurlu': 'Rainy',
  'okuma': 'reading',
  'Kısa bir not aldım, gün nötr geçti.': 'Just a short note — a neutral day.',
  'Yorucu ama verimli': 'Tiring but productive',
  'Proje teslimine yetiştirdik. Yorgunum ama başardığımız için mutluyum.': 'We made the project deadline. Tired, but glad we pulled it off.',
  'Parçalı bulutlu': 'Partly cloudy',
  'iş': 'work',
  'proje': 'project',
};

String _fx(String tr) => fx(tr, _en);

// --- Fixtures -----------------------------------------------------------------

JournalBundle _journal() => JournalBundle.fromJson({
      'entries': [
        {'id': 41, 'date': ymd(goldenNow), 'title': _fx('Harika bir gün'), 'body_plain': _fx('Sabah yoga ile başladım, öğleden sonra ekiple güzel bir toplantı yaptık. Akşam ailemle yemek yedik — enerjim gün boyu yüksek kaldı.'), 'mood': 'great', 'mood_emoji': '😄', 'energy_level': 5, 'weather': _fx('Güneşli'), 'tags': [_fx('spor'), _fx('aile')], 'has_gratitude': true, 'created_at': '${ymd(goldenNow)}T20:10:00.000Z'},
        {'id': 42, 'date': ymd(daysAgo(1)), 'title': _fx('Sakin bir akşam'), 'body_plain': _fx('Yağmurlu bir gündü. İçeride kalıp uzun süredir okumak istediğim kitabı bitirdim.'), 'mood': 'good', 'mood_emoji': '🙂', 'energy_level': 3, 'weather': _fx('Yağmurlu'), 'tags': [_fx('okuma')], 'has_gratitude': false, 'created_at': '${ymd(daysAgo(1))}T21:00:00.000Z'},
        {'id': 43, 'date': ymd(daysAgo(2)), 'title': null, 'body_plain': _fx('Kısa bir not aldım, gün nötr geçti.'), 'mood': 'neutral', 'mood_emoji': '😐', 'energy_level': 2, 'weather': null, 'tags': const <String>[], 'has_gratitude': false, 'created_at': '${ymd(daysAgo(2))}T18:00:00.000Z'},
        {'id': 44, 'date': ymd(daysAgo(4)), 'title': _fx('Yorucu ama verimli'), 'body_plain': _fx('Proje teslimine yetiştirdik. Yorgunum ama başardığımız için mutluyum.'), 'mood': 'good', 'mood_emoji': '🙂', 'energy_level': 4, 'weather': _fx('Parçalı bulutlu'), 'tags': [_fx('iş'), _fx('proje')], 'has_gratitude': true, 'created_at': '${ymd(daysAgo(4))}T22:30:00.000Z'},
      ],
      'meta': {
        'entries_count': 4,
        'journal_streak': 8,
        'mood_counts': {'great': 1, 'good': 2, 'neutral': 1, 'bad': 0, 'awful': 0},
        'range': '30d',
      },
    });

void main() {
  setUpGoldens();

  goldenScreen('journal', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const JournalScreen(),
      [
        journalProvider
            .overrideWith((ref, range) => Fetched(_journal(), goldenNow)),
      ],
    ));
    await tester.pumpAndSettle();
    // Past the longest staggered entrance (6 × 50 ms delay + 300 ms).
    await tester.pump(const Duration(milliseconds: 700));
  });
}
