/// The journal after review (WP-13 review fixes): an older plain entry reads
/// as its paragraphs, a web link offers its address, nothing the editor
/// says is lost or hidden — a save that fails or lands after the editor
/// closed, a new entry whose answer was lost, an entry that cannot load or
/// was deleted elsewhere — and snackbars clear the "Yaz" FAB and the
/// accessory bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/search.dart';
import 'package:meridian_mobile/models/journal.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/theme/entity_color.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_editor.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_screen.dart';
import 'package:meridian_mobile/ui/screens/journal/widgets/mood.dart';

import '../support/app_harness.dart';
import '../support/fake_api.dart';

/// A draft store that counts what reaches secure storage.
class _CountingDrafts extends DraftStore {
  _CountingDrafts() : super(const FlutterSecureStorage());
  var writes = 0;
  var clears = 0;

  @override
  Future<void> write(String value, {int? entryId}) {
    writes++;
    return super.write(value, entryId: entryId);
  }

  @override
  Future<void> clear({int? entryId}) {
    clears++;
    return super.clear(entryId: entryId);
  }
}

/// The detail of entry 20 over a blank page.
Future<void> _pumpDetail(WidgetTester tester, FakeApi api) async {
  await pumpWithRoutes(
    tester,
    api,
    home: opener(
      (context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const JournalDetailScreen(entryId: 20),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settleFrames(tester);
}

/// The editor over a blank page: [entry] to edit, else a new one.
Future<void> _pumpEditor(
  WidgetTester tester,
  FakeApi api, {
  JournalEntry? entry,
  String? initialMood,
  DraftStore? drafts,
}) async {
  await pumpWithRoutes(
    tester,
    api,
    overrides: [
      if (drafts != null) draftStoreProvider.overrideWithValue(drafts),
    ],
    home: opener(
      (context) =>
          openJournalEditor(context, entry: entry, initialMood: initialMood),
    ),
  );
  await tester.tap(find.text('open'));
  await settleFrames(tester);
}

/// The journal tab inside an outer scaffold, as the shell holds it.
Future<void> _pumpTab(WidgetTester tester, FakeApi api) =>
    pumpWithRoutes(tester, api, home: const Scaffold(body: JournalScreen()));

Finder _field(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

Future<String?> _draft([int? id]) => const FlutterSecureStorage().read(
  key: id == null ? 'journal_draft' : 'journal_draft_$id',
);

/// A journal list of [entries], [count] in the range in all.
Map<String, Object?> _listOf(List<Object?> entries, {int? count}) => {
  'entries': entries,
  'meta': {'entries_count': count ?? entries.length, 'journal_streak': 1},
};

/// The list item of the entry the tests' lost save created: "Sakin bir
/// gün" · "Kısa bir not." · İyi, created just after it was sent.
Map<String, Object?> _arrivedItem({int id = 21}) => {
  ...journalListItemJson(id: id),
  'energy_level': null,
  // Late that day: after the send, in whichever zone the test runs.
  'created_at': '2026-10-04T23:59:00.000+03:00',
};

EdgeInsetsGeometry? _snackMargin(WidgetTester tester) =>
    tester.widget<SnackBar>(find.byType(SnackBar)).margin;

void main() {
  setUpAll(initializeDateFormatting);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('the detail', () {
    testWidgets('a plain entry an older app saved as raw text reads as its '
        'paragraphs, not as one block from its HTML', (tester) async {
      const text =
          'Sabah erken kalktım.\n\nKahvemi alıp yürüdüm.\n\nAkşam annemi aradım.';
      final api = FakeApi()
        ..on('GET /journal_entries/20', {
          'entry': {
            ...journalEntryJson(),
            'body_plain': text,
            'body_text': text,
            'body_format': 'plain',
            // What ActionText renders for raw text: one run-on paragraph.
            'body_html': '<div class="trix-content">\n  $text\n</div>\n',
          },
        });
      await _pumpDetail(tester, api);
      expect(find.byType(HtmlWidget), findsNothing);
      for (final p in text.split('\n\n')) {
        expect(find.text(p), findsOneWidget, reason: p);
      }
    });

    testWidgets("a web entry's link offers its address to copy", (
      tester,
    ) async {
      final api = FakeApi()
        ..on('GET /journal_entries/20', {
          'entry': {
            ...journalEntryJson(),
            'body_text': 'Şunu oku: bu yazı',
            'body_format': 'rich',
            'body_formatting': ['link'],
            'body_html':
                '<div class="trix-content"><div>Şunu oku: '
                '<a href="https://example.com/yazi">bu yazı</a></div></div>',
          },
        });
      final copied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied.add(call.arguments);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pumpDetail(tester, api);
      expect(find.byType(HtmlWidget), findsOneWidget);
      await tester.tapOnText(find.textRange.ofSubstring('bu yazı'));
      await settleFrames(tester);
      expect(find.text('Bağlantı'), findsOneWidget);
      expect(find.text('https://example.com/yazi'), findsOneWidget);
      await tester.tap(find.text('Bağlantıyı kopyala'));
      await settleFrames(tester);
      expect(find.text('Bağlantı kopyalandı'), findsOneWidget);
      expect(copied, [
        {'text': 'https://example.com/yazi'},
      ]);
    });

    testWidgets('its date title stays whole at 200 % text on a 360 dp phone', (
      tester,
    ) async {
      final api = FakeApi();
      await _pumpDetail(tester, api);
      tester.view.physicalSize = const Size(1080, 2340);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await settleFrames(tester);
      final title = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.textContaining('2026'),
        ),
      );
      expect(title.didExceedMaxLines, isFalse);
      expect(title.text.toPlainText(), contains('Paz'));
    });

    testWidgets('a delete over the journal tab says so above its FAB, and '
        'drops the draft of an edit of that entry', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'journal_draft_20': '{"fields":{"title":"Yarım"}}',
      });
      final api = FakeApi();
      await _pumpTab(tester, api);
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const JournalDetailScreen(entryId: 20),
            ),
          );
      await settleFrames(tester);
      await tester.tap(find.byIcon(Icons.more_vert));
      await settleFrames(tester);
      await tester.tap(find.text('Sil'));
      await settleFrames(tester);
      expect(find.byType(JournalDetailScreen), findsNothing);
      expect(
        _snackMargin(tester),
        const EdgeInsets.fromLTRB(16, 0, 16, 80),
        reason: 'over the "Yaz" FAB',
      );
      await letUndoRunOut(tester);
      expect(api.requests, contains('DELETE /journal_entries/20'));
      expect(await _draft(20), isNull);
    });
  });

  group('the journal tab', () {
    testWidgets("a card's delete says so above the FAB", (tester) async {
      final api = FakeApi();
      await _pumpTab(tester, api);
      await tester.longPress(find.text('Sakin bir gün'));
      await settleFrames(tester);
      await tester.tap(find.text('Sil'));
      await settleFrames(tester);
      expect(_snackMargin(tester), const EdgeInsets.fromLTRB(16, 0, 16, 80));
    });

    testWidgets('"Yaz" → Kaydet: "Kayıt eklendi" above the FAB', (
      tester,
    ) async {
      final api = FakeApi();
      await _pumpTab(tester, api);
      await tester.tap(find.text('Yaz'));
      await settleFrames(tester);
      await tester.enterText(_field('Bugün neler oldu?'), 'Yeni bir gün');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(find.byType(JournalEditorScreen), findsNothing);
      expect(find.text('Kayıt eklendi'), findsOneWidget);
      expect(_snackMargin(tester), const EdgeInsets.fromLTRB(16, 0, 16, 80));
    });

    testWidgets('past the newest 180 the list says where it stops, and '
        'search reaches the older ones', (tester) async {
      final api = FakeApi()
        ..on('GET /journal_entries', {
          'entries': [journalListItemJson()],
          'meta': const {
            'entries_count': 312,
            'journal_streak': 1,
            'mood_counts': {
              'great': 0,
              'good': 1,
              'neutral': 0,
              'bad': 0,
              'awful': 0,
            },
            'range': '30d',
          },
        });
      await _pumpTab(tester, api);
      expect(find.text('312 kayıt'), findsOneWidget);
      expect(find.text('En yeni 1 kayıt gösteriliyor'), findsOneWidget);
      expect(find.text('Daha eskileri ara'), findsOneWidget);
    });
  });

  testWidgets("'awful' is the server's glyph everywhere (contract §7.1)", (
    tester,
  ) async {
    expect(journalMoodEmojis['awful'], '😞');
    expect(moodEmojiFor('awful'), moodEmojiFor('awful', serverEmoji: '😞'));
  });

  group('the editor', () {
    testWidgets('a save that fails after the editor closed is said, and '
        '"Aç" brings the text back', (tester) async {
      final api = FakeApi()
        ..hold('PATCH /journal_entries/20')
        ..failNetwork('PATCH /journal_entries/20');
      await _pumpEditor(
        tester,
        api,
        entry: JournalEntry.fromJson(journalEntryJson()),
      );
      await tester.enterText(_field('Başlık'), 'Yeni başlık');
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      await tester.tap(find.byTooltip('Kapat'));
      await settleFrames(tester);
      expect(find.byType(JournalEditorScreen), findsNothing);

      api.release('PATCH /journal_entries/20');
      await settleFrames(tester);
      expect(
        find.text('Kaydedilemedi — taslak olarak saklandı'),
        findsOneWidget,
      );
      await tester.tap(find.text('Aç'));
      await settleFrames(tester);
      expect(find.byType(JournalEditorScreen), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('Başlık')).controller!.text,
        'Yeni başlık',
      );
    });

    testWidgets('a save that succeeds after the editor closed is said too', (
      tester,
    ) async {
      final api = FakeApi()..hold('POST /journal_entries');
      await _pumpEditor(tester, api);
      await tester.enterText(_field('Bugün neler oldu?'), 'Kaybolmasın');
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      await tester.tap(find.byTooltip('Kapat'));
      await settleFrames(tester);
      api.release('POST /journal_entries');
      await settleFrames(tester);
      expect(find.text('Kayıt eklendi'), findsOneWidget);
      expect(await _draft(), isNull);
    });

    testWidgets('a new entry whose answer was lost, found in the journal: '
        'saved, and never sent twice', (tester) async {
      final api = FakeApi()
        ..timeOut('POST /journal_entries')
        ..on('GET /journal_entries', _listOf([_arrivedItem()]));
      await _pumpEditor(tester, api);
      await tester.enterText(_field('Başlık'), 'Sakin bir gün');
      await tester.enterText(_field('Bugün neler oldu?'), 'Kısa bir not.');
      await tester.tap(find.text('İyi'));
      await settleFrames(tester);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /journal_entries'), hasLength(1));
      expect(find.byType(JournalEditorScreen), findsNothing);
      expect(find.text('Kayıt eklendi'), findsOneWidget);
      expect(await _draft(), isNull);
    });

    testWidgets('a new entry whose answer was lost, and the journal cannot '
        'be read: "may be saved", and Kaydet looks before sending again', (
      tester,
    ) async {
      final api = FakeApi()
        ..timeOut('POST /journal_entries')
        ..failNetwork('GET /journal_entries');
      await _pumpEditor(tester, api);
      await tester.enterText(_field('Başlık'), 'Sakin bir gün');
      await tester.enterText(_field('Bugün neler oldu?'), 'Kısa bir not.');
      await tester.tap(find.text('İyi'));
      await settleFrames(tester);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(find.textContaining('edilmiş olabilir'), findsOneWidget);
      expect(find.text('Kayıt kaydedilemedi'), findsNothing);
      expect(find.byType(JournalEditorScreen), findsOneWidget);

      // The server had it after all; the journal can be read again.
      api
        ..on('POST /journal_entries', {
          'entry': journalEntryJson(id: 21),
        }, status: 201)
        ..on('GET /journal_entries', _listOf([_arrivedItem()]));
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /journal_entries'), hasLength(1));
      expect(find.byType(JournalEditorScreen), findsNothing);
    });

    testWidgets('a new entry whose answer was lost and is not in the '
        'journal: the usual failure, and Kaydet sends it', (tester) async {
      final api = FakeApi()..timeOut('POST /journal_entries');
      await _pumpEditor(tester, api);
      await tester.enterText(_field('Bugün neler oldu?'), 'Bambaşka bir gün');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(find.text('Kayıt kaydedilemedi'), findsOneWidget);
      api.on('POST /journal_entries', {
        'entry': journalEntryJson(id: 21),
      }, status: 201);
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /journal_entries'), hasLength(2));
      expect(find.byType(JournalEditorScreen), findsNothing);
    });

    testWidgets('an entry that cannot load offers a retry, which loads it', (
      tester,
    ) async {
      final api = FakeApi()..failNetwork('GET /journal_entries/20');
      await _pumpEditor(
        tester,
        api,
        entry: JournalEntry.fromJson(journalListItemJson()),
      );
      expect(find.text('Tekrar dene'), findsOneWidget);
      api.on('GET /journal_entries/20', {'entry': journalEntryJson()});
      await tester.tap(find.text('Tekrar dene'));
      await settleFrames(tester);
      expect(
        tester.widget<TextField>(_field('Bugün neler oldu?')).controller!.text,
        'Kısa bir not.',
      );
    });

    testWidgets('an entry deleted elsewhere before it loaded: its draft '
        'comes back, to be saved as a new entry', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'journal_draft_20':
            '{"fields":{"date":"2026-10-04","title":"Yarım kalan",'
            '"body":"Kısa bir not. Ve dahası."},"base":{"date":"2026-10-04",'
            '"title":"Sakin bir gün","body":"Kısa bir not."}}',
      });
      final api = FakeApi()..fail('GET /journal_entries/20', 404);
      await _pumpEditor(
        tester,
        api,
        entry: JournalEntry.fromJson(journalListItemJson()),
      );
      expect(find.text('Yeni kayıt olarak kaydet'), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('Başlık')).controller!.text,
        'Yarım kalan',
      );
      await tester.pump(const Duration(seconds: 6));
      expect(await _draft(20), isNull);
      expect(await _draft(), contains('Yarım kalan'));
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(
        (api.bodiesOf('POST /journal_entries').single as Map)['title'],
        'Yarım kalan',
      );
    });

    testWidgets('an entry deleted elsewhere before it loaded, with no draft: '
        'said, with a way back', (tester) async {
      final api = FakeApi()..fail('GET /journal_entries/20', 404);
      await _pumpEditor(
        tester,
        api,
        entry: JournalEntry.fromJson(journalListItemJson()),
      );
      expect(find.text('Bu günlük kaydı silinmiş'), findsOneWidget);
      expect(find.text('Geri dön'), findsOneWidget);
    });

    testWidgets('an idle editor writes its draft once, not every tick', (
      tester,
    ) async {
      final drafts = _CountingDrafts();
      final api = FakeApi();
      await _pumpEditor(tester, api, drafts: drafts);
      await tester.enterText(_field('Bugün neler oldu?'), 'Bir satır');
      await tester.pump(const Duration(seconds: 6));
      expect(drafts.writes, 1);
      await tester.pump(const Duration(minutes: 1));
      expect(drafts.writes, 1);
      expect(drafts.clears, lessThanOrEqualTo(1));
    });

    testWidgets("a mood picked on 'Bugün nasıldı?' is for today, even over "
        "an older day's draft", (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'journal_draft':
            '{"fields":{"date":"2026-10-03","body":"Dünden kalan"}}',
      });
      final api = FakeApi();
      await _pumpEditor(tester, api, initialMood: 'great');
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      final sent = api.bodiesOf('POST /journal_entries').single as Map;
      expect(sent['date'], '2026-10-04');
      expect(sent['mood'], 'great');
      expect(sent['body_text'], 'Dünden kalan');
    });

    testWidgets("the editor's snackbars float above the accessory bar", (
      tester,
    ) async {
      final api = FakeApi();
      await _pumpEditor(tester, api);
      await tester.tap(find.text('Geç'));
      await settleFrames(tester);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      final snack = tester.getRect(
        find
            .descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Material),
            )
            .first,
      );
      final save = tester.getRect(find.text('Kaydet'));
      expect(snack.bottom, lessThanOrEqualTo(save.top));
    });

    testWidgets('the gratitude hint reads at 4.5:1 in both themes, and a '
        'long title wraps', (tester) async {
      final api = FakeApi();
      await _pumpEditor(tester, api);
      await tester.ensureVisible(find.text('Minnet'));
      await tester.tap(find.text('Minnet'));
      await settleFrames(tester);
      final hint = tester
          .widget<TextField>(
            find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  w.decoration?.hintText != null &&
                  w.decoration!.hintText!.contains('minnet'),
            ),
          )
          .decoration!
          .hintStyle!
          .color!;
      for (final brightness in Brightness.values) {
        final c = buildTheme(brightness).extension<NokturnColors>()!;
        final ink = Color.alphaBlend(
          c.onGoldContainer.withValues(alpha: hint.a),
          c.goldContainer,
        );
        expect(
          contrastRatio(ink, c.goldContainer),
          greaterThanOrEqualTo(4.5),
          reason: '$brightness',
        );
      }
      expect(tester.widget<TextField>(_field('Başlık')).maxLines, isNull);
    });
  });

  group('after the second review', () {
    testWidgets('a lost save, the editor closed: the draft brought back '
        'looks in the journal before it is sent again', (tester) async {
      final api = FakeApi()
        ..timeOut('POST /journal_entries')
        ..failNetwork('GET /journal_entries');
      await _pumpEditor(tester, api);
      await tester.enterText(_field('Başlık'), 'Sakin bir gün');
      await tester.enterText(_field('Bugün neler oldu?'), 'Kısa bir not.');
      await tester.tap(find.text('İyi'));
      await settleFrames(tester);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(find.textContaining('edilmiş olabilir'), findsOneWidget);
      await tester.tap(find.byTooltip('Kapat'));
      await settleFrames(tester);
      expect(find.byType(JournalEditorScreen), findsNothing);
      expect(await _draft(), contains('"sent"'));

      // The server had it; the journal can be read again.
      api
        ..on('POST /journal_entries', {
          'entry': journalEntryJson(id: 21),
        }, status: 201)
        ..on('GET /journal_entries', _listOf([_arrivedItem()]))
        ..clearLog();
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      expect(
        tester.widget<TextField>(_field('Başlık')).controller!.text,
        'Sakin bir gün',
      );
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.requests, contains('GET /journal_entries'));
      expect(api.bodiesOf('POST /journal_entries'), hasLength(1));
      expect(find.byType(JournalEditorScreen), findsNothing);
      expect(find.text('Kayıt eklendi'), findsOneWidget);
      expect(await _draft(), isNull);
    });

    testWidgets('closed while its save was on its way, and the answer lost: '
        'the draft remembers it was sent', (tester) async {
      final api = FakeApi()
        ..hold('POST /journal_entries')
        ..timeOut('POST /journal_entries')
        ..failNetwork('GET /journal_entries');
      await _pumpEditor(tester, api);
      await tester.enterText(_field('Başlık'), 'Sakin bir gün');
      await tester.enterText(_field('Bugün neler oldu?'), 'Kısa bir not.');
      await tester.tap(find.text('İyi'));
      await settleFrames(tester);
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      await tester.tap(find.byTooltip('Kapat'));
      await settleFrames(tester);
      api.release('POST /journal_entries');
      await settleFrames(tester);
      expect(find.textContaining('edilmiş olabilir'), findsOneWidget);
      expect(await _draft(), contains('"sent"'));

      api
        ..on('POST /journal_entries', {
          'entry': journalEntryJson(id: 21),
        }, status: 201)
        ..on('GET /journal_entries', _listOf([_arrivedItem()]));
      // The snackbar has gone by the time the editor is opened again.
      await tester.pump(const Duration(seconds: 7));
      await tester.tap(find.text('open'));
      await settleFrames(tester);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /journal_entries'), hasLength(1));
      expect(find.byType(JournalEditorScreen), findsNothing);
    });

    testWidgets('an older look-alike on the same day is not the lost save: '
        'the text stays', (tester) async {
      final api = FakeApi()
        ..timeOut('POST /journal_entries')
        ..on(
          'GET /journal_entries',
          _listOf([
            {
              ...journalListItemJson(id: 19),
              'title': null,
              'body_plain': '',
              'energy_level': null,
              // Early that day: before the send.
              'created_at': '2026-10-04T08:00:00.000+03:00',
            },
          ]),
        );
      await _pumpEditor(tester, api, initialMood: 'good');
      await tester.ensureVisible(find.text('Minnet'));
      await tester.tap(find.text('Minnet'));
      await settleFrames(tester);
      await tester.enterText(
        _field('Bugün ne için minnettarsın?'),
        'Annemle akşam yemeği',
      );
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /journal_entries'), hasLength(1));
      expect(find.byType(JournalEditorScreen), findsOneWidget);
      expect(find.text('Kayıt eklendi'), findsNothing);
      expect(await _draft(), contains('Annemle akşam yemeği'));
    });

    test('a list item is the lost save only if created after it was sent, '
        'with the same gratitude, energy, weather and tags', () {
      final sentAt = DateTime(2026, 10, 4, 9);
      final input = JournalInput(
        date: DateTime(2026, 10, 4),
        title: 'Sakin bir gün',
        bodyText: 'Kısa bir not.',
        mood: 'good',
        energyLevel: 3,
        tags: const ['aile'],
      );
      JournalEntry item(Map<String, Object?> change) => JournalEntry.fromJson({
        ...journalListItemJson(),
        'tags': const ['aile'],
        'created_at': '2026-10-04T09:00:30.000+03:00',
        ...change,
      });
      expect(journalEntryMatches(item({}), input, sentAt: sentAt), isTrue);
      for (final change in <Map<String, Object?>>[
        {'created_at': '2026-10-04T08:00:00.000+03:00'},
        {'has_gratitude': true},
        {'energy_level': 4},
        {'weather': 'sunny'},
        {'tags': const <String>[]},
      ]) {
        expect(
          journalEntryMatches(item(change), input, sentAt: sentAt),
          isFalse,
          reason: '$change',
        );
      }
    });

    testWidgets('the journal stops short of the day: "may be saved", and '
        '"Yine de kaydet" sends it', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'journal_draft': '{"fields":{"date":"2026-03-01","body":"Mart notu"}}',
      });
      final ranges = <Object?>[];
      final api = FakeApi()
        ..timeOut('POST /journal_entries')
        ..onRequest('GET /journal_entries', (request) {
          ranges.add(request.queryParameters['range']);
          return _listOf([
            {...journalListItemJson(), 'date': '2026-09-30'},
          ], count: 400);
        });
      await _pumpEditor(tester, api);
      await tester.tap(find.text('Kaydet'));
      await settleFrames(tester);
      expect(ranges, ['1y'], reason: 'the shortest range reaching 1 March');
      expect(find.textContaining('edilmiş olabilir'), findsOneWidget);
      expect(find.byType(JournalEditorScreen), findsOneWidget);

      api.on('POST /journal_entries', {
        'entry': journalEntryJson(id: 21),
      }, status: 201);
      await tester.tap(find.text('Yine de kaydet'));
      await settleFrames(tester);
      expect(api.bodiesOf('POST /journal_entries'), hasLength(2));
      expect(find.byType(JournalEditorScreen), findsNothing);
    });

    testWidgets('a line break pasted into the title is dropped', (
      tester,
    ) async {
      final api = FakeApi();
      await _pumpEditor(tester, api);
      await tester.enterText(_field('Başlık'), 'Bir\nİki');
      expect(
        tester.widget<TextField>(_field('Başlık')).controller!.text,
        'Birİki',
      );
    });

    testWidgets('"Daha eskileri ara" only where search is offered', (
      tester,
    ) async {
      final api = FakeApi()
        ..on(
          'GET /journal_entries',
          _listOf([journalListItemJson()], count: 312),
        );
      await _pumpTab(tester, api);
      expect(find.text('Daha eskileri ara'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(JournalScreen)),
      );
      container
          .read(searchMissingOnProvider.notifier)
          .missing(container.read(serverUrlProvider));
      await settleFrames(tester);
      expect(find.text('En yeni 1 kayıt gösteriliyor'), findsOneWidget);
      expect(find.text('Daha eskileri ara'), findsNothing);
    });
  });
}
