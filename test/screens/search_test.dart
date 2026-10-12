/// Global search (design-analysis §6.8, §7.14; WP-16) in the app as it
/// runs, served by the fake API: the ways in, the 250 ms debounce and the
/// two-character floor, results grouped by type with the typed text picked
/// out, each type opening its own surface, answers to older text dropped,
/// the recent searches, and the empty, offline, failed and no-search
/// states.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/search.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/router/app_router.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/search/search_entry_button.dart';
import 'package:meridian_mobile/ui/screens/search/search_screen.dart';
import 'package:meridian_mobile/ui/screens/todos/todo_sheet.dart';
import 'package:meridian_mobile/ui/widgets/day_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/semantics.dart';

class _Session extends SessionController {
  @override
  SessionState build() => const SessionLoggedIn();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The app, signed in, served by [api], on Today; its router.
Future<GoRouter> _pumpApp(
  WidgetTester tester,
  FakeApi api, {
  Map<String, Object> prefs = const {},
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (textScale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  SharedPreferences.setMockInitialValues({'locale': 'tr', ...prefs});
  final shared = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(shared),
        sessionProvider.overrideWith(_Session.new),
        dioProvider.overrideWithValue(api.dio),
      ],
      retry: (_, _) => null,
      child: const MeridianApp(),
    ),
  );
  await _settle(tester);
  return tester.container().read(routerProvider);
}

/// Opens search from Today, as its icon does. The icons themselves belong
/// to Today's header (WP-5) and Agenda's app bar (WP-7), which place a
/// [SearchEntryButton]; the button is tested on its own below.
Future<void> _openSearch(WidgetTester tester) async {
  unawaited(tester.container().read(routerProvider).push('/search'));
  await _settle(tester);
  expect(find.byType(SearchScreen), findsOneWidget);
}

/// A bare page with a [SearchEntryButton] in its app bar, `/search` behind
/// it, served by [api]; its router.
Future<GoRouter> _pumpEntry(WidgetTester tester, FakeApi api) async {
  SharedPreferences.setMockInitialValues({'locale': 'tr'});
  final shared = await SharedPreferences.getInstance();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          appBar: AppBar(actions: const [SearchEntryButton()]),
        ),
      ),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(shared),
        sessionProvider.overrideWith(_Session.new),
        dioProvider.overrideWithValue(api.dio),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        supportedLocales: AppL10n.supportedLocales,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    ),
  );
  await _settle(tester);
  return router;
}

Finder get _field => find.descendant(
  of: find.byType(SearchScreen),
  matching: find.byType(TextField),
);

/// Types [text] and lets the debounce run out and the answer land.
Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump(searchDebounce);
  await _settle(tester);
}

int _searches(FakeApi api) => api.gets.where((p) => p == '/search').length;

/// The contract's example (§13.1): one or two rows of every type.
Map<String, dynamic> _kahve() => searchJson(
  'kahve',
  results: [
    searchResultJson(
      type: 'transaction',
      id: 316,
      title: 'Kahve',
      subtitle: '3 Eki 2026 · Cüzdan · −₺85,00',
    ),
    searchResultJson(
      type: 'transaction',
      id: 2548,
      title: 'Market',
      subtitle: '1 Eki 2026 · Cüzdan · −₺412,50',
    ),
    searchResultJson(
      type: 'todo',
      id: 39,
      title: 'Kahve filtresi al',
      subtitle: 'Bekliyor · Son gün 5 Eki 2026',
    ),
    searchResultJson(
      type: 'event',
      id: 12,
      title: 'Kahve buluşması',
      subtitle: '6 Eki 2026 15:00 · Moda',
    ),
    searchResultJson(
      type: 'journal_entry',
      id: 20,
      title: 'Sabah kahvesi balkonda',
      subtitle: '3 Eki 2026',
    ),
    searchResultJson(
      type: 'goal',
      id: 3,
      title: 'KAHVE bütçesi',
      subtitle: '33% tamamlandı',
    ),
    searchResultJson(
      type: 'habit',
      id: 7,
      title: 'Kahve yok',
      subtitle: 'Günlük',
    ),
    searchResultJson(
      type: 'subscription',
      id: 6,
      title: 'Kahve kulübü',
      subtitle: 'Aylık · ₺149,90 · Sonraki 15 Eki 2026',
    ),
  ],
);

