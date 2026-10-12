import 'date_utils.dart';
import 'json_read.dart';

class JournalEntry {
  final int id;
  final DateTime date;
  final String? title;
  final String? bodyPlain;
  final String? mood;
  final String? moodEmoji;
  final int? energyLevel;
  final String? weather;
  final List<String> tags;
  final bool hasGratitude;
  final DateTime? createdAt;

  /// Detail-only fields (GET /journal_entries/:id).
  final String? bodyHtml;
  final String? gratitude;

  /// The whole body as plain text — line breaks and blank lines between
  /// paragraphs kept — what the editor edits. Detail only: a list item's
  /// [bodyPlain] is a 200-character preview, never to be edited or saved.
  final String? bodyText;

  /// `"rich"` when the body has web formatting plain text cannot hold
  /// (bold, lists, links…: [bodyFormatting]); `"plain"` otherwise.
  final String? bodyFormat;
  final List<String> bodyFormatting;
  final DateTime? updatedAt;

  const JournalEntry({
    required this.id,
    required this.date,
    this.title,
    this.bodyPlain,
    this.mood,
    this.moodEmoji,
    this.energyLevel,
    this.weather,
    required this.tags,
    required this.hasGratitude,
    this.createdAt,
    this.bodyHtml,
    this.gratitude,
    this.bodyText,
    this.bodyFormat,
    this.bodyFormatting = const [],
    this.updatedAt,
  });

  /// Whether this is the full entry (`GET /journal_entries/:id`, or a save's
  /// answer) rather than a list item: only the full one may be edited.
  bool get isFull => bodyText != null || bodyHtml != null;

  /// Saving a different text over it drops web formatting.
  bool get isRich => bodyFormat == 'rich';

  /// The text the editor starts from: the whole body. An older server
  /// without `body_text` sends the whole text as `body_plain` in the full
  /// entry.
  String get editableBody => bodyText ?? bodyPlain ?? '';

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: readId(json['id']),
        date: DateTime.parse(json['date'] as String),
        title: json['title'] as String?,
        bodyPlain: json['body_plain'] as String?,
        mood: json['mood'] as String?,
        moodEmoji: json['mood_emoji'] as String?,
        energyLevel: readIntOrNull(json['energy_level']),
        weather: json['weather'] as String?,
        tags: ((json['tags'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        hasGratitude: readBool(json['has_gratitude']),
        createdAt: parseDateTime(json['created_at']),
        bodyHtml: json['body_html'] as String?,
        gratitude: json['gratitude'] as String?,
        bodyText: json['body_text'] as String?,
        bodyFormat: json['body_format'] as String?,
        bodyFormatting: ((json['body_formatting'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        updatedAt: parseDateTime(json['updated_at']),
      );
}

class JournalBundle {
  final List<JournalEntry> entries;
  final int entriesCount;
  final int journalStreak;

  /// Consecutive Monday–Sunday weeks with an entry (`meta.journal_streak_weeks`,
  /// WP-15); null from a server without it — the meta line then falls back
  /// to the day streak.
  final int? journalStreakWeeks;
  final Map<String, int> moodCounts;
  final String range;

  const JournalBundle({
    required this.entries,
    required this.entriesCount,
    required this.journalStreak,
    this.journalStreakWeeks,
    required this.moodCounts,
    required this.range,
  });

  factory JournalBundle.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map<String, dynamic>?) ?? const {};
    final rawMoods = (meta['mood_counts'] as Map?) ?? const {};
    return JournalBundle(
      entries: ((json['entries'] as List?) ?? const [])
          .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      entriesCount: readInt(meta['entries_count']),
      journalStreak: readInt(meta['journal_streak']),
      journalStreakWeeks: meta.containsKey('journal_streak_weeks')
          ? readInt(meta['journal_streak_weeks'])
          : null,
      moodCounts:
          rawMoods.map((key, value) => MapEntry('$key', readInt(value))),
      range: (meta['range'] as String?) ?? '30d',
    );
  }
}

/// How the server compares a body sent back with the stored one
/// (`body_text`): line endings, spaces at line ends, non-breaking spaces and
/// blank space around the text do not count.
String normalizedBody(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\u00A0', ' ')
    .split('\n')
    .map((line) => line.trimRight())
    .join('\n')
    .trim();

/// Create/update body — `tags` is comma-joined for the wire.
///
/// The body travels as [bodyText], plain text (`body_text`): the server
/// keeps its line breaks and paragraphs, and escapes it, so `<3` stays
/// text. It is never sent as `body`, which the server reads as HTML.
class JournalInput {
  final DateTime date;
  final String? title;
  final String? bodyText;
  final String? mood;
  final String? weather;
  final int? energyLevel;
  final String? gratitude;
  final List<String> tags;

  const JournalInput({
    required this.date,
    this.title,
    this.bodyText,
    this.mood,
    this.weather,
    this.energyLevel,
    this.gratitude,
    this.tags = const [],
  });

  static String? _text(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String get _tags => tags.join(',');

  /// `POST /journal_entries`.
  Map<String, dynamic> toJson() => {
        'date': isoDate(date),
        'title': _text(title),
        'body_text': _text(bodyText),
        'mood': mood,
        'weather': _text(weather),
        'energy_level': energyLevel,
        'gratitude': _text(gratitude),
        'tags': _tags,
      };

  /// Whether the body differs from [before]'s, the way the server compares.
  bool bodyChangedFrom(JournalEntry before) =>
      normalizedBody(bodyText ?? '') != normalizedBody(before.editableBody);

  /// `PATCH /journal_entries/:id`: only what differs from [before]. The body
  /// goes only when its text changed, so a web entry whose title, mood or
  /// tags were edited keeps its formatting untouched. [discardFormatting]
  /// confirms that a changed body may replace a rich one.
  Map<String, dynamic> changesFrom(
    JournalEntry before, {
    bool discardFormatting = false,
  }) {
    final changedBody = bodyChangedFrom(before);
    return {
      if (isoDate(date) != isoDate(before.date)) 'date': isoDate(date),
      if (_text(title) != _text(before.title)) 'title': _text(title),
      if (changedBody) 'body_text': _text(bodyText),
      if (changedBody && discardFormatting) 'discard_formatting': true,
      if (mood != before.mood) 'mood': mood,
      if (_text(weather) != _text(before.weather)) 'weather': _text(weather),
      if (energyLevel != before.energyLevel) 'energy_level': energyLevel,
      if (_text(gratitude) != _text(before.gratitude))
        'gratitude': _text(gratitude),
      if (_tags != before.tags.join(',')) 'tags': _tags,
    };
  }
}
