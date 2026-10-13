import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session.dart';
import '../models/goal.dart';
import '../theme/app_motion.dart';
import '../ui/flows/flows.dart';
import '../ui/screens/agenda/agenda_screen.dart';
import '../ui/screens/habits/archived_habits_screen.dart';
import '../ui/screens/habits/habits_screen.dart';
import '../ui/screens/today/today_screen.dart';
import '../ui/screens/agenda/todo_lists_screen.dart';
import '../ui/screens/journal/journal_detail_screen.dart';
import '../ui/screens/journal/journal_editor.dart';
import '../ui/screens/journal/journal_screen.dart';
import '../ui/screens/goals/goal_detail_screen.dart';
import '../ui/screens/goals/goals_screen.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/finance/account_detail_screen.dart';
import '../ui/screens/finance/accounts_screen.dart';
import '../ui/screens/finance/categories_screen.dart';
import '../ui/screens/finance/finance_utils.dart';
import '../ui/screens/finance/subscriptions_screen.dart';
import '../ui/screens/finance/transactions_screen.dart';
import '../ui/screens/finance/finance_screen.dart';
import '../ui/screens/profile/profile_screen.dart';
import '../ui/screens/profile/server_screen.dart';
import '../ui/screens/search/search_screen.dart';
import '../ui/screens/shell/app_scaffold.dart';
import '../ui/screens/shell/back_to_today.dart';
import '../ui/screens/shell/fade_through_branches.dart';
import '../ui/screens/shell/launch_query.dart';
import '../ui/screens/splash_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// Bumps go_router's refreshListenable whenever the session changes.
class _SessionRefresh extends ChangeNotifier {
  _SessionRefresh(Ref ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
  }
}

/// A FadeThrough page (design-analysis §5.2) for the auth flow: [duration]
/// in, [reverseDuration] out. Under reduced
/// motion the page is simply there.
CustomTransitionPage<void> _fadeThrough(
  Widget child,
  GoRouterState state, {
  required Duration duration,
  Duration? reverseDuration,
}) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: reverseDuration ?? duration,
    transitionsBuilder: (context, animation, secondary, child) =>
        Motion.reduced(context)
            ? child
            : FadeThroughTransition(
                animation: animation,
                secondaryAnimation: secondary,
                child: child,
              ),
  );
}

/// The signed-in shell's page (§5.2). Its own entry — Splash/Login → Bugün
/// — and exit are a FadeThrough ([duration] in, [reverseDuration] out).
/// Under the pages pushed over it, it is a Material route like them, so it
/// leaves and comes back with the theme's push motion (FadeForwards,
/// predictive back) in step with them, as a [MaterialPage] would.
class _ShellPage extends Page<void> {
  final Widget child;
  final Duration duration;
  final Duration reverseDuration;

  const _ShellPage({
    super.key,
    required this.child,
    required this.duration,
    required this.reverseDuration,
  });

  @override
  Route<void> createRoute(BuildContext context) => _ShellRoute(this);
}

class _ShellRoute extends PageRoute<void>
    with MaterialRouteTransitionMixin<void> {
  _ShellRoute(_ShellPage page) : super(settings: page);

  _ShellPage get _page => settings as _ShellPage;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  Duration get transitionDuration => _page.duration;

  @override
  Duration get reverseTransitionDuration => _page.reverseDuration;

  @override
  bool get maintainState => true;

  @override
  bool get fullscreenDialog => false;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The theme moves the shell out from under a pushed page (and back);
    // its own entrance is not the theme's.
    final under = super.buildTransitions(
      context,
      kAlwaysCompleteAnimation,
      secondaryAnimation,
      child,
    );
    if (Motion.reduced(context)) return under;
    return FadeThroughTransition(
      animation: animation,
      secondaryAnimation: kAlwaysDismissedAnimation,
      child: under,
    );
  }
}

/// A tab's root page. The tab-to-tab fade is [FadeThroughBranches]'s; the
/// page itself never animates (the branch navigator only ever has it).
NoTransitionPage<void> _tabRoot(GoRouterState state, Widget child) =>
    NoTransitionPage(key: state.pageKey, child: child);

/// Where to go back to after signing in again: [from], when it is a place
/// in the app (never the sign-in flow itself, never another host).
String? _returnTo(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return null;
  }
  final uri = Uri.tryParse(from);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (uri.path == '/login' || uri.path == '/splash') return null;
  return from;
}

/// A record's id in the path; null when it is not one (a link from
/// outside the app), which goes to the record's list instead.
int? _idOf(GoRouterState state) {
  final id = int.tryParse(state.pathParameters['id'] ?? '');
  return id != null && id > 0 ? id : null;
}

