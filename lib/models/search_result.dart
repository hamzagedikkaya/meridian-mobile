import 'json_read.dart';

/// The kinds of record global search finds (`GET /search`, contract §13.1),
/// in the order the server lists them — and the screen groups them.
enum SearchResultType {
  transaction('transaction'),
  todo('todo'),
  event('event'),
  journalEntry('journal_entry'),
  goal('goal'),
  habit('habit'),
  subscription('subscription');

  const SearchResultType(this.wire);

  /// The `type` the server sends.
  final String wire;

  /// The type the server calls [wire]; null for one this app does not know
  /// (a type added to the server later), whose rows are left out.
  static SearchResultType? parse(Object? wire) {
    for (final type in values) {
      if (type.wire == wire) return type;
    }
    return null;
  }
}

/// One ready-to-show row: the server words [title] and [subtitle] in the
/// account's language and time zone ("3 Eki 2026 · Cüzdan · −₺85,00"), so
/// the app only lays them out. [id] opens the record on its own endpoint.
class SearchResult {
  final SearchResultType type;
  final int id;
  final String title;
  final String subtitle;

  const SearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
  });

  /// Null for a row of a type this app does not know, or without an id.
  static SearchResult? fromJson(Map<String, dynamic> json) {
    final type = SearchResultType.parse(json['type']);
    final id = readIntOrNull(json['id']);
    if (type == null || id == null) return null;
    return SearchResult(
      type: type,
      id: id,
      title: '${json['title'] ?? ''}',
      subtitle: '${json['subtitle'] ?? ''}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchResult && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

/// The answer to one search: [query] as the server applied it (the text
/// without its surrounding spaces) — which tells an answer to an older
/// query from the current one — and at most five [results] per type.
class SearchResults {
  final String query;
  final List<SearchResult> results;

  const SearchResults({required this.query, required this.results});

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
        query: '${json['query'] ?? ''}',
        results: [
          for (final row in (json['results'] as List?) ?? const [])
            if (row is Map<String, dynamic>) ?SearchResult.fromJson(row),
        ],
      );

  /// The rows by type, in [SearchResultType] order and each type's rows in
  /// the server's order; a type without rows has no group.
  List<(SearchResultType, List<SearchResult>)> get groups => [
        for (final type in SearchResultType.values)
          if (results.where((r) => r.type == type).toList()
              case final rows when rows.isNotEmpty)
            (type, rows),
      ];

  /// These results without [result] (a record gone since the search).
  SearchResults without(SearchResult result) => SearchResults(
        query: query,
        results: [
          for (final r in results)
            if (r != result) r,
        ],
      );
}
