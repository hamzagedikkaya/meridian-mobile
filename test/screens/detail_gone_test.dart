import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/sync.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_form.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_editor.dart';
import 'package:meridian_mobile/ui/widgets/offline_banner.dart';

import '../support/fake_api.dart';

/// [detail] opened from a list screen, against [api].
Widget _app(FakeApi api, Widget detail) => ProviderScope(
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
              child: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => detail)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A detail screen whose record was deleted on the web or on another device
/// says so — a retry could only answer 404 again — instead of putting up the
/// offline banner, which blames the connection.
void main() {
  setUpAll(initializeDateFormatting);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('a goal deleted elsewhere while its screen is open',
      (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(_app(api, const GoalDetailScreen(goalId: 3)));
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('Kitap'), findsOneWidget);

    api.fail('GET /goals/3', 404);
    tester.container().read(dataSyncProvider).refresh([goalDetailProvider(3)]);
    await tester.pump(const Duration(milliseconds: 50));
    // What happened, not a connection problem…
    expect(find.text('Bu hedef silinmiş'), findsWidgets);
    expect(find.byType(OfflineBanner), findsNothing);
    expect(find.text('Tekrar dene'), findsNothing);

    // …and back to the list, which says it too.
    await tester.pumpAndSettle();
    expect(find.byType(GoalDetailScreen), findsNothing);
    expect(
      find.descendant(
          of: find.byType(SnackBar), matching: find.text('Bu hedef silinmiş')),
      findsOneWidget,
    );
  });

  testWidgets('a goal already deleted when its screen opens', (tester) async {
    final api = FakeApi()..fail('GET /goals/3', 404);
    await tester.pumpWidget(_app(api, const GoalDetailScreen(goalId: 3)));
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('Bu hedef silinmiş'), findsWidgets);
    expect(find.text('Hedef yüklenemedi'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(GoalDetailScreen), findsNothing);
  });

  testWidgets('a goal that cannot be refreshed still gets the offline banner',
      (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(_app(api, const GoalDetailScreen(goalId: 3)));
    await tester.tap(find.text('open'));
    await _settle(tester);

    api.failNetwork('GET /goals/3');
    tester.container().read(dataSyncProvider).refresh([goalDetailProvider(3)]);
    await _settle(tester);
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(find.text('Kitap'), findsOneWidget);
    expect(find.text('Bu hedef silinmiş'), findsNothing);
  });

  testWidgets('a journal entry deleted elsewhere while its screen is open: '
      'no edit or delete on it either', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(_app(api, const JournalDetailScreen(entryId: 20)));
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('Sakin bir gün'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);

    api.fail('GET /journal_entries/20', 404);
    tester
        .container()
        .read(dataSyncProvider)
        .refresh([journalEntryProvider(20)]);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Bu günlük kaydı silinmiş'), findsWidgets);
    expect(find.byType(OfflineBanner), findsNothing);
    expect(find.text('Sakin bir gün'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byTooltip('Düzenle'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(JournalDetailScreen), findsNothing);
    expect(
      find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Bu günlük kaydı silinmiş')),
      findsOneWidget,
    );
  });

  group('deleted elsewhere while edited over its screen', () {
    Finder bodyField() => find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Bugün neler oldu?',
        );

    Future<void> openEditor(WidgetTester tester, FakeApi api) async {
      tester.view.physicalSize = const Size(1290, 3600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(api, const JournalDetailScreen(entryId: 20)));
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.tap(find.byTooltip('Düzenle'));
      await _settle(tester);
      expect(find.byType(JournalEditorScreen), findsOneWidget);
      await tester.enterText(bodyField(), 'Yarım kalan uzun bir metin');
      await tester.pump();
    }

    testWidgets('a refresh finds the entry gone: the editor and its text '
        'stay, and save it as a new entry; the detail goes after', (
      tester,
    ) async {
      final api = FakeApi();
      await openEditor(tester, api);

      api.fail('GET /journal_entries/20', 404);
      tester
          .container()
          .read(dataSyncProvider)
          .refresh([journalEntryProvider(20)]);
      await _settle(tester);
      // Nothing closed under the user: the editor, the text, and the way on.
      expect(find.byType(JournalEditorScreen), findsOneWidget);
      expect(find.byType(JournalDetailScreen, skipOffstage: false),
          findsOneWidget);
      expect(find.textContaining('başka yerde silindi'), findsOneWidget);
      expect(
        tester.widget<TextField>(bodyField()).controller!.text,
        'Yarım kalan uzun bir metin',
      );
      // What is typed now is a new entry's draft.
      await tester.pump(journalDraftInterval);
      expect(await const FlutterSecureStorage().read(key: 'journal_draft'),
          contains('Yarım kalan'));
      expect(await const FlutterSecureStorage().read(key: 'journal_draft_20'),
          isNull);

      await tester.tap(find.text('Yeni kayıt olarak kaydet'));
      await _settle(tester);
      expect(api.requests, isNot(contains('PATCH /journal_entries/20')));
      final created = api.bodiesOf('POST /journal_entries').single as Map;
      expect(created['body_text'], 'Yarım kalan uzun bir metin');
      expect(await const FlutterSecureStorage().read(key: 'journal_draft'),
          isNull);

      // Then the gone entry's screen goes too, leaving the "added" word.
      await tester.pumpAndSettle();
      expect(find.byType(JournalEditorScreen), findsNothing);
      expect(find.byType(JournalDetailScreen), findsNothing);
      expect(find.text('Kayıt eklendi ✓'), findsOneWidget);
    });

    testWidgets('a save answered 404 keeps the editor and the text', (
      tester,
    ) async {
      final api = FakeApi();
      await openEditor(tester, api);
      api
        ..fail('PATCH /journal_entries/20', 404)
        ..fail('GET /journal_entries/20', 404);
      await tester.tap(find.text('Kaydet'));
      await _settle(tester);
      expect(find.byType(JournalEditorScreen), findsOneWidget);
      expect(find.textContaining('başka yerde silindi'), findsOneWidget);
      expect(
        tester.widget<TextField>(bodyField()).controller!.text,
        'Yarım kalan uzun bir metin',
      );

      // Closed without saving: the text waits in the new entry's draft,
      // and the gone entry's screen goes, saying why.
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      expect(await const FlutterSecureStorage().read(key: 'journal_draft'),
          contains('Yarım kalan'));
      expect(find.byType(JournalDetailScreen), findsNothing);
      expect(
        find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('Bu günlük kaydı silinmiş')),
        findsOneWidget,
      );
    });

    testWidgets('a goal deleted while its form is open: the form stays, and '
        'nothing asks to discard; the detail goes once it is closed', (
      tester,
    ) async {
      final api = FakeApi();
      tester.view.physicalSize = const Size(1290, 3600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(api, const GoalDetailScreen(goalId: 3)));
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.tap(find.byTooltip('Düzenle'));
      await _settle(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Hedef adı'), 'Yeni ad');
      await tester.pump();

      api.fail('GET /goals/3', 404);
      tester.container().read(dataSyncProvider).refresh([goalDetailProvider(3)]);
      await _settle(tester);
      expect(find.byType(GoalFormScreen), findsOneWidget);
      expect(find.text('Değişiklikleri at'), findsNothing);
      expect(find.byType(GoalDetailScreen, skipOffstage: false),
          findsOneWidget);

      await tester.tap(find.byTooltip('Kapat'));
      await _settle(tester);
      await tester.tap(find.text('Değişiklikleri at'));
      await tester.pumpAndSettle();
      expect(find.byType(GoalFormScreen), findsNothing);
      expect(find.byType(GoalDetailScreen), findsNothing);
      expect(
        find.descendant(
            of: find.byType(SnackBar), matching: find.text('Bu hedef silinmiş')),
        findsOneWidget,
      );
    });
  });
}
