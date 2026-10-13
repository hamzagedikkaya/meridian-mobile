/// Quick add, as reviewed (WP-17 review, group g2): an answer that lands
/// after the sheet was closed is still named on the screen, with "Geri
/// al"; and what quick add creates grows in where it lands, like any add.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/data_scope.dart';
import 'package:meridian_mobile/data/recent_changes.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/flows/flows.dart';

import '../support/fake_api.dart';

/// A screen with an "open" button that opens quick add; its container.
Future<ProviderContainer> _open(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(api.dio),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 4, 12, 30)),
      ],
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
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => openQuickAdd(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.text('open')));
}

/// Types [text], sends it, and closes the sheet while the answer is on its
/// way.
Future<void> _sendAndClose(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byType(FilledButton).last);
  await _frames(tester);
  await tester.tap(find.byTooltip('Kapat'));
  await tester.pumpAndSettle();
  expect(find.byType(TextField), findsNothing, reason: 'the sheet is gone');
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('a task saved after the sheet was closed is still named, with '
      '"Geri al" — and it grows in where it lands', (tester) async {
    final api = FakeApi()..hold('POST /todos');
    final container = await _open(tester, api);
    await _sendAndClose(tester, 'süt al');
    api.release('POST /todos');
    await _frames(tester);
    expect(api.requests, contains('POST /todos'));
    expect(find.textContaining('Görev eklendi'), findsOneWidget);
    expect(find.text('Geri al'), findsOneWidget);
    expect(
      container.read(recentChangesProvider)[(scope: DataScope.todos, id: 40)]
          ?.kind,
      ChangeKind.inserted,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a line read by the server after the sheet was closed is '
      'still named', (tester) async {
    final api = FakeApi()..hold('POST /quick_captures');
    final container = await _open(tester, api);
    await _sendAndClose(tester, '-85 kahve');
    api.release('POST /quick_captures');
    await _frames(tester);
    expect(api.requests, contains('POST /quick_captures'));
    // The fake server files it as a task.
    expect(find.textContaining('Görev eklendi'), findsOneWidget);
    expect(
      container.read(recentChangesProvider)[(scope: DataScope.todos, id: 40)]
          ?.kind,
      ChangeKind.inserted,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('with the sheet up, a saved task is noted for its row too', (
    tester,
  ) async {
    final api = FakeApi();
    final container = await _open(tester, api);
    await tester.enterText(find.byType(TextField), 'süt al');
    await tester.pump();
    await tester.tap(find.byType(FilledButton).last);
    await _frames(tester);
    expect(
      container.read(recentChangesProvider)[(scope: DataScope.todos, id: 40)]
          ?.kind,
      ChangeKind.inserted,
    );
    await tester.pumpAndSettle();
  });
}