void main() {
  testWidgets('the way in opens /search with the keyboard', (tester) async {
    final router = await _pumpEntry(tester, FakeApi());
    expect(find.byType(SearchEntryButton), findsOneWidget);
    await tester.tap(find.byTooltip('Ara'));
    await _settle(tester);
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(router.state.uri.path, '/search');
    final field = tester.widget<TextField>(_field);
    expect(field.autofocus, isTrue);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.text('Ara: işlem, görev, günlük…'), findsOneWidget);
    // Nothing searched yet: what search covers.
    expect(find.text('Her yerde ara'), findsOneWidget);
  });

  testWidgets('the app routes /search to the search page', (tester) async {
    final router = await _pumpApp(tester, FakeApi());
    await _openSearch(tester);
    expect(router.state.uri.path, '/search');
    expect(find.text('Her yerde ara'), findsOneWidget);
  });

  testWidgets('typing is searched 250 ms after it pauses, never under two '
      'characters', (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api);
    await _openSearch(tester);
    api.clearLog();

    await tester.enterText(_field, 'K');
    await tester.pump(const Duration(seconds: 1));
    expect(_searches(api), 0, reason: 'one character is never sent');
    await tester.enterText(_field, '  K ');
    await tester.pump(const Duration(seconds: 1));
    expect(_searches(api), 0, reason: 'surrounding spaces do not count');

    await tester.enterText(_field, 'Ka');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(_field, 'Kah');
    await tester.pump(const Duration(milliseconds: 200));
    expect(_searches(api), 0, reason: 'still typing');
    await tester.pump(const Duration(milliseconds: 60));
    await _settle(tester);
    expect(_searches(api), 1, reason: 'one search, for the paused text');
    expect(api.requests.last, 'GET /search');
    expect(find.text('Kahve'), findsWidgets);

    // A space at the end is the same query: nothing new is asked.
    await tester.enterText(_field, 'Kah ');
    await tester.pump(const Duration(seconds: 1));
    expect(_searches(api), 1);
  });

  testWidgets('results come grouped by type, in the contract order, with '
      "the server's subtitles and the typed text picked out", (tester) async {
    final api = FakeApi()..on('GET /search', _kahve());
    await _pumpApp(tester, api);
    await _openSearch(tester);
    await _search(tester, 'kahve');

    const headings = [
      'İşlemler',
      'Görevler',
      'Etkinlikler',
      'Günlük',
      'Hedefler',
      'Alışkanlıklar',
      'Abonelikler',
    ];
    final tops = <double>[];
    for (final heading in headings) {
      // Headings only: "Günlük" is also the habit's subtitle.
      final found = find.descendant(
        of: find.byType(DayHeader),
        matching: find.text(heading),
      );
      await tester.scrollUntilVisible(
        found,
        200,
        scrollable: find
            .descendant(
              of: find.byType(SearchScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(found, findsOneWidget, reason: heading);
    }
    // In order: each heading is laid out below the previous one.
    final scroll = find
        .descendant(
          of: find.byType(SearchScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(scroll, const Offset(0, 3000));
    await _settle(tester);
    for (final heading in headings.take(3)) {
      tops.add(
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(DayHeader),
                matching: find.text(heading),
              ),
            )
            .dy,
      );
    }
    expect(tops, orderedEquals([...tops]..sort()));

    expect(find.text('3 Eki 2026 · Cüzdan · −₺85,00'), findsOneWidget);
    expect(find.text('Bekliyor · Son gün 5 Eki 2026'), findsOneWidget);

    // "kahve" in gold w600 inside "Sabah kahvesi balkonda" — and in
    // "KAHVE bütçesi", any case.
    final c = tester.element(find.byType(SearchScreen)).nok;
    List<TextSpan> goldIn(String plain) {
      final text = tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == plain,
        ),
      );
      final spans = <TextSpan>[];
      text.text.visitChildren((span) {
        if (span is TextSpan &&
            span.style?.color == c.gold &&
            span.style?.fontWeight == FontWeight.w600) {
          spans.add(span);
        }
        return true;
      });
      return spans;
    }

    expect(goldIn('Sabah kahvesi balkonda').map((s) => s.text), ['kahve']);
    expect(goldIn('Market'), isEmpty, reason: 'matched on its note');
    await tester.drag(scroll, const Offset(0, -3000));
    await _settle(tester);
    expect(goldIn('KAHVE bütçesi').map((s) => s.text), ['KAHVE']);
  });

  testWidgets('each type opens its own surface', (tester) async {
    final api = FakeApi()..on('GET /search', _kahve());
    final router = await _pumpApp(tester, api);
    await _openSearch(tester);
    await _search(tester, 'kahve');
    final scroll = find
        .descendant(
          of: find.byType(SearchScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<void> open(String title) async {
      final row = find.descendant(
        of: find.byType(SearchResultRow),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == title,
        ),
      );
      await tester.scrollUntilVisible(row, 150, scrollable: scroll);
      api.clearLog();
      await tester.tap(row);
      await _settle(tester);
    }

    Future<void> close() async {
      await tester.binding.handlePopRoute();
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(SearchScreen).hitTestable(), findsOneWidget);
    }

    await open('Kahve');
    expect(api.gets, contains('/transactions/316'));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Düzenle'), findsWidgets);
    await close();
    expect(
      api.gets,
      contains('/search'),
      reason: 'searched again once it closed',
    );

    await open('Kahve filtresi al');
    expect(api.gets, contains('/todos/39'));
    expect(find.byType(TodoSheet), findsOneWidget);
    await close();

    await open('Kahve buluşması');
    expect(api.gets, contains('/events/12'));
    expect(find.byType(BottomSheet), findsOneWidget);
    await close();

    await open('Sabah kahvesi balkonda');
    expect(find.byType(JournalDetailScreen), findsOneWidget);
    expect(router.state.uri.path, '/journal/20');
    await close();

    await open('KAHVE bütçesi');
    expect(find.byType(GoalDetailScreen), findsOneWidget);
    expect(router.state.uri.path, '/goals/3');
    await close();

    await open('Kahve yok');
    expect(api.gets, contains('/habits/7'));
    expect(find.byType(BottomSheet), findsOneWidget);
    await close();

    await open('Kahve kulübü');
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(api.gets, contains('/subscriptions'));
    await close();
  });

  testWidgets('a record deleted since the search drops out', (tester) async {
    final api = FakeApi()
      ..on('GET /search', _kahve())
      ..fail('GET /todos/39', 404);
    await _pumpApp(tester, api);
    await _openSearch(tester);
    await _search(tester, 'kahve');
    final row = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == 'Kahve filtresi al',
    );
    expect(row, findsOneWidget);
    await tester.tap(row);
    await _settle(tester);
    expect(find.byType(TodoSheet), findsNothing);
    expect(row, findsNothing);
    expect(
      find.text('Bu kayıt silinmiş; sonuçlardan çıkarıldı'),
      findsOneWidget,
    );
  });

  testWidgets('the shown results stay until the next answer, and an answer '
      'for older text is dropped', (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api);
    await _openSearch(tester);
    await _search(tester, 'kitap');
    expect(find.byType(SearchResultRow), findsOneWidget);

    api.hold('GET /search');
    await tester.enterText(_field, 'yog');
    await tester.pump(searchDebounce);
    await _settle(tester);
    // On its way: Kitap is still shown.
    expect(find.byType(SearchResultRow), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == 'Kitap',
      ),
      findsOneWidget,
    );

    // Typed on before "yog" answered: that answer must not show.
    await tester.enterText(_field, 'netf');
    await tester.pump(searchDebounce);
    await _settle(tester);
    api.release('GET /search');
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == 'Yoga',
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == 'Netflix',
      ),
      findsOneWidget,
    );
  });

  testWidgets('nothing found says so with the query', (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api);
    await _openSearch(tester);
    await _search(tester, 'zzz');
    expect(find.text('“zzz” için sonuç yok'), findsOneWidget);
    expect(find.byType(SearchResultRow), findsNothing);
  });

  testWidgets('recent searches: kept when a result is opened, searched '
      'again on a tap, forgotten on a long press or ×', (tester) async {
    final api = FakeApi();
    await _pumpApp(
      tester,
      api,
      prefs: {
        recentSearchesKey: <String>['yoga', 'netflix'],
      },
    );
    await _openSearch(tester);
    expect(find.text('Son aramalar'), findsOneWidget);
    expect(find.text('yoga'), findsOneWidget);
    expect(find.text('netflix'), findsOneWidget);

    // A tap searches it at once (no debounce).
    api.clearLog();
    await tester.tap(find.text('netflix'));
    await tester.pump();
    await _settle(tester);
    expect(_searches(api), 1);
    expect(find.byType(SearchResultRow), findsOneWidget);

    // Opening a result keeps the words, first.
    await tester.tap(find.byType(SearchResultRow));
    await _settle(tester);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.tap(find.byTooltip('Temizle'));
    await _settle(tester);
    expect(find.text('Son aramalar'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(recentSearchesKey), ['netflix', 'yoga']);

    await tester.longPress(find.text('yoga'));
    await _settle(tester);
    expect(find.text('yoga'), findsNothing);
    expect(prefs.getStringList(recentSearchesKey), ['netflix']);

    // The long press is a screen-reader action too, and × a plain tap.
    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(
      find
          .ancestor(of: find.text('netflix'), matching: find.byType(InkWell))
          .first,
    );
    expect(customActionLabels(node), contains('Son aramalardan kaldır'));
    handle.dispose();
    await tester.tap(find.byTooltip('Son aramalardan kaldır'));
    await _settle(tester);
    expect(find.text('netflix'), findsNothing);
    expect(find.text('Her yerde ara'), findsOneWidget);
  });

  testWidgets('an unreachable server: the error view, and "Tekrar dene" '
      'searches again', (tester) async {
    final api = FakeApi()..failNetwork('GET /search');
    await _pumpApp(tester, api);
    await _openSearch(tester);
    await _search(tester, 'kitap');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sunucuya ulaşılamıyor'), findsOneWidget);
    expect(find.text('Sunucu ayarları'), findsOneWidget);

    api.on('GET /search', searchJson('kitap'));
    await tester.tap(find.text('Tekrar dene'));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sunucuya ulaşılamıyor'), findsNothing);
    expect(find.byType(SearchResultRow), findsOneWidget);
  });

  testWidgets('after a first search fails, the error stays up while a retry '
      'is on its way', (tester) async {
    final api = FakeApi()..failNetwork('GET /search');
    await _pumpApp(tester, api);
    await _openSearch(tester);
    await _search(tester, 'kitap');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sunucuya ulaşılamıyor'), findsOneWidget);

    api
      ..on('GET /search', searchJson('kitap'))
      ..hold('GET /search');
    await tester.tap(find.text('Tekrar dene'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Sunucuya ulaşılamıyor'), findsOneWidget);

    api.release('GET /search');
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Sunucuya ulaşılamıyor'), findsNothing);
    expect(find.byType(SearchResultRow), findsOneWidget);
  });

  testWidgets('after a first search fails, the error stays up while new '
      'text is on its way', (tester) async {
    final api = FakeApi()..fail('GET /search', 500);
    await _pumpApp(tester, api);
    await _openSearch(tester);
    await _search(tester, 'kitap');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Arama yapılamadı'), findsOneWidget);

    api
      ..on('GET /search', searchJson('kitapl'))
      ..hold('GET /search');
    await tester.enterText(_field, 'kitapl');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(searchDebounce);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Arama yapılamadı'), findsOneWidget);

    api.release('GET /search');
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Arama yapılamadı'), findsNothing);
  });

  testWidgets('a server error says so and offers a retry', (tester) async {
    final api = FakeApi()..fail('GET /search', 500);
    await _pumpApp(tester, api);
    await _openSearch(tester);
    await _search(tester, 'kitap');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Arama yapılamadı'), findsOneWidget);
    expect(find.text('Sunucu hatası (500)'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
  });

  testWidgets('a server without search (404): says so, and the ways in hide', (
    tester,
  ) async {
    final api = FakeApi()..fail('GET /search', 404);
    await _pumpApp(tester, api);
    await _openSearch(tester);
    await _search(tester, 'kitap');
    expect(find.text('Bu sunucuda arama yok'), findsOneWidget);
    expect(tester.container().read(searchOfferedProvider), isFalse);
  });

  testWidgets('the way in hides once the server has no search', (
    tester,
  ) async {
    final api = FakeApi()..fail('GET /search', 404);
    await _pumpEntry(tester, api);
    await tester.tap(find.byTooltip('Ara'));
    await _settle(tester);
    await _search(tester, 'kitap');
    expect(find.text('Bu sunucuda arama yok'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(SearchEntryButton), findsOneWidget);
    expect(find.byTooltip('Ara'), findsNothing);
  });

  test('a server without search is remembered by address, not for good',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer fresh() {
      final container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    final here = fresh();
    expect(here.read(searchOfferedProvider), isTrue);
    here
        .read(searchMissingOnProvider.notifier)
        .missing(here.read(serverUrlProvider));
    expect(here.read(searchOfferedProvider), isFalse);

    // Another server lacked it: the one the app points at still offers it.
    final elsewhere = fresh();
    elsewhere
        .read(searchMissingOnProvider.notifier)
        .missing('http://old-server.example:3000');
    expect(elsewhere.read(searchOfferedProvider), isTrue);
  });

  testWidgets('200 % text: results and recents lay out without overflow', (
    tester,
  ) async {
    final api = FakeApi()..on('GET /search', _kahve());
    await _pumpApp(
      tester,
      api,
      prefs: {
        recentSearchesKey: <String>['kahve filtresi ve süt'],
      },
      textScale: 2.0,
    );
    await _openSearch(tester);
    expect(tester.takeException(), isNull);
    await _search(tester, 'kahve');
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(SearchResultRow), findsWidgets);
    // Amounts come last in a transaction's subtitle: never cut (§8.3).
    final subtitle = find.text('1 Eki 2026 · Cüzdan · −₺412,50');
    await tester.ensureVisible(subtitle);
    await tester.pump();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: subtitle, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
  });
}