/// The pages pushed over the tabs on the root navigator that can also be
/// the only page there: [BackToToday] gives them a way back to Today.
const _standAlonePages = {'/goals', '/search'};

/// Whether [page], opened with `go`, has a way back: a page under it (its
/// tab, or its parent route) or a [BackToToday] of its own. A root-level
/// page such as Profile or the server page alone has neither — no back
/// arrow, no tab bar, and the system back would close the app.
bool _standsAlone(RouteMatchList page) {
  final chain = page.matches;
  if (chain.isEmpty) return false;
  if (chain.first is ShellRouteMatch) return true;
  if (chain.whereType<RouteMatch>().length > 1) return true;
  return _standAlonePages.contains(page.fullPath);
}

/// The pages pushed with `push`, bottom to top, wherever their navigator.
Iterable<ImperativeRouteMatch> _pushed(List<RouteMatchBase> matches) sync* {
  for (final match in matches) {
    if (match is ImperativeRouteMatch) yield match;
    if (match is ShellRouteMatch) yield* _pushed(match.matches);
  }
}

/// Where the user is: the page on top of the stack. A page opened with
/// `push` (every detail and management page) is not in [state]'s location,
/// which stays the page it was pushed over; so while [state] is the
/// current location — the session changing under it — the top of the
/// router's stack says where the user was. A pushed page that cannot stand
/// on its own ([_standsAlone]) gives way to the one under it, down to
/// [state]'s location.
String _topLocation(GoRouter? router, GoRouterState state) {
  final config = router?.routerDelegate.currentConfiguration;
  if (config == null || config.isEmpty || config.uri != state.uri) {
    return state.uri.toString();
  }
  for (final page in _pushed(config.matches).toList().reversed) {
    if (_standsAlone(page.matches)) return page.matches.uri.toString();
  }
  return state.uri.toString();
}

/// p24's todo links (`/todos?filter=today&list=3`), on the Agenda tab: the
/// filter becomes its view (`undated` is the inbox; every open todo when
/// there is none), the list stays. Always with a view, so a mounted Agenda
/// tab lands on the todos asked for, not on what it showed last.
String _agendaForTodos(Map<String, String> query) {
  final filter = query['filter'];
  final view = switch (filter) {
    null || 'open' => 'open',
    'undated' => 'inbox',
    _ => filter,
  };
  return Uri(
    path: '/agenda',
    queryParameters: {'view': view, 'list': ?query['list']},
  ).toString();
}

