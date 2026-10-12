/// Global search on the phone (design-analysis §6.8, §7.14; WP-16), over
/// `GET /search` (contract §13.1): the field's text, debounced, becomes a
/// query; answers that arrive for an older text are dropped; what was found
/// stays on screen until the next answer replaces it.
///
/// Also here: whether this server offers search at all (a server without
/// WP-15 answers 404, and the ways in hide), the last five searches, and
/// where a query occurs in a result's title, folded the way the server
/// matches.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/turkish_case.dart';
import '../models/search_result.dart';
import 'providers.dart';

/// The shortest query sent (the server refuses less: `query_too_short`).
const searchMinLength = 2;

/// The longest query the server takes (`invalid_parameter` past it).
const searchMaxLength = 100;

/// How long typing must pause before the text is searched (§6.8). Not
/// motion: a request is held back, nothing on screen moves.
const searchDebounce = Duration(milliseconds: 250);

/// Whether [query] (already trimmed) is long enough to send. Counted in
/// characters, as the server counts them.
bool isSearchable(String query) => query.runes.length >= searchMinLength;

// --- Is search offered -------------------------------------------------------

/// The server that answered `GET /search` with 404 (one from before WP-15,
/// contract §13); null while none has. Kept as the server's address rather
/// than a flag so pointing the app at another server offers search again —
/// and so nothing here reads the server address (nor the preferences behind
/// it) until a search has actually been refused.
final searchMissingOnProvider =
    NotifierProvider<SearchSupport, String?>(SearchSupport.new);

class SearchSupport extends Notifier<String?> {
  @override
  String? build() => null;

  /// [server] has no `GET /search`.
  void missing(String server) => state = server;
}

/// Whether the server offers global search: true unless this very server
/// answered a search with 404. Watch [searchOfferedProvider] to draw a way
/// in.
final searchSupportedProvider = Provider<bool>((ref) {
  final missingOn = ref.watch(searchMissingOnProvider);
  return missingOn == null || missingOn != ref.watch(serverUrlProvider);
});

/// Whether to draw the ways into search — Today's and Agenda's search icons
/// (`SearchEntryButton`): it is enabled ([kSearchEnabled]) and this server
/// has not said it lacks it.
final searchOfferedProvider = Provider<bool>(
  (ref) => kSearchEnabled && ref.watch(searchSupportedProvider),
);

// --- Recent searches ---------------------------------------------------------

/// Where the recent searches are kept (SharedPreferences, this device). Not
/// one of `PrefKeys.keptOnSignOut`, so signing out forgets them.
const recentSearchesKey = 'recent_searches';

/// How many recent searches are kept (§6.8).
const recentSearchesMax = 5;

/// The last [recentSearchesMax] searches, newest first: what the search
/// page shows before anything is typed.
final recentSearchesProvider =
    NotifierProvider.autoDispose<RecentSearches, List<String>>(
        RecentSearches.new);

class RecentSearches extends Notifier<List<String>> {
  @override
  List<String> build() =>
      ref.watch(sharedPrefsProvider).getStringList(recentSearchesKey) ??
      const [];

  /// Puts [query] first; the same words typed in another case move up
  /// rather than coming twice.
  Future<void> add(String query) async {
    final q = query.trim();
    if (!isSearchable(q)) return;
    final key = trFold(q);
    await _save([
      q,
      for (final s in state)
        if (trFold(s) != key) s,
    ].take(recentSearchesMax).toList());
  }

  Future<void> remove(String query) =>
      _save([for (final s in state) if (s != query) s]);

  Future<void> _save(List<String> next) async {
    state = next;
    await ref.read(sharedPrefsProvider).setStringList(recentSearchesKey, next);
  }
}

// --- The search itself -------------------------------------------------------

/// What the search page shows.
@immutable
class SearchState {
  const SearchState({
    this.query = '',
    this.results,
    this.searching = false,
    this.error,
  });

  /// The field's text without its surrounding spaces.
  final String query;

  /// The latest answer shown — kept, while a newer [query] is on its way,
  /// until that one's answer replaces it. Its own `query` may be older.
  final SearchResults? results;

  /// [query]'s answer is still to come (typing has not paused yet, or the
  /// request is out).
  final bool searching;

  /// Why the search for [query] failed; null when it has not.
  final Object? error;

  /// Too short to search: the page shows the recent searches.
  bool get idle => !isSearchable(query);
}

final searchProvider =
    NotifierProvider.autoDispose<SearchNotifier, SearchState>(
        SearchNotifier.new);

