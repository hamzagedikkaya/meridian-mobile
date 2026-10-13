import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meridian_mobile/core/formats.dart' show setAppToday;
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/finance/account_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/accounts_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/categories_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/finance_utils.dart';
import 'package:meridian_mobile/ui/screens/finance/subscriptions_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/transactions_screen.dart';

import 'app_harness.dart' show fixtureNow;
import 'fake_api.dart';

/// A tall phone: the test font draws every glyph a full em wide, so rows
/// need more room than they do in Inter.
void tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1290, 2796);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// [home] in the app's theme and languages, with [api] behind the real
/// repository, DataSync and read models, the clock at [now] ([fixtureNow]
/// unless given) — so a fixture's dates read the same on any run day —
/// and a router for the finance pages it opens (`/finance/...`). A
/// `clockProvider` override in [overrides] takes the place of [now].
Future<GoRouter> pumpFinance(
  WidgetTester tester,
  FakeApi api,
  Widget home, {
  Locale locale = const Locale('tr'),
  DateTime? now,
  List<Override> overrides = const [],
}) async {
  final clock = now ?? fixtureNow;
  // A test that brings its own clock (in [overrides]) keeps it, as before
  // [now] existed: the harness then sets no clock of its own.
  final ownClock = overrides.any((o) => identical(o.origin, clockProvider));
  if (!ownClock) {
    setAppToday(clock);
    addTearDown(() => setAppToday(null));
  }
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/finance/transactions',
        builder: (_, state) => TransactionsScreen(
          initial: filtersFromQuery(state.uri.queryParameters),
        ),
      ),
      GoRoute(
        path: '/finance/account/:id',
        builder: (_, state) => AccountDetailScreen(
          accountId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/finance/accounts',
        builder: (_, state) => AccountsScreen(
          showArchived: state.uri.queryParameters['archived'] == '1',
        ),
      ),
      GoRoute(
        path: '/finance/accounts/archived',
        redirect: (_, _) => '/finance/accounts?archived=1',
      ),
      GoRoute(
        path: '/finance/categories',
        builder: (_, _) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/finance/subscriptions',
        builder: (_, _) => const SubscriptionsScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(api.dio),
        if (!ownClock) clockProvider.overrideWithValue(() => clock),
        ...overrides,
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildTheme(Brightness.dark),
        locale: locale,
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
  await settleFrames(tester);
  return router;
}

/// Pumps until the fake API has answered and the screen has caught up —
/// without waiting for animations that never end (a "loading more" spinner).
Future<void> settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets an undo snackbar run out (6 s) and the delete it held go out. Its
/// timer starts once it has finished coming in, so that is waited for first.
Future<void> letUndoRunOut(WidgetTester tester) async {
  await settleFrames(tester);
  await tester.pump(const Duration(seconds: 7));
  await settleFrames(tester);
}
