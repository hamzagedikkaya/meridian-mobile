/// The shell and the route map (design-analysis §6.1, §6.2, §5.2; WP-4):
/// the five tabs, the fade-through between them, back on a tab root, the
/// Agenda badge, Goals as a pushed page, the redirects that keep old links
/// working, the shortcut queries, and sign-in coming back where it was.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/router/app_router.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/agenda/agenda_screen.dart';
import 'package:meridian_mobile/ui/screens/events/agenda_screen.dart'
    as events;
import 'package:meridian_mobile/ui/screens/finance/accounts_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_screen.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/goals/goals_screen.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_editor.dart';
import 'package:meridian_mobile/ui/screens/login_screen.dart';
import 'package:meridian_mobile/ui/screens/search/search_screen.dart';
import 'package:meridian_mobile/ui/screens/shell/app_scaffold.dart';
import 'package:meridian_mobile/ui/screens/shell/app_tabs.dart';
import 'package:meridian_mobile/ui/screens/shell/fade_through_branches.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';
import 'package:meridian_mobile/ui/screens/todos/todo_lists_screen.dart';
import 'package:meridian_mobile/ui/screens/todos/todos_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

/// A session the test moves along: signed in at first.
class _Session extends SessionController {
  @override
  SessionState build() => const SessionLoggedIn();

  void set(SessionState next) => state = next;
}

/// Lets the fake API answer and the screens settle (the tabs show
/// indeterminate progress while loading, so pumpAndSettle cannot be used).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The app as it runs, signed in, served by [api]; its router.
Future<GoRouter> _pumpApp(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'locale': 'tr'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sessionProvider.overrideWith(_Session.new),
      dioProvider.overrideWithValue(api.dio),
    ],
    child: const MeridianApp(),
  ));
  await _settle(tester);
  return tester.container().read(routerProvider);
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

/// A tab root that says which tab it is.
class _Probe extends StatelessWidget {
  final AppTab tab;
  const _Probe(this.tab);

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('probe ${tab.name}')));
}

/// The shell alone, with probe tabs: [reduceMotion] as the system's
/// "Remove animations" (or the app's switch) sets it.
Widget _probeShell({bool reduceMotion = false}) {
  final router = GoRouter(
    initialLocation: '/today',
    routes: [
      StatefulShellRoute(
        builder: (context, state, shell) => AppScaffold(shell: shell),
        navigatorContainerBuilder: (context, shell, children) =>
            FadeThroughBranches(
          currentIndex: shell.currentIndex,
          children: children,
        ),
        branches: [
          for (final tab in AppTab.values)
            StatefulShellBranch(routes: [
              GoRoute(
                path: tab.location,
                pageBuilder: (_, state) =>
                    NoTransitionPage(key: state.pageKey, child: _Probe(tab)),
              ),
            ]),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      homeProvider.overrideWithBuild((ref, _) =>
          Fetched(HomeSummary.fromJson(homeJson()), DateTime(2026, 10, 4))),
    ],
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
    ),
  );
}

/// How opaque [finder]'s widget is drawn: every fade above it multiplied.
double _opacity(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(of: finder, matching: find.byType(FadeTransition)))) {
    opacity *= fade.opacity.value;
  }
  return opacity;
}

/// Where [finder]'s tab is painted among the shell's tabs: the higher, the
/// nearer the top.
int _paintOrder(WidgetTester tester, Finder finder) {
  final stack = tester.renderObject<RenderStack>(find
      .descendant(
          of: find.byType(FadeThroughBranches), matching: find.byType(Stack))
      .first);
  RenderObject? node = tester.renderObject(finder);
  while (node != null && node.parent != stack) {
    node = node.parent;
  }
  return stack.getChildrenAsList().indexOf(node! as RenderBox);
}

/// Mocks the platform channel; the calls to [method] made from here on.
List<MethodCall> _platformCalls(WidgetTester tester, String method) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == method) calls.add(call);
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

