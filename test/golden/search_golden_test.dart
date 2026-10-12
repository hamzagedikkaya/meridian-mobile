@Tags(['golden'])
/// Arama (global search).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-16.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/search.dart';
import 'package:meridian_mobile/models/search_result.dart';
import 'package:meridian_mobile/ui/screens/search/search_screen.dart';

import 'golden_harness.dart';

const _en = <String, String>{
  'kahve': 'coffee',
  'Kahve': 'Coffee',
  'Market': 'Groceries',
  'Kahve filtresi al': 'Buy a coffee filter',
  'Kahve buluşması': 'Coffee with Deniz',
  'Sabah kahvesi balkonda': 'Morning coffee on the balcony',
  'KAHVE bütçesi': 'COFFEE budget',
  'Kahve yok': 'No coffee',
  'Kahve kulübü': 'Coffee club',
  'kira': 'rent',
  'koşu': 'run',
  // Subtitles: the server words them in the user's language (§13.1).
  '3 Eki 2026 · Cüzdan · −₺85,00': '3 Oct 2026 · Wallet · −₺85.00',
  '1 Eki 2026 · Cüzdan · −₺412,50': '1 Oct 2026 · Wallet · −₺412.50',
  'Bekliyor · Son gün 5 Eki 2026': 'Pending · Due 5 Oct 2026',
  '6 Eki 2026 15:00 · Moda': '6 Oct 2026 15:00 · Moda',
  '3 Eki 2026': '3 Oct 2026',
  '33% tamamlandı': '33% complete',
  'Günlük': 'Daily',
  'Aylık · ₺149,90 · Sonraki 15 Eki 2026':
      'Monthly · ₺149.90 · Next 15 Oct 2026',
};

String _fx(String tr) => fx(tr, _en);

// --- Fixtures -----------------------------------------------------------------

SearchResult _row(SearchResultType type, int id, String title, String sub) =>
    SearchResult(type: type, id: id, title: _fx(title), subtitle: _fx(sub));

/// The contract's example (§13.1): every type, "Market" matched on its note.
SearchResults _kahve() => SearchResults(query: _fx('kahve'), results: [
      _row(SearchResultType.transaction, 2547, 'Kahve', '3 Eki 2026 · Cüzdan · −₺85,00'),
      _row(SearchResultType.transaction, 2548, 'Market', '1 Eki 2026 · Cüzdan · −₺412,50'),
      _row(SearchResultType.todo, 2721, 'Kahve filtresi al', 'Bekliyor · Son gün 5 Eki 2026'),
      _row(SearchResultType.event, 821, 'Kahve buluşması', '6 Eki 2026 15:00 · Moda'),
      _row(SearchResultType.journalEntry, 558, 'Sabah kahvesi balkonda', '3 Eki 2026'),
      _row(SearchResultType.goal, 12, 'KAHVE bütçesi', '33% tamamlandı'),
      _row(SearchResultType.habit, 2480, 'Kahve yok', 'Günlük'),
      _row(SearchResultType.subscription, 484, 'Kahve kulübü', 'Aylık · ₺149,90 · Sonraki 15 Eki 2026'),
    ]);

/// The search as it stands, asking nothing of the server.
class _Fixed extends SearchNotifier {
  _Fixed(this.fixed);
  final SearchState fixed;

  @override
  SearchState build() => fixed;

  @override
  void searchNow(String text) {}

  @override
  void type(String text) {}
}

class _Recent extends RecentSearches {
  _Recent(this.fixed);
  final List<String> fixed;

  @override
  List<String> build() => fixed;
}

/// The search page opened with [query] (the field's text), showing [state]
/// and, before anything is typed, [recent].
Future<void> _pump(
  WidgetTester tester, {
  String query = '',
  SearchState state = const SearchState(),
  List<String> recent = const [],
}) async {
  await tester.pumpWidget(goldenHost(SearchScreen(query: query), [
    sharedPrefsProvider.overrideWithValue(goldenPrefs),
    searchProvider.overrideWith(() => _Fixed(state)),
    recentSearchesProvider.overrideWith(() => _Recent(recent)),
  ]));
  // The field has focus (autofocus): its cursor blinks forever, so settle
  // by time rather than by pumpAndSettle.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpGoldens();
  // A blinking cursor would make every shot a coin toss.
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  goldenScreen('search', (tester, _) async {
    final results = _kahve();
    await _pump(tester,
        query: results.query,
        state: SearchState(query: results.query, results: results));
  });

  goldenScreen('search_recent', (tester, _) async {
    await _pump(tester, recent: [_fx('kahve'), _fx('kira'), _fx('koşu')]);
  });

  goldenScreen('search_none', (tester, _) async {
    await _pump(tester,
        query: 'zzz',
        state: const SearchState(
          query: 'zzz',
          results: SearchResults(query: 'zzz', results: []),
        ));
  });
}
