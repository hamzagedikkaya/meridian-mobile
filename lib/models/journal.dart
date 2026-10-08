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
  });

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
      );
}

class JournalBundle {
  final List<JournalEntry> entries;
  final int entriesCount;
  final int journalStreak;
  final Map<String, int> moodCounts;
  final String range;

  const JournalBundle({
    required this.entries,
    required this.entriesCount,
    required this.journalStreak,
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
      moodCounts:
          rawMoods.map((key, value) => MapEntry('$key', readInt(value))),
      range: (meta['range'] as String?) ?? '30d',
    );
  }
}

/// Create/update body — `tags` is comma-joined for the wire.
class JournalInput {
  final DateTime date;
  final String? title;
  final String? body;
  final String? mood;
  final String? weather;
  final int? energyLevel;
  final String? gratitude;
  final List<String> tags;

  const JournalInput({
    required this.date,
    this.title,
    this.body,
    this.mood,
    this.weather,
    this.energyLevel,
    this.gratitude,
    this.tags = const [],
  });

  Map<String, dynamic> toJson() => {
        'date': isoDate(date),
        'title': title,
        'body': body,
        'mood': mood,
        'weather': weather,
        'energy_level': energyLevel,
        'gratitude': gratitude,
        'tags': tags.join(','),
      };
}
