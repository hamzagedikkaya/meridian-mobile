/// The journal never loses what was written (contract G4 journal): an edit
/// starts from the whole body and sends it back only when its text changed
/// — and over web formatting only once the user agrees — drafts are kept
/// per entry when the app goes to the background and when the editor
/// closes, come back with a way to discard them, and are cleared once
/// saved; a delete has undo.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/journal.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

/// Twenty paragraphs, 2,000-odd characters, as written on the web.
final _longBody = [
  for (var i = 0; i < 20; i++) 'Paragraf $i: ${'kelime ' * 13}'.trim(),
].join('\n\n');

Map<String, dynamic> _fullJson({
  String? body,
  String format = 'plain',
  List<String> formatting = const [],
}) => {
  ...journalEntryJson(),
  'body_plain': body ?? _longBody,
  'body_text': body ?? _longBody,
  'body_format': format,
  'body_formatting': formatting,
  'updated_at': '2026-10-04T12:30:00.000+03:00',
};

JournalEntry _full({String? body, String format = 'plain'}) =>
    JournalEntry.fromJson(
      _fullJson(
        body: body,
        format: format,
        formatting: format == 'rich' ? const ['bold', 'list'] : const [],
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  FakeApi api, {
  JournalEntry? entry,
}) async {
  tester.view.physicalSize = const Size(1290, 3600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(api.dio)],
      retry: (_, _) => null,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        supportedLocales: AppL10n.supportedLocales,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => openJournalEditor(context, entry: entry),
                    child: const Text('open'),
                  ),
                  TextButton(
                    onPressed: () => openJournalEditor(context),
                    child: const Text('new'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const JournalDetailScreen(entryId: 20),
                      ),
                    ),
                    child: const Text('detail'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(WidgetTester tester, String button) async {
  await tester.tap(find.text(button));
  await _settle(tester);
}

Finder _field(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

String _text(WidgetTester tester, String hint) =>
    tester.widget<TextField>(_field(hint)).controller!.text;

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Kapat'));
  await _settle(tester);
}

Future<String?> _draft([int? id]) => const FlutterSecureStorage().read(
  key: id == null ? 'journal_draft' : 'journal_draft_$id',
);

void main() {
  setUpAll(initializeDateFormatting);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('editing an entry', () {
    testWidgets('starts from the whole body — 2,000 characters and every '
        'paragraph — and an edit of the title leaves it out', (tester) async {
      expect(_longBody.length, greaterThan(2000));
      final api = FakeApi();
      await _pump(tester, api, entry: _full());
      await _open(tester, 'open');
      expect(
        _text(tester, 'Bugün neler oldu?'),
        _longBody,
        reason: 'byte for byte, never the 200-character preview',
      );

      await tester.enterText(_field('Başlık'), 'Uzun bir pazar');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(api.bodiesOf('PATCH /journal_entries/20'), [
        {'title': 'Uzun bir pazar'},
      ]);
      expect(find.byType(JournalEditorScreen), findsNothing);
    });

    testWidgets('a changed body is sent whole, as plain text', (tester) async {
      final api = FakeApi();
      await _pump(tester, api, entry: _full());
      await _open(tester, 'open');
      final edited = '$_longBody\n\nYeni bir paragraf <3';
      await tester.enterText(_field('Bugün neler oldu?'), edited);
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(api.bodiesOf('PATCH /journal_entries/20'), [
        {'body_text': edited},
      ]);
    });

    testWidgets('saving without a change sends nothing', (tester) async {
      final api = FakeApi();
      await _pump(tester, api, entry: _full());
      await _open(tester, 'open');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(api.bodiesOf('PATCH /journal_entries/20'), isEmpty);
      expect(find.byType(JournalEditorScreen), findsNothing);
    });

    testWidgets('a web entry says its formatting is kept unless the text '
        'changes, and a changed text asks first', (tester) async {
      final api = FakeApi();
      await _pump(tester, api, entry: _full(format: 'rich'));
      await _open(tester, 'open');
      expect(find.textContaining('kalın yazı, liste'), findsOneWidget);

      await tester.enterText(_field('Bugün neler oldu?'), 'Başka bir metin');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(find.text('Biçimlendirme kaldırılsın mı?'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await _settle(tester);
      expect(api.bodiesOf('PATCH /journal_entries/20'), isEmpty);
      expect(
        find.byType(JournalEditorScreen),
        findsOneWidget,
        reason: 'the text stays to keep editing',
      );

      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      await tester.tap(find.text('Yine de kaydet'));
      await _settle(tester);
      expect(api.bodiesOf('PATCH /journal_entries/20'), [
        {'body_text': 'Başka bir metin', 'discard_formatting': true},
      ]);
    });

    testWidgets('formatting added on the web meanwhile (body_has_formatting): '
        'asks, then sends the same change with the go-ahead', (tester) async {
      final api = FakeApi()
        ..on('PATCH /journal_entries/20', {
          'errors': {
            'body_text': ['x'],
          },
          'code': 'body_has_formatting',
          'body_formatting': ['link'],
        }, status: 422);
      await _pump(tester, api, entry: _full());
      await _open(tester, 'open');
      await tester.enterText(_field('Bugün neler oldu?'), 'Yeni metin');
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(find.text('Biçimlendirme kaldırılsın mı?'), findsOneWidget);
      expect(find.textContaining('bağlantı'), findsOneWidget);

      api.on('PATCH /journal_entries/20', {
        'entry': _fullJson(body: 'Yeni metin'),
      });
      await tester.tap(find.text('Yine de kaydet'));
      await _settle(tester);
      expect(api.bodiesOf('PATCH /journal_entries/20'), [
        {'body_text': 'Yeni metin'},
        {'body_text': 'Yeni metin', 'discard_formatting': true},
      ]);
      expect(find.byType(JournalEditorScreen), findsNothing);
    });

    testWidgets('the mood can be changed or cleared', (tester) async {
      final api = FakeApi();
      await _pump(tester, api, entry: _full());
      await _open(tester, 'open');
      await tester.tap(find.text('İyi'));
      await _settle(tester);
      await tester.tap(find.text('Ruh halini kaldır'));
      await _settle(tester);
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(api.bodiesOf('PATCH /journal_entries/20'), [
        {'mood': null},
      ]);
    });

    testWidgets('given a list item, the editor loads the full entry first', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('GET /journal_entries/20', {'entry': _fullJson()});
      final preview = JournalEntry.fromJson({
        ...journalListItemJson(),
        'body_plain': '${_longBody.substring(0, 197)}...',
      });
      await _pump(tester, api, entry: preview);
      await _open(tester, 'open');
      expect(_text(tester, 'Bugün neler oldu?'), _longBody);
    });
  });

  testWidgets('a new entry keeps its paragraphs, sent as plain text', (
    tester,
  ) async {
    final api = FakeApi();
    await _pump(tester, api);
    await _open(tester, 'new');
    await tester.tap(find.text('Geç')); // the mood step
    await _settle(tester);
    const body = 'İlk paragraf.\nAynı paragrafta.\n\nİkinci paragraf <3';
    await tester.enterText(_field('Bugün neler oldu?'), body);
    await tester.tap(find.text('Kaydet'));
    await _settle(tester);
    final sent = api.bodiesOf('POST /journal_entries').single as Map;
    expect(sent['body_text'], body);
    expect(sent.containsKey('body'), isFalse);
  });

  testWidgets('a mood alone is a check-in worth saving', (tester) async {
    final api = FakeApi();
    await _pump(tester, api);
    await _open(tester, 'new');
    await tester.tap(find.text('Harika'));
    await _settle(tester);
    await tester.tap(find.text('Kaydet'));
    await _settle(tester);
    expect(
      (api.bodiesOf('POST /journal_entries').single as Map)['mood'],
      'great',
    );
  });

  group('drafts', () {
    testWidgets('kept when the app goes to the background and when the '
        'editor closes; back next time, with a way to discard them', (
      tester,
    ) async {
      final api = FakeApi();
      await _pump(tester, api);
      await _open(tester, 'new');
      await tester.tap(find.text('Geç'));
      await _settle(tester);
      await tester.enterText(_field('Bugün neler oldu?'), 'Yarım kalan yazı');

      // Before the 5-second autosave: the app is put away.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(await _draft(), contains('Yarım kalan yazı'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      await tester.enterText(_field('Bugün neler oldu?'), 'Yarım kalan yazı!');
      await _close(tester);
      expect(
        await _draft(),
        contains('Yarım kalan yazı!'),
        reason: 'closing keeps what was typed since',
      );

      await _open(tester, 'new');
      expect(find.text('Kaydedilmemiş taslak geri yüklendi'), findsOneWidget);
      expect(_text(tester, 'Bugün neler oldu?'), 'Yarım kalan yazı!');

      await tester.tap(find.text('Taslağı at'));
      await _settle(tester);
      expect(_text(tester, 'Bugün neler oldu?'), isEmpty);
      expect(await _draft(), isNull);
    });

    testWidgets('cleared once saved', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'journal_draft':
            '{"date":"2026-10-04","title":"","body":"Taslak","mood":"good",'
            '"weather":null,"energy":0,"gratitude":"","tags":""}',
      });
      final api = FakeApi();
      await _pump(tester, api);
      await _open(tester, 'new');
      expect(_text(tester, 'Bugün neler oldu?'), 'Taslak');
      expect(
        find.text('Bugün nasıl hissediyorsun?'),
        findsNothing,
        reason: 'the restored mood skips the mood step',
      );
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(api.bodiesOf('POST /journal_entries'), hasLength(1));
      expect(await _draft(), isNull);

      // The next new entry starts blank.
      await _open(tester, 'new');
      expect(find.text('Kaydedilmemiş taslak geri yüklendi'), findsNothing);
    });

    testWidgets('an edit has a draft of its own, never shown in a new entry', (
      tester,
    ) async {
      final api = FakeApi();
      await _pump(tester, api, entry: _full());
      await _open(tester, 'open');
      await tester.enterText(_field('Başlık'), 'Yarım başlık');
      await _close(tester);
      expect(await _draft(20), contains('Yarım başlık'));
      expect(await _draft(), isNull);

      await _open(tester, 'new');
      expect(find.text('Kaydedilmemiş taslak geri yüklendi'), findsNothing);
      await _close(tester);

      await _open(tester, 'open');
      expect(find.text('Kaydedilmemiş taslak geri yüklendi'), findsOneWidget);
      expect(_text(tester, 'Başlık'), 'Yarım başlık');
    });

    for (final fails in [true, false]) {
      testWidgets(
        'closed while saving: a save that '
        '${fails ? 'fails keeps the text as a draft' : 'succeeds clears it'}',
        (tester) async {
          final api = FakeApi()..hold('POST /journal_entries');
          if (fails) api.failNetwork('POST /journal_entries');
          await _pump(tester, api);
          await _open(tester, 'new');
          await tester.tap(find.text('Geç'));
          await _settle(tester);
          await tester.enterText(_field('Bugün neler oldu?'), 'Kaybolmasın');
          await tester.tap(find.text('Kaydet'));
          await tester.pump();
          await _close(tester);
          expect(find.byType(JournalEditorScreen), findsNothing);

          api.release('POST /journal_entries');
          await _settle(tester);
          if (fails) {
            expect(await _draft(), contains('Kaybolmasın'));
          } else {
            expect(await _draft(), isNull);
          }
        },
      );
    }

    testWidgets('a draft brings back only what it changed, and says so when '
        'the entry changed elsewhere since — the web text is not written '
        'over', (tester) async {
      String snapshot({required String title, required String body}) =>
          '{"date":"2026-10-04","title":"$title","body":"$body",'
          '"mood":"good","weather":null,"energy":3,"gratitude":"","tags":""}';
      FlutterSecureStorage.setMockInitialValues({
        'journal_draft_20': '{"fields":'
            '${snapshot(title: 'Yeni başlık', body: 'Eski metin')},'
            '"base":${snapshot(title: 'Sakin bir gün', body: 'Eski metin')},'
            '"updated_at":"2026-10-03T09:00:00.000Z"}',
      });
      final api = FakeApi();
      // Edited on the web after the draft was written.
      await _pump(tester, api, entry: _full(body: 'Webde yazılmış yeni metin'));
      await _open(tester, 'open');
      expect(_text(tester, 'Başlık'), 'Yeni başlık');
      expect(_text(tester, 'Bugün neler oldu?'), 'Webde yazılmış yeni metin');
      expect(find.textContaining('başka yerde değişti'), findsOneWidget);

      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(api.bodiesOf('PATCH /journal_entries/20'), [
        {'title': 'Yeni başlık'},
      ]);
    });

    testWidgets('a draft of the entry as it still is restores quietly', (
      tester,
    ) async {
      final api = FakeApi();
      await _pump(tester, api, entry: _full());
      await _open(tester, 'open');
      await tester.enterText(_field('Başlık'), 'Yarım başlık');
      await _close(tester);
      expect(await _draft(20), contains('"updated_at"'));

      await _open(tester, 'open');
      expect(find.text('Kaydedilmemiş taslak geri yüklendi'), findsOneWidget);
      expect(find.textContaining('başka yerde değişti'), findsNothing);
    });

    test('drafts belong to the account that wrote them: another account '
        'signing in starts without them', () async {
      FlutterSecureStorage.setMockInitialValues({
        'journal_draft': '{}',
        'journal_draft_20': '{}',
      });
      final drafts = DraftStore(const FlutterSecureStorage());
      await drafts.claimFor('9:demo@meridian.local');
      expect(await _draft(), '{}', reason: 'drafts from before: kept');
      await drafts.claimFor('9:demo@meridian.local');
      expect(await _draft(20), '{}', reason: 'the same account');
      await drafts.claimFor('12:baska@meridian.local');
      expect(await _draft(), isNull);
      expect(await _draft(20), isNull);
    });

    test('signing in claims the drafts for that account', () async {
      SharedPreferences.setMockInitialValues({'installed': true});
      final prefs = await SharedPreferences.getInstance();
      FlutterSecureStorage.setMockInitialValues({
        'journal_draft': '{}',
        'journal_drafts_owner': '12:baska@meridian.local',
      });
      final api = FakeApi()
        ..on('POST /session', {'token': 't', 'user': userJson()});
      final container = ProviderContainer.test(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(api.dio),
        ],
      );
      await container
          .read(sessionProvider.notifier)
          .login('demo@meridian.local', 'x');
      expect(await _draft(), isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'journal_drafts_owner'),
        '9:demo@meridian.local',
      );
    });

    testWidgets('the mood row can be activated by a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final api = FakeApi();
      await _pump(tester, api, entry: _full());
      await _open(tester, 'open');
      final node = tester.getSemantics(find.bySemanticsLabel(RegExp('^Ruh hali')));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.semantics.tap(find.semantics.byLabel(RegExp('^Ruh hali')));
      await _settle(tester);
      expect(find.text('Bugün nasıl hissediyorsun?'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an editor closed unchanged leaves no draft', (tester) async {
      final api = FakeApi();
      await _pump(tester, api, entry: _full());
      await _open(tester, 'open');
      await _close(tester);
      expect(await _draft(20), isNull);
    });

    test('an expired session or a new server address keeps drafts; signing '
        'out drops them', () async {
      SharedPreferences.setMockInitialValues({'installed': true});
      final prefs = await SharedPreferences.getInstance();
      Future<ProviderContainer> signedInWithDrafts() async {
        FlutterSecureStorage.setMockInitialValues({
          'journal_draft': '{}',
          'journal_draft_20': '{}',
          'api_token': 't',
        });
        final container = ProviderContainer.test(
          overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        );
        await container.read(sessionProvider.notifier).restore();
        expect(container.read(sessionProvider), isA<SessionLoggedIn>());
        return container;
      }

      var container = await signedInWithDrafts();
      await container.read(sessionProvider.notifier).forceLogout();
      expect(await _draft(), '{}', reason: 'a 401: sign back in to it');
      expect(await _draft(20), '{}');
      expect(await const FlutterSecureStorage().read(key: 'api_token'), isNull);

      container = await signedInWithDrafts();
      await container.read(sessionProvider.notifier).serverChanged();
      expect(await _draft(), '{}', reason: 'the same server, another address');

      container = await signedInWithDrafts();
      await container.read(sessionProvider.notifier).logout();
      expect(await _draft(), isNull);
      expect(await _draft(20), isNull);
    });
  });

  group('deleting an entry', () {
    testWidgets('back to the list at once, with undo; the delete goes when '
        'the snackbar does', (tester) async {
      final api = FakeApi();
      await _pump(tester, api);
      await _open(tester, 'detail');
      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);
      await tester.tap(find.text('Sil'));
      await _settle(tester);
      expect(find.byType(JournalDetailScreen), findsNothing);
      expect(find.text('Kayıt silindi'), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /journal_entries/20')));

      await tester.pump(const Duration(seconds: 7));
      await _settle(tester);
      expect(api.requests, contains('DELETE /journal_entries/20'));
    });

    testWidgets('undone: nothing is sent', (tester) async {
      final api = FakeApi();
      await _pump(tester, api);
      await _open(tester, 'detail');
      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);
      await tester.tap(find.text('Sil'));
      await _settle(tester);
      await tester.tap(find.text('Geri al'));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 7));
      await _settle(tester);
      expect(api.requests, isNot(contains('DELETE /journal_entries/20')));
    });
  });
}
