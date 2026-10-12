@Tags(['golden'])
/// Günlük (Journal).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-13.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/journal.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_editor.dart';
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
  'Sahilde pazar': 'Sunday by the sea',
  'Sabah erkenden sahile indim. Deniz durgundu, birkaç balıkçıdan başka kimse yoktu.\n\nKahvemi alıp bir saat kadar yürüdüm. Uzun zamandır bu kadar sakin hissetmemiştim.\n\nÖğleden sonra annemi aradım; haftaya bize gelecek.': 'I went down to the shore early. The sea was still, nobody around but a few fishermen.\n\nI got a coffee and walked for an hour or so. I had not felt this calm in a long time.\n\nIn the afternoon I called my mother; she is visiting next week.',
  'Sakin bir sabah ve sıcak bir kahve.': 'A calm morning and a warm coffee.',
  'deniz': 'sea',
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
        // WP-15 (contract §13.4).
        'journal_streak_weeks': 6,
        'mood_counts': {'great': 1, 'good': 2, 'neutral': 1, 'bad': 0, 'awful': 0},
        'range': '30d',
      },
    });

/// A range with no entries — today asks "Bugün nasıldı?".
JournalBundle _empty() => JournalBundle.fromJson({
      'entries': const <Object>[],
      'meta': {
        'entries_count': 0,
        'journal_streak': 0,
        'journal_streak_weeks': 0,
        'mood_counts': {'great': 0, 'good': 0, 'neutral': 0, 'bad': 0, 'awful': 0},
        'range': '30d',
      },
    });

/// The full entry (`GET /journal_entries/:id`): paragraphs, mood, energy,
/// weather, gratitude and tags.
JournalEntry _full() {
  final body = _fx('Sabah erkenden sahile indim. Deniz durgundu, birkaç balıkçıdan başka kimse yoktu.\n\nKahvemi alıp bir saat kadar yürüdüm. Uzun zamandır bu kadar sakin hissetmemiştim.\n\nÖğleden sonra annemi aradım; haftaya bize gelecek.');
  return JournalEntry.fromJson({
    'id': 41, 'date': ymd(goldenNow), 'title': _fx('Sahilde pazar'),
    'body_plain': body, 'body_text': body, 'body_html': '',
    'body_format': 'plain', 'body_formatting': const <String>[],
    'mood': 'good', 'mood_emoji': '🙂', 'energy_level': 4,
    'weather': _fx('Güneşli'), 'tags': [_fx('deniz'), _fx('aile')],
    'has_gratitude': true,
    'gratitude': _fx('Sakin bir sabah ve sıcak bir kahve.'),
    'created_at': '${ymd(goldenNow)}T08:10:00.000Z',
    'updated_at': '${ymd(goldenNow)}T08:10:00.000Z',
  });
}

void main() {
  setUpGoldens();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  goldenScreen('journal', variants: GoldenVariant.withLargeText,
      (tester, _) async {
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

  goldenScreen('journal_empty', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const JournalScreen(),
      [
        journalProvider
            .overrideWith((ref, range) => Fetched(_empty(), goldenNow)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
  });

  // An edit with the keyboard up (300 dp): the accessory bar and Save
  // ride it.
  goldenScreen('journal_editor', (tester, _) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    final entry = _full();
    await tester.pumpWidget(goldenHost(
      JournalEditorScreen(editEntry: entry),
      [
        journalEntryProvider
            .overrideWith((ref, id) => Fetched(entry, goldenNow)),
      ],
    ));
    await tester.pumpAndSettle();
  });

  goldenScreen('journal_detail', (tester, _) async {
    final entry = _full();
    await tester.pumpWidget(goldenHost(
      const JournalDetailScreen(entryId: 41),
      [
        journalEntryProvider
            .overrideWith((ref, id) => Fetched(entry, goldenNow)),
      ],
    ));
    await tester.pumpAndSettle();
  });
}
