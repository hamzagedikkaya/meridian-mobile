import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/journal.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_screen.dart';

// Fixtures shaped like GET /journal_entries (see api-samples.json). The list
// endpoint returned an empty payload in samples, so entry rows follow the
// documented entry shape (id/date/title/body_plain/mood/mood_emoji/
// energy_level/weather/tags/has_gratitude) and the single-entry sample (id 20).

JournalEntry _entryFromJson(Map<String, dynamic> json) =>
    JournalEntry.fromJson(json);

/// Populated range: mixed rows exercising every edge the card renders —
/// a full row, a null-title row (→ "Adsız"), and a null-mood + 0-energy row.
JournalBundle _populatedBundle() => JournalBundle.fromJson({
      'entries': [
        {
          'id': 20,
          'date': '2026-05-25',
          'title': 'Harika bir gün',
          'body_plain':
              'Sabah yoga ile başladım, gün boyu enerjim yüksek kaldı.',
          'mood': 'good',
          'mood_emoji': '🙂',
          'energy_level': 3,
          'weather': 'Güneşli',
          'tags': ['reflection', 'personal'],
          'has_gratitude': true,
          'created_at': '2026-05-25T19:10:59.640Z',
        },
        {
          'id': 21,
          'date': '2026-05-24',
          'title': null,
          'body_plain': 'Kısa bir not.',
          'mood': 'great',
          'mood_emoji': '😄',
          'energy_level': 5,
          'weather': null,
          'tags': <String>[],
          'has_gratitude': false,
          'created_at': '2026-05-24T20:00:00.000Z',
        },
        {
          'id': 22,
          'date': '2026-05-23',
          'title': 'Sessiz gün',
          'body_plain': null,
          'mood': null,
          'mood_emoji': null,
          'energy_level': 0,
          'weather': null,
          'tags': ['tek'],
          'has_gratitude': true,
          'created_at': '2026-05-23T09:00:00.000Z',
        },
      ],
      'meta': {
        'entries_count': 3,
        'journal_streak': 3,
        'mood_counts': {
          'great': 1,
          'good': 1,
          'neutral': 0,
          'bad': 0,
          'awful': 0,
        },
        'range': '30d',
      },
    });

/// Empty range: no entries, zero streak, all mood counts zero (real payload).
JournalBundle _emptyBundle() => JournalBundle.fromJson({
      'entries': <dynamic>[],
      'meta': {
        'entries_count': 0,
        'journal_streak': 0,
        'mood_counts': {
          'great': 0,
          'good': 0,
          'neutral': 0,
          'bad': 0,
          'awful': 0,
        },
        'range': '30d',
      },
    });

Widget _harness(JournalBundle bundle) {
  return ProviderScope(
    overrides: [
      journalProvider.overrideWith(
        (ref, range) => Fetched(bundle, DateTime(2026, 7, 11)),
      ),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const JournalScreen(),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  testWidgets('renders populated journal range without exceptions',
      (tester) async {
    // Sanity: fromJson survives the null/empty/0 rows before pumping.
    expect(_entryFromJson(const {
      'id': 1,
      'date': '2026-05-01',
      'tags': null,
      'has_gratitude': null,
    }).tags, isEmpty);

    await tester.pumpWidget(_harness(_populatedBundle()));
    await tester.pumpAndSettle();
    // Let the screen's 650ms stagger-retire timer fire so no timer outlives the
    // widget tree (the flutter_animate entrance settles earlier, at ~550ms).
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.takeException(), isNull);
    expect(find.text('Günlük'), findsOneWidget); // app bar
    expect(find.text('3 kayıt'), findsOneWidget); // meta line
    expect(find.text('🔥 3'), findsOneWidget); // streak flame pill
    expect(find.text('Harika bir gün'), findsOneWidget); // titled entry
    expect(find.text('Adsız'), findsOneWidget); // null-title fallback
    expect(find.text('Sessiz gün'), findsOneWidget); // null-mood/0-energy row
  });

  testWidgets('renders empty journal range without exceptions',
      (tester) async {
    await tester.pumpWidget(_harness(_emptyBundle()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Günlük'), findsOneWidget);
    expect(find.text('0 kayıt'), findsOneWidget);
    expect(find.text('Bugün nasıldı?'), findsOneWidget); // empty-state title
    expect(find.text('Kayıt oluştur'), findsOneWidget); // empty-state CTA
    // Streak pill hidden at 0.
    expect(find.textContaining('🔥'), findsNothing);
  });
}