/// Turns the field's text into searches: [type] waits for typing to pause
/// ([searchDebounce]), sends nothing below [searchMinLength], and keeps the
/// results shown until the next answer arrives. An answer whose `query` is
/// not the text in the field any more is dropped (requests can overtake
/// each other).
class SearchNotifier extends Notifier<SearchState> {
  Timer? _debounce;

  @override
  SearchState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SearchState();
  }

  /// The field's text is now [text]: search it once typing pauses.
  void type(String text) => _set(text.trim(), debounce: true);

  /// Searches [text] now: a recent search tapped, the keyboard's search key.
  void searchNow(String text) => _set(text.trim(), debounce: false);

  /// Tries the failed search again.
  void retry() => _set(state.query, debounce: false, force: true);

  /// Searches the shown query again in the background — after something
  /// opened from the results may have changed it (the server does not cache
  /// results, contract §13.1). What is shown stays, and stays should it fail.
  void refresh() {
    if (state.idle || state.searching) return;
    unawaited(_run(state.query, quiet: true));
  }

  /// Leaves [result] out of what is shown: its record is gone.
  void drop(SearchResult result) {
    final results = state.results;
    if (results == null) return;
    state = SearchState(
      query: state.query,
      results: results.without(result),
      searching: state.searching,
      error: state.error,
    );
  }

  void _set(String query, {required bool debounce, bool force = false}) {
    final same = query == state.query;
    // Typing that leaves the text as it was (a space at the end) asks
    // nothing new.
    if (same && debounce && !force) return;
    // Asked now for the text whose request is already out: its answer comes.
    if (same && !force && state.searching && _debounce == null) return;
    _debounce?.cancel();
    _debounce = null;
    if (!isSearchable(query)) {
      state = SearchState(query: query, results: state.results);
      return;
    }
    state = SearchState(query: query, results: state.results, searching: true);
    if (debounce) {
      _debounce = Timer(searchDebounce, () => _run(query));
    } else {
      unawaited(_run(query));
    }
  }

  Future<void> _run(String query, {bool quiet = false}) async {
    _debounce = null;
    final repo = ref.read(repositoryProvider);
    try {
      final answer = await repo.search(query);
      if (!ref.mounted) return;
      // Out of order: an answer for text that is no longer in the field.
      if (answer.query != state.query && query != state.query) return;
      // The text came back to what was asked while a second ask waited.
      _debounce?.cancel();
      _debounce = null;
      state = SearchState(query: state.query, results: answer);
    } catch (error) {
      if (!ref.mounted || query != state.query) return;
      if (error is ApiException) {
        if (error.kind == ApiErrorKind.notFound) {
          ref
              .read(searchMissingOnProvider.notifier)
              .missing(ref.read(serverUrlProvider));
        } else if (error.code == 'query_too_short') {
          // The server trims more than the app (contract §13.1): nothing
          // left to search for.
          state = SearchState(
            query: query,
            results: SearchResults(query: query, results: const []),
          );
          return;
        }
      }
      // A background refresh that fails keeps what is shown.
      if (quiet) return;
      // As on success: a second ask for this same text, waiting on the
      // debounce, is not sent unseen after the error shows.
      _debounce?.cancel();
      _debounce = null;
      state = SearchState(query: query, results: state.results, error: error);
    }
  }
}

// --- Highlighting -------------------------------------------------------------

/// Where [query] occurs in [text], as `[start, end)` ranges of [text], found
/// the way the server matches (contract §13, "Text matching"): any case by
/// Turkish rules, I, İ, ı and i one letter, accents kept. A result can match
/// on a field it does not show (a note, a body): then there is no range.
List<(int, int)> searchMatches(String text, String query) {
  final needle = trFold(query.trim());
  if (needle.isEmpty) return const [];
  // Fold rune by rune, remembering which runes of [text] each folded code
  // unit came from, so a match maps back even where folding changed the
  // length.
  final folded = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  var at = 0;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final fold = trFold(char);
    for (var k = 0; k < fold.length; k++) {
      starts.add(at);
      ends.add(at + char.length);
    }
    folded.write(fold);
    at += char.length;
  }
  final haystack = folded.toString();
  final out = <(int, int)>[];
  var from = 0;
  while (from <= haystack.length - needle.length) {
    final found = haystack.indexOf(needle, from);
    if (found < 0) break;
    final last = found + needle.length - 1;
    out.add((starts[found], ends[last]));
    from = found + needle.length;
  }
  return out;
}
