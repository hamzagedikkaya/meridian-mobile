import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/home.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/shell/app_scaffold.dart';
import 'package:meridian_mobile/ui/screens/shell/app_tabs.dart';

import '../support/fake_api.dart';

/// A tab root that shows a long list, like the real tab screens: its list is
/// the tab's primary scroll view, and it keeps the tab's read model alive.
class _ProbeTab extends ConsumerStatefulWidget {
  final AppTab appTab;
  const _ProbeTab(this.appTab);

  @override
  ConsumerState<_ProbeTab> createState() => _ProbeTabState();
}

class _ProbeTabState extends ConsumerState<_ProbeTab>
    with TabRootScroll<_ProbeTab> {
  @override
  AppTab get tab => widget.appTab;

  @override
  Widget build(BuildContext context) {
    if (tab == AppTab.habits) ref.watch(habitsProvider);
    return primaryScroll(Scaffold(
      body: ListView.builder(
        primary: true,
        itemCount: 80,
        itemBuilder: (_, i) => SizedBox(height: 64, child: Text('${tab.name} $i')),
      ),
    ));
  }
}

class _Harness {
  var homeBuilds = 0;
  var habitsBuilds = 0;
  var now = DateTime(2026, 10, 4, 9);

  /// The shell with the real read models, served by [api].
  Widget live(FakeApi api) => _shell([
        clockProvider.overrideWithValue(() => now),
        dioProvider.overrideWithValue(api.dio),
      ]);

  Widget app() => _shell([
        clockProvider.overrideWithValue(() => now),
        homeProvider.overrideWithBuild((ref, _) {
          homeBuilds++;
          return Fetched(HomeSummary.fromJson(homeJson()), now);
        }),
        habitsProvider.overrideWithBuild((ref, _) {
          habitsBuilds++;
          return Fetched(HabitsBundle.fromJson(habitsJson()), now);
        }),
      ]);

  Widget _shell(List<Override> overrides) {
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppScaffold(shell: shell),
          branches: [
            for (final tab in AppTab.values)
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/${tab.name}',
                  builder: (_, _) => _ProbeTab(tab),
                ),
              ]),
          ],
        ),
      ],
    );
    return ProviderScope(
      overrides: overrides,
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
    );
  }
}

double _offset(WidgetTester tester, AppTab tab) => tester
    .state<_ProbeTabState>(
        find.byWidgetPredicate((w) => w is _ProbeTab && w.appTab == tab))
    .tabScroll
    .offset;

void _lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

const _toBackground = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];
const _toForeground = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

void main() {
  setUpAll(initializeDateFormatting);

  group('re-tapping the selected tab', () {
    testWidgets('Today: scrolls to the top and refetches', (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(h.homeBuilds, 1);

      await tester.drag(find.text('today 3'), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(_offset(tester, AppTab.today), greaterThan(0));

      await tester.tap(find.text('Bugün'));
      await tester.pumpAndSettle();
      expect(_offset(tester, AppTab.today), 0);
      expect(h.homeBuilds, 2);
    });

    testWidgets('another tab: refetches only what that tab shows',
        (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alışkanlık'));
      await tester.pumpAndSettle();
      expect(h.habitsBuilds, 1);

      await tester.drag(find.text('habits 3'), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(_offset(tester, AppTab.habits), greaterThan(0));

      final homeBefore = h.homeBuilds;
      await tester.tap(find.text('Alışkanlık'));
      await tester.pumpAndSettle();
      expect(_offset(tester, AppTab.habits), 0);
      expect(h.habitsBuilds, 2);
      expect(h.homeBuilds, homeBefore);
    });

    testWidgets('switching to another tab neither scrolls nor refetches',
        (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await tester.drag(find.text('today 3'), const Offset(0, -1200));
      await tester.pumpAndSettle();
      final offset = _offset(tester, AppTab.today);

      await tester.tap(find.text('Alışkanlık'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bugün'));
      await tester.pumpAndSettle();
      expect(_offset(tester, AppTab.today), offset);
      expect(h.homeBuilds, 1);
    });
  });

  group('switching back to Today, whose /home the tab bar keeps live for '
      'its badge (so Riverpod never sees it hidden and shown again)', () {
    Future<void> settleApi(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('after more than a minute: /home refetches (edits made on the '
        'web turn up)', (tester) async {
      final h = _Harness();
      final api = FakeApi();
      await tester.pumpWidget(h.live(api));
      await settleApi(tester);
      expect(api.gets, contains('/home'));

      await tester.tap(find.text('Alışkanlık'));
      await settleApi(tester);
      api.clearLog();

      h.now = h.now.add(const Duration(minutes: 2));
      await tester.tap(find.text('Bugün'));
      await settleApi(tester);
      expect(api.gets, ['/home']);
      expect(tester.container().read(homeProvider).value!.at, h.now);
    });

    testWidgets('within a minute: nothing refetches', (tester) async {
      final h = _Harness();
      final api = FakeApi();
      await tester.pumpWidget(h.live(api));
      await settleApi(tester);

      await tester.tap(find.text('Alışkanlık'));
      await settleApi(tester);
      api.clearLog();

      h.now = h.now.add(const Duration(seconds: 40));
      await tester.tap(find.text('Bugün'));
      await settleApi(tester);
      expect(api.gets, isEmpty);
    });

    testWidgets('switching to another tab leaves /home alone, however old',
        (tester) async {
      final h = _Harness();
      final api = FakeApi();
      await tester.pumpWidget(h.live(api));
      await settleApi(tester);
      api.clearLog();

      h.now = h.now.add(const Duration(minutes: 5));
      await tester.tap(find.text('Alışkanlık'));
      await settleApi(tester);
      expect(api.gets, ['/habits']);
    });
  });

  group('coming back to the app', () {
    testWidgets('after more than 30 s away: everything refetches',
        (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(h.homeBuilds, 1);

      _lifecycle(tester, _toBackground);
      h.now = h.now.add(const Duration(minutes: 5));
      _lifecycle(tester, _toForeground);
      await tester.pumpAndSettle();
      expect(h.homeBuilds, 2);
    });

    testWidgets('after a moment away (a dialog, the shade): nothing refetches',
        (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      _lifecycle(tester, _toBackground);
      h.now = h.now.add(const Duration(seconds: 10));
      _lifecycle(tester, _toForeground);
      await tester.pumpAndSettle();
      expect(h.homeBuilds, 1);
    });

    testWidgets('across midnight, even within seconds: the day rolls over',
        (tester) async {
      final h = _Harness()..now = DateTime(2026, 10, 4, 23, 59, 55);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final container = tester.container();
      expect(container.read(currentDayProvider), DateTime(2026, 10, 4));

      _lifecycle(tester, _toBackground);
      h.now = DateTime(2026, 10, 5, 0, 0, 2);
      _lifecycle(tester, _toForeground);
      await tester.pumpAndSettle();
      expect(container.read(currentDayProvider), DateTime(2026, 10, 5));
    });
  });
}
