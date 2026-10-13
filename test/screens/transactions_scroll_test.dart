/// A refetch of a long transactions feed (after a write, on resume, …) must
/// not move the list under the user's thumb: it reloads the first pages and
/// keeps the rest, so the list keeps its length and its scroll position.
library;

import 'package:dio/dio.dart';
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
import 'package:meridian_mobile/ui/screens/finance/transactions_screen.dart';

import '../support/fake_api.dart';

/// 320 rows, newest first, all on one day.
Map<String, dynamic> _page(RequestOptions request) {
  final page = int.parse('${request.queryParameters['page'] ?? 1}');
  final first = (page - 1) * 50;
  final last = first + 50 > 320 ? 320 : first + 50;
  return {
    'transactions': [
      for (var i = first; i < last; i++)
        {...transactionJson(id: 5000 - i), 'description': 'Satır ${i + 1}'},
    ],
    'meta': {
      'total_count': 320,
      'page': page,
      'page_limit': 50,
      'filtered_income_cents': 0,
      'filtered_expense_cents': 0,
    },
  };
}

/// Pumps until the fake API has answered (the feed's own "loading more"
/// spinner never settles).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('a refetch deep in a long feed keeps the scroll position and '
      'the rows on screen', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = FakeApi()..onRequest('GET /transactions', _page);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(api.dio)],
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
          home: const TransactionsScreen(),
        ),
      ),
    );
    await _settle(tester);

    final container = tester.container();
    final notifier = container.read(
      transactionsProvider(const TxFilters()).notifier,
    );
    // Infinite scroll, six times (the fake answers on the next frames).
    for (var i = 0; i < 6; i++) {
      final more = notifier.loadMore();
      await _settle(tester);
      await more;
    }
    expect(
      container.read(transactionsProvider(const TxFilters())).value!.items,
      hasLength(320),
    );

    // Scroll past what a refetch reloads (five pages, 250 rows).
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    // (The extent below the viewport is estimated until it is laid out, so
    // it takes a few jumps to get there.)
    for (var i = 0; i < 5; i++) {
      position.jumpTo(position.maxScrollExtent * 0.9);
      await _settle(tester);
    }
    final offset = position.pixels;
    final shown = find.textContaining('Satır 2');
    expect(shown, findsWidgets);
    final before = [for (final e in shown.evaluate()) (e.widget as Text).data];
    api.clearLog();

    container.read(dataSyncProvider).refresh([transactionsProvider]);
    await _settle(tester);

    // Five pages, as promised — not the constant under test.
    expect(api.gets, hasLength(5));
    expect(position.pixels, offset, reason: 'the list did not move');
    final after = [
      for (final e in find.textContaining('Satır 2').evaluate())
        (e.widget as Text).data,
    ];
    expect(after, before, reason: 'the same rows under the thumb');
  });
}
