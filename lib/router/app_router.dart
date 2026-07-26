import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session.dart';
import '../ui/screens/aliskanliklar/aliskanliklar_screen.dart';
import '../ui/screens/bugun/bugun_screen.dart';
import '../ui/screens/gunluk/gunluk_detail_screen.dart';
import '../ui/screens/gunluk/gunluk_screen.dart';
import '../ui/screens/hedefler/hedef_detail_screen.dart';
import '../ui/screens/hedefler/hedefler_screen.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/para/hesap_detail_screen.dart';
import '../ui/screens/para/islemler_screen.dart';
import '../ui/screens/para/para_screen.dart';
import '../ui/screens/profil/profil_screen.dart';
import '../ui/screens/profil/sunucu_screen.dart';
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
        return loc == '/giris' ? null : '/giris';
      }
      if (loc == '/splash' || loc == '/giris') return '/bugun';
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
        path: '/giris',
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
        path: '/profil',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ProfilScreen(),
      ),
      GoRoute(
        path: '/profil/sunucu',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SunucuScreen(),
      ),
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootKey,
        builder: (context, state, shell) => AppScaffold(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellKey,
            routes: [
              GoRoute(
                path: '/bugun',
                pageBuilder: (_, state) => _fadeThrough(const BugunScreen(), state),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/para',
                pageBuilder: (_, state) => _fadeThrough(const ParaScreen(), state),
                routes: [
                  GoRoute(
                    path: 'islemler',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const IslemlerScreen(),
                  ),
                  GoRoute(
                    path: 'hesap/:id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => HesapDetailScreen(
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
                path: '/aliskanliklar',
                pageBuilder: (_, state) =>
                    _fadeThrough(const AliskanliklarScreen(), state),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/hedefler',
                pageBuilder: (_, state) =>
                    _fadeThrough(const HedeflerScreen(), state),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => HedefDetailScreen(
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
                path: '/gunluk',
                pageBuilder: (_, state) =>
                    _fadeThrough(const GunlukScreen(), state),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => GunlukDetailScreen(
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