void main() {
  setUpAll(initializeDateFormatting);

  group('the bar', () {
    testWidgets('five tabs: Bugün · Ajanda · Finans · Alışkanlık · Günlük',
        (tester) async {
      await tester.pumpWidget(_probeShell());
      await tester.pumpAndSettle();
      final labels = [
        for (final d in tester.widgetList<NavigationDestination>(
            find.byType(NavigationDestination)))
          d.label,
      ];
      expect(labels, ['Bugün', 'Ajanda', 'Finans', 'Alışkanlık', 'Günlük']);
      expect(find.text('Hedefler'), findsNothing, reason: 'a page, no tab');
    });

    testWidgets('the tabs fade through: at 150 ms both are on stage, half '
        'way; at 300 ms only the new one', (tester) async {
      await tester.pumpWidget(_probeShell());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finans'));
      await tester.pump(); // the switch: the fade starts…
      await tester.pump(); // …ticking from this frame on
      await tester.pump(const Duration(milliseconds: 45));
      final today = find.text('probe today');
      final finance = find.text('probe finance');
      expect(today, findsOneWidget);
      expect(finance, findsOneWidget);
      // The old tab fades out over the first 90 ms…
      expect(_opacity(tester, today), inExclusiveRange(0, 1));
      expect(_opacity(tester, finance), 0);

      await tester.pump(const Duration(milliseconds: 105));
      expect(today, findsOneWidget, reason: 'still on stage at 150 ms');
      expect(finance, findsOneWidget);
      expect(_opacity(tester, today), lessThan(1));
      // …and the new one fades in over the remaining 210 ms.
      expect(_opacity(tester, finance), inExclusiveRange(0, 1));

      await tester.pump(const Duration(milliseconds: 150));
      expect(_opacity(tester, finance), 1);
      await tester.pump(const Duration(milliseconds: 16)); // the next frame
      expect(today, findsNothing, reason: 'offstage once it is over');
      expect(finance, findsOneWidget);
      expect(_opacity(tester, finance), 1);
    });

    testWidgets('back to a tab on the left fades through the same way: the '
        'new tab is drawn over the old one, never under its fill',
        (tester) async {
      await tester.pumpWidget(_probeShell());
      await tester.pumpAndSettle();
      final todayNavigator = tester.state<NavigatorState>(find
          .ancestor(
              of: find.text('probe today'), matching: find.byType(Navigator))
          .first);
      await tester.tap(find.text('Finans'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bugün'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final today = find.text('probe today');
      final finance = find.text('probe finance');
      expect(today, findsOneWidget);
      expect(finance, findsOneWidget);
      expect(_opacity(tester, today), inExclusiveRange(0, 1));
      expect(_opacity(tester, finance), lessThan(1));
      expect(_paintOrder(tester, today),
          greaterThan(_paintOrder(tester, finance)),
          reason: 'the old tab fills its area with c.bg: drawn over the new '
              'one, it would hide it until the switch is over');

      await tester.pumpAndSettle();
      expect(finance, findsNothing);
      expect(_opacity(tester, today), 1);
      expect(
          tester.state<NavigatorState>(find
              .ancestor(of: today, matching: find.byType(Navigator))
              .first),
          same(todayNavigator),
          reason: 'moving in the stack never remounts a branch');
    });

    testWidgets('only the selected tab takes taps while the old one fades',
        (tester) async {
      await tester.pumpWidget(_probeShell());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finans'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final ignoring = tester
          .widgetList<IgnorePointer>(find.ancestor(
              of: find.text('probe today'),
              matching: find.byType(IgnorePointer)))
          .any((w) => w.ignoring);
      expect(ignoring, isTrue);
    });

    testWidgets('under reduced motion the switch takes one frame',
        (tester) async {
      await tester.pumpWidget(_probeShell(reduceMotion: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finans'));
      await tester.pump();
      expect(find.text('probe today'), findsNothing);
      expect(find.text('probe finance'), findsOneWidget);
      expect(_opacity(tester, find.text('probe finance')), 1);
    });

    testWidgets('a tab tap is silent: no haptic (D38)', (tester) async {
      final haptics = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method.startsWith('HapticFeedback')) haptics.add(call);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(_probeShell());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finans'));
      await tester.pumpAndSettle();
      expect(haptics, isEmpty);
    });
  });

  group('back on a tab root', () {
    testWidgets('on Finans goes to Today; on Today leaves the app',
        (tester) async {
      final exits = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') exits.add(call);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final router = await _pumpApp(tester, FakeApi());

      await tester.tap(find.text('Finans'));
      await _settle(tester);
      expect(find.byType(FinanceScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_location(router), '/today');
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(exits, isEmpty);

      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(exits, hasLength(1), reason: 'back on Today leaves the app');
    });

    testWidgets('the tabs make way for a pushed page with the theme\'s push '
        '(FadeForwards): out to the left, fading', (tester) async {
      final router = await _pumpApp(tester, FakeApi());
      await tester.tap(find.text('Finans'));
      await _settle(tester);
      router.push('/finance/accounts');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final bar = find.byType(NavigationBar);
      expect(_opacity(tester, bar), lessThan(1));
      final slides = tester.widgetList<SlideTransition>(
          find.ancestor(of: bar, matching: find.byType(SlideTransition)));
      expect(slides.any((s) => s.position.value.dx < 0), isTrue,
          reason: 'sliding out to the left');
      await _settle(tester);
    });

    testWidgets('a page pushed over a tab closes first', (tester) async {
      final router = await _pumpApp(tester, FakeApi());
      await tester.tap(find.text('Finans'));
      await _settle(tester);
      router.push('/finance/accounts');
      await _settle(tester);
      expect(find.byType(AccountsScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(AccountsScreen), findsNothing);
      expect(_location(router), '/finance');
    });
  });

  testWidgets('the overdue badge is on Agenda, in onError on error, and '
      'read with the tab', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpApp(tester, FakeApi());
    final badge = find.byType(Badge);
    expect(badge, findsOneWidget);
    final destination = tester.widget<NavigationDestination>(find.ancestor(
        of: badge, matching: find.byType(NavigationDestination)));
    expect(destination.label, 'Ajanda');

    final c = tester.element(badge).nok;
    final label = tester.widget<RichText>(find.descendant(
        of: badge,
        matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == '1')));
    expect(label.text.style?.color, c.onError);
    // What the badge paints: its own colour, else the theme's.
    expect(
        tester.widget<Badge>(badge).backgroundColor ??
            BadgeTheme.of(tester.element(badge)).backgroundColor,
        c.error);

    final node = tester.getSemantics(find.ancestor(
        of: badge, matching: find.byType(NavigationDestination)));
    expect(node.label, startsWith('Ajanda'));
    expect(node.value, '1 gecikmiş görev');
    handle.dispose();
  });

  group('the route map', () {
    testWidgets('Goals is a page with a back arrow; a goal deep link opens '
        'with its ring', (tester) async {
      final router = await _pumpApp(tester, FakeApi());
      router.push('/goals');
      await _settle(tester);
      expect(find.byType(GoalsScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byType(NavigationBar).hitTestable(), findsNothing);

      router.go('/goals/3');
      await _settle(tester);
      expect(find.byType(GoalDetailScreen), findsOneWidget);
      expect(
          find.byWidgetPredicate((w) => w is Hero && w.tag == 'goal-ring-3'),
          findsOneWidget);
    });

    testWidgets('Goals or Search opened on their own (a link, back after '
        'signing in): back goes to Today, never out of the app',
        (tester) async {
      final exits = _platformCalls(tester, 'SystemNavigator.pop');
      final router = await _pumpApp(tester, FakeApi());
      router.go('/goals/3');
      await _settle(tester);
      expect(find.byType(GoalDetailScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_location(router), '/goals');
      expect(find.byType(GoalsScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget,
          reason: 'its back arrow, though nothing is under it');

      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(_location(router), '/today');
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(exits, isEmpty);

      router.go('/search');
      await _settle(tester);
      expect(find.byType(SearchScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_location(router), '/today');
      expect(exits, isEmpty);
    });

    testWidgets('pushed over the tabs, Goals goes back to the tab it came '
        'from', (tester) async {
      final router = await _pumpApp(tester, FakeApi());
      await tester.tap(find.text('Alışkanlık'));
      await _settle(tester);
      router.push('/goals');
      await _settle(tester);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_location(router), '/habits');
    });

    testWidgets('a goal pushed with its preview has its ring in the first '
        'frame, before /goals/:id answers', (tester) async {
      final api = FakeApi()..hold('GET /goals/3');
      final router = await _pumpApp(tester, api);
      router.push('/goals/3', extra: Goal.fromJson(goalJson()));
      for (var i = 0;
          i < 3 && find.byType(GoalDetailScreen).evaluate().isEmpty;
          i++) {
        await tester.pump();
      }
      expect(
          find.byWidgetPredicate((w) => w is Hero && w.tag == 'goal-ring-3'),
          findsOneWidget);
      api.release('GET /goals/3');
      await _settle(tester);
    });

    testWidgets('/todos links land on the Agenda tab with their filter and '
        'list', (tester) async {
      final api = FakeApi();
      final queries = <Map<String, String>>[];
      api.onRequest('GET /todos', (request) {
        queries.add(request.uri.queryParameters);
        return {
          'todos': <Object>[],
          'meta': const {'counts': <String, int>{}},
        };
      });
      final router = await _pumpApp(tester, api);
      router.go('/todos?filter=undated&list=5');
      await _settle(tester);
      expect(find.byType(AgendaTabScreen), findsOneWidget);
      expect(_location(router), '/agenda', reason: 'the query was used up');
      expect(queries.last['filter'], 'undated');
      expect(queries.last['list_id'], '5');

      router.go('/todos/lists');
      await _settle(tester);
      expect(find.byType(TodoListsScreen), findsOneWidget);
      expect(_location(router), '/agenda/lists');
    });

    testWidgets('a todo link opens the open todos, whatever the Agenda tab '
        'showed last', (tester) async {
      final router = await _pumpApp(tester, FakeApi());
      Finder tab(String label) => find.descendant(
          of: find.byType(NavigationBar), matching: find.text(label));
      await tester.tap(tab('Ajanda'));
      await _settle(tester);
      await tester.tap(find.text('Etkinlikler'));
      await _settle(tester);
      expect(find.byType(events.AgendaScreen), findsOneWidget);
      await tester.tap(tab('Bugün'));
      await _settle(tester);

      router.go('/todos');
      await _settle(tester);
      expect(find.byType(TodosScreen), findsOneWidget);
      expect(find.byType(events.AgendaScreen), findsNothing);
      expect(
          tester.widget<TodosScreen>(find.byType(TodosScreen)).initialFilter,
          'open');
    });

    testWidgets('the old archived-accounts page opens Accounts with the '
        'archive open', (tester) async {
      final router = await _pumpApp(tester, FakeApi());
      await tester.tap(find.text('Finans'));
      await _settle(tester);
      // As Finance's menu opens it: pushed over the tab.
      router.push('/finance/accounts/archived');
      await _settle(tester);
      expect(find.byType(AccountsScreen), findsOneWidget);
      expect(
          tester.widget<AccountsScreen>(find.byType(AccountsScreen))
              .showArchived,
          isTrue);

      // And as a link opens it.
      router.go('/finance/accounts/archived');
      await _settle(tester);
      expect(_location(router), '/finance/accounts?archived=1');
      expect(
          tester.widget<AccountsScreen>(find.byType(AccountsScreen))
              .showArchived,
          isTrue);
    });

    testWidgets('a shortcut query opens its surface once, then leaves the '
        'location', (tester) async {
      final router = await _pumpApp(tester, FakeApi());
      router.go('/journal?new=1');
      await _settle(tester);
      expect(find.byType(JournalEditorScreen), findsOneWidget);
      expect(_location(router), '/journal');
    });
  });

  group('signing in again', () {
    testWidgets('after the session ran out: back where it was',
        (tester) async {
      final router = await _pumpApp(tester, FakeApi());
      router.go('/finance/transactions');
      await _settle(tester);
      final session = tester.container().read(sessionProvider.notifier)
          as _Session;

      session.set(const SessionLoggedOut(expired: true));
      await _settle(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
          _location(router), '/login?from=%2Ffinance%2Ftransactions');

      session.set(const SessionLoggedIn());
      await _settle(tester);
      expect(_location(router), '/finance/transactions');
    });

    testWidgets('after signing out: Today, whatever was open', (tester) async {
      final router = await _pumpApp(tester, FakeApi());
      router.go('/finance/transactions');
      await _settle(tester);
      final session = tester.container().read(sessionProvider.notifier)
          as _Session;

      session.set(const SessionLoggedOut());
      await _settle(tester);
      expect(_location(router), '/login');

      session.set(const SessionLoggedIn());
      await _settle(tester);
      expect(_location(router), '/today');
    });
  });
}
