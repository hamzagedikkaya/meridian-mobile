/// Where the journal's snackbars land in the running app (§4.17): a screen
/// that has closed says its last word over the FAB or capture bar of the
/// screen the user is back on — Today's capture bar after an entry opened
/// from "Bugün yazdın" is deleted, the journal's "Yaz" after the "Günlüğe
/// yaz" shortcut's editor saves — and what the editor says fits in the
/// snackbar's two lines on a 360 dp phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/l10n/app_l10n_en.dart';
import 'package:meridian_mobile/l10n/app_l10n_tr.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/router/app_router.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_editor.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';
import 'package:meridian_mobile/ui/widgets/app_snackbar.dart';
import 'package:meridian_mobile/ui/widgets/capture_bar.dart';
import 'package:meridian_mobile/ui/widgets/collapsing_fab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_fonts.dart';
import '../support/app_harness.dart';
import '../support/fake_api.dart';

class _Session extends SessionController {
  @override
  SessionState build() => const SessionLoggedIn();
}

/// The app as it runs on a 360 × 780 dp phone, signed in, at [fixtureNow].
Future<void> _pumpApp(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'locale': 'tr'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        sessionProvider.overrideWith(_Session.new),
        dioProvider.overrideWithValue(api.dio),
        clockProvider.overrideWithValue(() => fixtureNow),
      ],
      child: const MeridianApp(),
    ),
  );
  await settleFrames(tester);
}

/// The snackbar's surface.
Rect _snackRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
      .first,
);

void main() {
  setUpAll(initializeDateFormatting);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Today → "Bugün yazdın" → Sil: the undo snackbar floats over '
      "Today's capture bar", (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api);
    await tester.scrollUntilVisible(
      find.text('Bugün yazdın'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(TodayScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settleFrames(tester);
    await tester.tap(find.text('Bugün yazdın'));
    await settleFrames(tester);
    expect(find.byType(JournalDetailScreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await settleFrames(tester);
    await tester.tap(find.text('Sil'));
    await settleFrames(tester);
    expect(find.byType(JournalDetailScreen), findsNothing);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).margin,
      const EdgeInsets.fromLTRB(16, 0, 16, 76),
    );
    final bar = tester.getRect(find.byType(CaptureBar));
    expect(_snackRect(tester).bottom, lessThanOrEqualTo(bar.top));
  });

  testWidgets('the "Günlüğe yaz" shortcut: "Kayıt eklendi" floats over the '
      '"Yaz" FAB', (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api);
    tester.container().read(routerProvider).go('/journal?new=1');
    await settleFrames(tester);
    expect(find.byType(JournalEditorScreen), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Bugün neler oldu?',
      ),
      'Kısayoldan',
    );
    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    expect(find.byType(JournalEditorScreen), findsNothing);
    expect(find.text('Kayıt eklendi'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).margin,
      const EdgeInsets.fromLTRB(16, 0, 16, 80),
    );
    final fab = tester.getRect(find.byType(CollapsingFab));
    expect(_snackRect(tester).bottom, lessThanOrEqualTo(fab.top));
  });

  group('in the app\'s fonts on a 360 dp phone', () {
    setUpAll(loadAppFonts);

    for (final (lang, l) in <(String, AppL10n)>[
      ('tr', AppL10nTr()),
      ('en', AppL10nEn()),
    ]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets("the editor's snackbars fit their two lines ($lang, "
            '$scale×)', (tester) async {
          tester.view.physicalSize = const Size(1080, 2340);
          tester.view.devicePixelRatio = 3.0;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          late BuildContext context;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(Brightness.dark),
              home: Scaffold(
                body: Builder(
                  builder: (c) {
                    context = c;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          );
          for (final (message, action) in <(String, String?)>[
            (l.journalSaveFailedKept, l.journalOpenDraft),
            (l.journalGoneDraftKept, l.journalOpenDraft),
            (l.journalMaybeSaved, l.journalSaveAnyway),
            (l.journalMaybeSavedLater, null),
          ]) {
            showAppSnack(
              context,
              message,
              isError: true,
              actionLabel: action,
              onAction: action == null ? null : () {},
            );
            await tester.pumpAndSettle();
            final text = tester.renderObject<RenderParagraph>(
              find.text(message),
            );
            expect(text.didExceedMaxLines, isFalse, reason: message);
          }
        });
      }
    }
  });
}
