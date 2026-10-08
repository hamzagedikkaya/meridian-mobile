import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/sync.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_detail_screen.dart';
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

  testWidgets('a goal deleted elsewhere while its screen is open',
      (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(_app(api, const GoalDetailScreen(goalId: 3)));
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('Kitap'), findsOneWidget);

    api.fail('GET /goals/3', 404);
    tester.container().read(dataSyncProvider).refresh([goalDetailProvider(3)]);
    await _settle(tester);
    expect(find.text('Bu hedef silinmiş'), findsOneWidget);
    expect(find.byType(OfflineBanner), findsNothing);
    expect(find.text('Tekrar dene'), findsNothing);
    expect(find.text('Kitap'), findsNothing);

    await tester.tap(find.text('Geri dön'));
    await tester.pumpAndSettle();
    expect(find.byType(GoalDetailScreen), findsNothing);
  });

  testWidgets('a goal already deleted when its screen opens', (tester) async {
    final api = FakeApi()..fail('GET /goals/3', 404);
    await tester.pumpWidget(_app(api, const GoalDetailScreen(goalId: 3)));
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('Bu hedef silinmiş'), findsOneWidget);
    expect(find.text('Hedef yüklenemedi'), findsNothing);
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
    await _settle(tester);
    expect(find.text('Bu günlük kaydı silinmiş'), findsOneWidget);
    expect(find.byType(OfflineBanner), findsNothing);
    expect(find.text('Sakin bir gün'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);

    await tester.tap(find.text('Geri dön'));
    await tester.pumpAndSettle();
    expect(find.byType(JournalDetailScreen), findsNothing);
  });
}
