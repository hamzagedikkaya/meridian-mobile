import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session.dart';
import '../ui/screens/habits/archived_habits_screen.dart';
import '../ui/screens/habits/habits_screen.dart';
import '../ui/screens/today/today_screen.dart';
import '../ui/screens/todos/todo_lists_screen.dart';
import '../ui/screens/todos/todos_screen.dart';
import '../ui/screens/events/agenda_screen.dart';
import '../ui/screens/journal/journal_detail_screen.dart';
import '../ui/screens/journal/journal_screen.dart';
import '../ui/screens/goals/goal_detail_screen.dart';
import '../ui/screens/goals/goals_screen.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/finance/account_detail_screen.dart';
import '../ui/screens/finance/archived_accounts_screen.dart';
import '../ui/screens/finance/categories_screen.dart';
import '../ui/screens/finance/finance_utils.dart';
import '../ui/screens/finance/subscriptions_screen.dart';
import '../ui/screens/finance/transactions_screen.dart';
import '../ui/screens/finance/finance_screen.dart';
import '../ui/screens/profile/profile_screen.dart';
import '../ui/screens/profile/server_screen.dart';
import '../ui/screens/shell/app_scaffold.dart';
import '../ui/screens/splash_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// Bumps go_router's refreshListenable whenever the session changes.
class _SessionRefresh extends ChangeNotifier {
  _SessionRefresh(Ref ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
  }
}

/// Section-5 FadeThrough page. Defaults to the 300ms tab↔tab feel; callers
/// override [duration]/[reverseDuration] for the auth-flow transitions.
CustomTransitionPage<void> _fadeThrough(
  Widget child,
  GoRouterState state, {
  Duration duration = const Duration(milliseconds: 300),
  Duration? reverseDuration,
}) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: reverseDuration ?? duration,
    transitionsBuilder: (context, animation, secondary, child) =>
        FadeThroughTransition(
      animation: animation,
      secondaryAnimation: secondary,
      child: child,
    ),
  );
}

/// The tabs' navigators, as `StatefulShellRoute.indexedStack` lays them out —
/// the selected one shown, every visited one kept alive offstage with its
/// tickers off — and with the hidden ones' heroes switched off as well.
///
/// A route pushed over the shell (a goal, an entry, an account) looks for
/// heroes in every tab that is still mounted. Two tabs' FABs share the
/// default hero tag, which fails outright, and a goal's ring on a hidden
/// Goals tab would fly into the goal opened from Today out of a screen the
/// user cannot see.
Widget _tabStack(
  BuildContext context,
  StatefulNavigationShell shell,
  List<Widget> children,
) =>
    IndexedStack(
      index: shell.currentIndex,
      children: [
        for (var i = 0; i < children.length; i++)
          Offstage(
            offstage: i != shell.currentIndex,
            child: TickerMode(
              enabled: i == shell.currentIndex,
              child: HeroMode(
                enabled: i == shell.currentIndex,
                child: children[i],
              ),
            ),
          ),
      ],
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionRefresh(ref);

  return GoRouter(
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
        return loc == '/login' ? null : '/login';
      }
      if (loc == '/splash' || loc == '/login') return '/today';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, state) => _fadeThrough(
          const SplashScreen(),
          state,
          duration: const Duration(milliseconds: 350),
        ),
      ),
      GoRoute(
        path: '/login',
        // 350ms in (Splash → Giriş); its 400ms reverse animation is the exit
        // that plays on login success, giving the Login → Bugün 400ms feel.
        pageBuilder: (_, state) => _fadeThrough(
          const LoginScreen(),
          state,
          duration: const Duration(milliseconds: 350),
          reverseDuration: const Duration(milliseconds: 400),
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
      // Every todo by filter and list (`?filter=today`, `?list=3`,
      // `?list=none`), pushed from Today.
      GoRoute(
        path: '/todos',
        parentNavigatorKey: _rootKey,
        builder: (_, state) {
          final query = state.uri.queryParameters;
          final list = query['list'];
          return TodosScreen(
            initialFilter: query['filter'] ?? 'open',
            initialListId: list == null ? null : int.tryParse(list),
            initialUnlisted: list == 'none',
          );
        },
      ),
      GoRoute(
        path: '/todos/lists',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const TodoListsScreen(),
      ),
      // The days ahead with their events, pushed from Today.
      GoRoute(
        path: '/agenda',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const AgendaScreen(),
      ),
      StatefulShellRoute(
        parentNavigatorKey: _rootKey,
        builder: (context, state, shell) => AppScaffold(shell: shell),
        navigatorContainerBuilder: _tabStack,
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellKey,
            routes: [
              GoRoute(
                path: '/today',
                pageBuilder: (_, state) => _fadeThrough(const TodayScreen(), state),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/finance',
                pageBuilder: (_, state) => _fadeThrough(const FinanceScreen(), state),
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
                    builder: (_, state) => AccountDetailScreen(
                      accountId: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                  GoRoute(
                    path: 'accounts/archived',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const ArchivedAccountsScreen(),
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
                    _fadeThrough(const HabitsScreen(), state),
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
                path: '/goals',
                pageBuilder: (_, state) =>
                    _fadeThrough(const GoalsScreen(), state),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => GoalDetailScreen(
                      goalId: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/journal',
                pageBuilder: (_, state) =>
                    _fadeThrough(const JournalScreen(), state),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => JournalDetailScreen(
                      entryId: int.parse(state.pathParameters['id']!),
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
