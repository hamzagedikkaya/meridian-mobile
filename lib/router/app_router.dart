import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session.dart';
import '../ui/screens/habits/habits_screen.dart';
import '../ui/screens/today/today_screen.dart';
import '../ui/screens/journal/journal_detail_screen.dart';
import '../ui/screens/journal/journal_screen.dart';
import '../ui/screens/goals/goal_detail_screen.dart';
import '../ui/screens/goals/goals_screen.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/finance/account_detail_screen.dart';
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
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootKey,
        builder: (context, state, shell) => AppScaffold(shell: shell),
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
                  GoRoute(
                    path: 'transactions',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const TransactionsScreen(),
                  ),
                  GoRoute(
                    path: 'account/:id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => AccountDetailScreen(
                      accountId: int.parse(state.pathParameters['id']!),
                    ),
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
