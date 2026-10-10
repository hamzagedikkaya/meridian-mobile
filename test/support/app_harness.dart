import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/agenda/agenda_screen.dart';
import 'package:meridian_mobile/ui/screens/agenda/todo_lists_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api.dart';

/// The moment the fixtures are recorded at: Sunday 4 October 2026, 12:30 —
/// `/home`'s `today`.
final fixtureNow = DateTime(2026, 10, 4, 12, 30);

/// [home] at `/` in the app's theme and languages, with [api] behind the
/// real repository, DataSync and read models, the clock at [fixtureNow],
/// and the pages Today opens — the Agenda tab (`/agenda?view=…&list=…`),
/// `/agenda/lists`, and p24's `/todos` links redirected to them — as the
/// app routes them.
Future<GoRouter> pumpWithRoutes(
  WidgetTester tester,
  FakeApi api, {
  Widget? home,
  String initialLocation = '/',
  Locale locale = const Locale('tr'),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1290, 2796);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (_, _) => home ?? const SizedBox()),
      GoRoute(
        path: '/todos',
        redirect: (_, state) {
          final query = state.uri.queryParameters;
          final view = switch (query['filter']) {
            null || 'open' => 'open',
            'undated' => 'inbox',
            final String filter => filter,
          };
          return Uri(
            path: '/agenda',
            queryParameters: {'view': view, 'list': ?query['list']},
          ).toString();
        },
      ),
      GoRoute(path: '/todos/lists', redirect: (_, _) => '/agenda/lists'),
      GoRoute(
        path: '/agenda',
        builder: (_, state) => AgendaTabScreen(
          view: state.uri.queryParameters['view'],
          list: state.uri.queryParameters['list'],
        ),
      ),
      GoRoute(
        path: '/agenda/lists',
        builder: (_, _) => const TodoListsScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(api.dio),
        sharedPrefsProvider.overrideWithValue(prefs),
        currentUserProvider.overrideWithValue(null),
        clockProvider.overrideWithValue(() => fixtureNow),
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

/// Pumps until the fake API has answered and the screen has caught up,
/// without waiting for animations that never end.
Future<void> settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets an undo snackbar run out (6 s) and the delete it held go out.
Future<void> letUndoRunOut(WidgetTester tester) async {
  await settleFrames(tester);
  await tester.pump(const Duration(seconds: 7));
  await settleFrames(tester);
}

/// A button at `/` that runs [open] — a sheet or form under test.
Widget opener(void Function(BuildContext context) open) => Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