/// The route map (design-analysis §6.2). Five tabs — Bugün, Ajanda,
/// Finans, Alışkanlık, Günlük — each a branch of the signed-in shell;
/// everything opened from them (details, management pages, Goals, Search)
/// is pushed over the shell on the root navigator. p24's `/todos` links
/// and the old archived-accounts page redirect to where they live now.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionRefresh(ref);
  GoRouter? router;

  return router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;

      if (session is SessionUnknown) {
        return loc == '/splash' ? null : '/splash';
      }
      if (session is SessionLoggedOut) {
        if (loc == '/login') return null;
        // A session that ran out (a 401) comes back to where it was once
        // signed in again (IA-23); signing out starts over on Today.
        if (session.expired && loc != '/splash') {
          return Uri(
            path: '/login',
            queryParameters: {'from': _topLocation(router, state)},
          ).toString();
        }
        return '/login';
      }
      if (loc == '/splash') return '/today';
      if (loc == '/login') {
        return _returnTo(state.uri.queryParameters['from']) ?? '/today';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, state) => _fadeThrough(
          const SplashScreen(),
          state,
          duration: Motion.sheetIn, // 350 ms
        ),
      ),
      GoRoute(
        path: '/login',
        // 350ms in (Splash → Giriş); its 400ms reverse animation is the exit
        // that plays on login success, under the shell's 350ms fade in.
        pageBuilder: (_, state) => _fadeThrough(
          const LoginScreen(),
          state,
          duration: Motion.sheetIn, // 350 ms
          reverseDuration: Motion.formIn, // 400 ms
        ),
      ),
      GoRoute(
        path: '/profile',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/profile/server',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ServerScreen(),
      ),
      // p24's todo screen and lists page now live on the Agenda tab.
      GoRoute(
        path: '/todos',
        redirect: (_, state) => _agendaForTodos(state.uri.queryParameters),
      ),
      GoRoute(
        path: '/todos/lists',
        redirect: (_, _) => '/agenda/lists',
      ),
      // Goals left the bar: a page pushed over the tabs, from Today's
      // goals and the Habits menu. Opened on its own (a deep link, the way
      // back after signing in), its back goes to Today.
      GoRoute(
        path: '/goals',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const BackToToday(child: GoalsScreen()),
        routes: [
          GoRoute(
            path: ':id',
            parentNavigatorKey: _rootKey,
            redirect: (_, state) => _idOf(state) == null ? '/goals' : null,
            // The goal tapped comes along (`extra`), so its ring — the
            // hero's landing spot — is there in the first frame.
            builder: (_, state) => GoalDetailScreen(
              goalId: _idOf(state)!,
              preview: state.extra is Goal ? state.extra as Goal : null,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => BackToToday(
          child: SearchScreen(query: state.uri.queryParameters['q'] ?? ''),
        ),
      ),
      StatefulShellRoute(
        parentNavigatorKey: _rootKey,
        // Splash/Login → Bugün: one 350/250 fade-through (§5.2).
        pageBuilder: (context, state, shell) => _ShellPage(
          key: state.pageKey,
          child: AppScaffold(shell: shell),
          duration: Motion.sheetIn, // 350 ms
          reverseDuration: Motion.sheetOut, // 250 ms
        ),
        navigatorContainerBuilder: (context, shell, children) =>
            FadeThroughBranches(
          currentIndex: shell.currentIndex,
          children: children,
        ),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellKey,
            routes: [
              GoRoute(
                path: '/today',
                // `?capture=1` (the "Hızlı ekle" shortcut) opens quick add.
                pageBuilder: (_, state) => _tabRoot(
                  state,
                  LaunchQuery(
                    path: '/today',
                    query: state.uri.queryParameters,
                    triggers: {
                      'capture': (context, value) {
                        if (value == '1') openQuickAdd(context);
                      },
                    },
                    child: const TodayScreen(),
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/agenda',
                // `?view=` and `?list=`: what the tab opens on.
                pageBuilder: (_, state) => _tabRoot(
                  state,
                  AgendaTabScreen(
                    view: state.uri.queryParameters['view'],
                    list: state.uri.queryParameters['list'],
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'lists',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const TodoListsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/finance',
                // `?new=tx` (the "İşlem ekle" shortcut) opens the form.
                pageBuilder: (_, state) => _tabRoot(
                  state,
                  LaunchQuery(
                    path: '/finance',
                    query: state.uri.queryParameters,
                    triggers: {
                      'new': (context, value) {
                        if (value == 'tx') openTransactionForm(context);
                      },
                    },
                    child: const FinanceScreen(),
                  ),
                ),
                routes: [
                  // Finance drills in with filters in the query (a
                  // category this month, the uncategorized spending).
                  GoRoute(
                    path: 'transactions',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => TransactionsScreen(
                      initial: filtersFromQuery(state.uri.queryParameters),
                    ),
                  ),
                  GoRoute(
                    path: 'account/:id',
                    parentNavigatorKey: _rootKey,
                    redirect: (_, state) =>
                        _idOf(state) == null ? '/finance/accounts' : null,
                    builder: (_, state) => AccountDetailScreen(
                      accountId: _idOf(state)!,
                    ),
                  ),
                  GoRoute(
                    path: 'accounts',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => AccountsScreen(
                      showArchived:
                          state.uri.queryParameters['archived'] == '1',
                    ),
                    routes: [
                      // The archive is a group of the accounts page now.
                      GoRoute(
                        path: 'archived',
                        redirect: (_, _) => '/finance/accounts?archived=1',
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'categories',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const CategoriesScreen(),
                  ),
                  GoRoute(
                    path: 'subscriptions',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const SubscriptionsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/habits',
                pageBuilder: (_, state) =>
                    _tabRoot(state, const HabitsScreen()),
                routes: [
                  GoRoute(
                    path: 'archived',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const ArchivedHabitsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/journal',
                // `?new=1` (the "Günlüğe yaz" shortcut) opens the editor.
                pageBuilder: (_, state) => _tabRoot(
                  state,
                  LaunchQuery(
                    path: '/journal',
                    query: state.uri.queryParameters,
                    triggers: {
                      'new': (context, value) {
                        if (value == '1') openJournalEditor(context);
                      },
                    },
                    child: const JournalScreen(),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootKey,
                    redirect: (_, state) =>
                        _idOf(state) == null ? '/journal' : null,
                    builder: (_, state) => JournalDetailScreen(
                      entryId: _idOf(state)!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
