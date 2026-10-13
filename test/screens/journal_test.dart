import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/journal.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_editor.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_screen.dart';
import 'package:meridian_mobile/ui/screens/journal/widgets/mood.dart';
import 'package:meridian_mobile/ui/widgets/entrance.dart';
import 'package:meridian_mobile/ui/widgets/streak_flame.dart';

import '../support/app_harness.dart';
import '../support/fake_api.dart';
import '../support/semantics.dart';

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
      'body_plain': 'Sabah yoga ile başladım, gün boyu enerjim yüksek kaldı.',
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
    'mood_counts': {'great': 1, 'good': 1, 'neutral': 0, 'bad': 0, 'awful': 0},
    'range': '30d',
  },
});

/// Empty range: no entries, zero streak, all mood counts zero (real payload).
JournalBundle _emptyBundle() => JournalBundle.fromJson({
  'entries': <dynamic>[],
  'meta': {
    'entries_count': 0,
    'journal_streak': 0,
    'mood_counts': {'great': 0, 'good': 0, 'neutral': 0, 'bad': 0, 'awful': 0},
    'range': '30d',
  },
});

Widget _harness(JournalBundle bundle, {DateTime? today}) {
  return ProviderScope(
    overrides: [
      journalProvider.overrideWith(
        (ref, range) => Fetched(bundle, DateTime(2026, 7, 11)),
      ),
      if (today != null) clockProvider.overrideWithValue(() => today),
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

/// The populated bundle as a WP-15 server sends it: with the week streak.
JournalBundle _withWeeks(int weeks) {
  final b = _populatedBundle();
  return JournalBundle(
    entries: b.entries,
    entriesCount: b.entriesCount,
    journalStreak: b.journalStreak,
    journalStreakWeeks: weeks,
    moodCounts: b.moodCounts,
    range: b.range,
  );
}

/// Every entrance on screen has finished: none replays.
void _expectNoEntrancePlaying(WidgetTester tester) {
  for (final entrance in tester.widgetList(find.byType(Entrance))) {
    final fade = tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byWidget(entrance),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1.0, reason: 'an entrance replayed');
  }
}

/// No state told by half opacity (design-analysis §3.4 rule 7).
void _expectNoHalfOpacity(WidgetTester tester) {
  for (final o in tester.widgetList<Opacity>(find.byType(Opacity))) {
    expect(o.opacity, isNot(0.5));
  }
}

Finder _moodChip(String label) =>
    find.byWidgetPredicate((w) => w is MoodFilterChip && w.mood == label);

/// A tall phone, so every card of the populated range is laid out.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1290, 3600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('renders populated journal range without exceptions', (
    tester,
  ) async {
    // Sanity: fromJson survives the null/empty/0 rows before pumping.
    expect(
      _entryFromJson(const {
        'id': 1,
        'date': '2026-05-01',
        'tags': null,
        'has_gratitude': null,
      }).tags,
      isEmpty,
    );

    _tall(tester);
    await tester.pumpWidget(_harness(_populatedBundle()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Günlük'), findsOneWidget); // app bar
    expect(find.text('Son 30 gün'), findsOneWidget); // range chip
    expect(find.text('3 kayıt'), findsOneWidget); // meta line
    // No week count from this server: the day streak, as a StreakFlame.
    expect(find.byType(StreakFlame), findsOneWidget);
    expect(find.bySemanticsLabel('3 günlük seri'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.textContaining('🔥'), findsNothing);
    expect(find.text('Harika bir gün'), findsOneWidget); // titled entry
    // No title: the first sentence stands in; "Adsız" only without text.
    expect(find.text('Kısa bir not.'), findsOneWidget);
    expect(find.text('Adsız'), findsNothing);
    expect(find.text('Sessiz gün'), findsOneWidget); // null-mood/0-energy row
    expect(find.text('Yaz'), findsOneWidget); // the FAB
    // Not today's: the today card asks, with five moods.
    expect(find.text('Bugün nasıldı?'), findsOneWidget);
    // EnergyBars speak inside the card's one merged button.
    expect(find.bySemanticsLabel(RegExp('Enerji 3 / 5')), findsOneWidget);
    _expectNoHalfOpacity(tester);
  });

  testWidgets('the week streak from WP-15 servers: "n haftadır yazıyorsun"', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_withWeeks(6)));
    await tester.pumpAndSettle();
    expect(find.text('6 haftadır yazıyorsun'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.byType(StreakFlame), findsNothing);
  });

  testWidgets('a zero week streak hides the line', (tester) async {
    await tester.pumpWidget(_harness(_withWeeks(0)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    expect(find.textContaining('yazıyorsun'), findsNothing);
  });

  testWidgets("today's entry leads under a gold BUGÜN, without the prompt", (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_populatedBundle(), today: DateTime(2026, 5, 25, 12)),
    );
    await tester.pumpAndSettle();
    expect(find.text('BUGÜN'), findsOneWidget);
    expect(find.text('Bugün nasıldı?'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Harika bir gün')).dy,
      lessThan(tester.getTopLeft(find.byType(MoodFilterChip).first).dy),
      reason: 'the today slot comes first',
    );
  });

  testWidgets('a mood on the today card opens the editor with that mood', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_harness(_emptyBundle()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MoodStrip),
        matching: find.text('Harika'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(JournalEditorScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Ruh hali: Harika'), findsOneWidget);
  });

  testWidgets('renders empty journal range without exceptions', (tester) async {
    await tester.pumpWidget(_harness(_emptyBundle()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Günlük'), findsOneWidget);
    // No "0 kayıt" over the empty range (§7.15): its empty state says it.
    expect(find.text('0 kayıt'), findsNothing);
    expect(find.text('Bugün nasıldı?'), findsOneWidget); // today card
    expect(find.text('Bu aralıkta kayıt yok'), findsOneWidget);
    expect(find.text('Tüm kayıtlar'), findsOneWidget);
    // Streak hidden at 0; never a flame by a zero.
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    expect(find.textContaining('🔥'), findsNothing);
  });

  testWidgets('the mood filter: chips change at once, the cards after a '
      'fade — no entrance replays, nothing at half opacity', (tester) async {
    await tester.pumpWidget(_harness(_populatedBundle()));
    await tester.pumpAndSettle();

    await tester.tap(_moodChip('great'));
    await tester.pump();
    expect(tester.widget<MoodFilterChip>(_moodChip('great')).selected, isTrue);
    expect(tester.widget<MoodFilterChip>(_moodChip('good')).muted, isTrue);
    await tester.pump(const Duration(milliseconds: 120));
    _expectNoEntrancePlaying(tester);
    await tester.pumpAndSettle();
    expect(find.text('Kısa bir not.'), findsOneWidget);
    expect(find.text('Harika bir gün'), findsNothing);
    expect(find.text('Sessiz gün'), findsNothing);
    _expectNoHalfOpacity(tester);

    // Again: the filter goes, every card is back — still no entrance.
    await tester.tap(_moodChip('great'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    _expectNoEntrancePlaying(tester);
    await tester.pumpAndSettle();
    expect(find.text('Harika bir gün'), findsOneWidget);
  });

  testWidgets('a tag filters the journal on the phone, and clears', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_harness(_populatedBundle()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('tek'));
    await tester.tap(find.text('tek'));
    await tester.pumpAndSettle();
    expect(find.text('Etiket: tek'), findsOneWidget);
    expect(find.text('Sessiz gün'), findsOneWidget);
    expect(find.text('Harika bir gün'), findsNothing);

    await tester.tap(find.text('Etiket: tek'));
    await tester.pumpAndSettle();
    expect(find.text('Etiket: tek'), findsNothing);
    expect(find.text('Harika bir gün'), findsOneWidget);
  });

  testWidgets('the range chip picks a range; six months and more group by '
      'month; the entrance does not replay', (tester) async {
    await tester.pumpWidget(_harness(_populatedBundle()));
    await tester.pumpAndSettle();
    expect(find.text('Mayıs 2026'), findsNothing);

    await tester.tap(find.text('Son 30 gün'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Son 6 ay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    _expectNoEntrancePlaying(tester);
    await tester.pumpAndSettle();
    expect(find.text('Son 6 ay'), findsOneWidget);
    expect(find.text('Mayıs 2026'), findsOneWidget);
  });

  testWidgets('a card offers its long press and its tags to a screen reader '
      'as custom actions', (tester) async {
    final handle = tester.ensureSemantics();
    _tall(tester);
    await tester.pumpWidget(_harness(_populatedBundle()));
    await tester.pumpAndSettle();
    final card = tester.getSemantics(find.text('Sessiz gün'));
    expect(
      customActionLabels(card),
      containsAll(['Düzenle', 'Sil', 'Etiket: tek']),
    );
    performCustomAction(card, 'Etiket: tek');
    await tester.pumpAndSettle();
    // The tag filter is on: only the tagged entry is left.
    expect(find.text('Etiket: tek'), findsOneWidget);
    expect(find.text('Harika bir gün'), findsNothing);
    handle.dispose();
  });

  group('against the API', () {
    testWidgets('a range still loading keeps the last one up; once it lands '
        'no entrance replays', (tester) async {
      final api = FakeApi();
      await pumpWithRoutes(tester, api, home: const JournalScreen());
      await tester.pumpAndSettle();
      expect(find.text('Sakin bir gün'), findsOneWidget);

      api.hold('GET /journal_entries');
      await tester.tap(find.text('Son 30 gün'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Son 6 ay'));
      await settleFrames(tester);
      expect(find.text('Sakin bir gün'), findsOneWidget, reason: 'kept up');

      api.release('GET /journal_entries');
      await tester.pump();
      await tester.pump();
      _expectNoEntrancePlaying(tester);
      await tester.pumpAndSettle();
      expect(find.text('Son 6 ay'), findsOneWidget);
      expect(find.text('Sakin bir gün'), findsOneWidget);
    });

    testWidgets('long press → Sil: the card goes at once, the delete only '
        'once the undo has run out', (tester) async {
      final api = FakeApi();
      await pumpWithRoutes(tester, api, home: const JournalScreen());
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Sakin bir gün'));
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsOneWidget);
      await tester.tap(find.text('Sil'));
      await settleFrames(tester);
      expect(find.text('Sakin bir gün'), findsNothing);
      expect(find.text('Geri al'), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /journal_entries/20')));

      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /journal_entries/20'));
    });

    testWidgets('Sil from a screen reader, then Geri al: the card is back '
        'and nothing is sent', (tester) async {
      final handle = tester.ensureSemantics();
      final api = FakeApi();
      await pumpWithRoutes(tester, api, home: const JournalScreen());
      await tester.pumpAndSettle();
      performCustomAction(
        tester.getSemantics(find.text('Sakin bir gün')),
        'Sil',
      );
      await settleFrames(tester);
      expect(find.text('Sakin bir gün'), findsNothing);
      await tester.tap(find.text('Geri al'));
      await settleFrames(tester);
      expect(find.text('Sakin bir gün'), findsOneWidget);

      await letUndoRunOut(tester);
      expect(api.requests, isNot(contains('DELETE /journal_entries/20')));
      handle.dispose();
    });
  });
}
