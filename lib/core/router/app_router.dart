import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/diario/diario_screen.dart';
import '../../features/practica/practica_screen.dart';
import '../../features/ranking/ranking_screen.dart';
import '../../features/perfil/perfil_screen.dart';
import '../../features/practica/solving_screen.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/auth/tutorial_screen.dart';
import '../../features/legal/terms_screen.dart';
import '../../features/legal/privacy_screen.dart';
import '../../features/pro/pro_dashboard_screen.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/providers/guest_provider.dart';
import 'scaffold_with_nav_bar.dart';

// Keys for StatefulShellRoute to persist state
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorDiarioKey = GlobalKey<NavigatorState>(
  debugLabel: 'shellDiario',
);
final _shellNavigatorPracticaKey = GlobalKey<NavigatorState>(
  debugLabel: 'shellPractica',
);
final _shellNavigatorRankingKey = GlobalKey<NavigatorState>(
  debugLabel: 'shellRanking',
);
final _shellNavigatorPerfilKey = GlobalKey<NavigatorState>(
  debugLabel: 'shellPerfil',
);

final goRouterProvider = Provider<GoRouter>((ref) {
  final currentUser = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/welcome',
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isLoggedIn = currentUser != null;
      final isGuest = ref.read(guestModeProvider);

      final atWelcome = state.matchedLocation == '/welcome';
      final atLogin = state.matchedLocation == '/login';
      final isGoingToLegal =
          state.matchedLocation == '/terms' ||
          state.matchedLocation == '/privacy';

      // If not logged in and not a guest, forced to go to welcome (except legal)
      if (!isLoggedIn &&
          !isGuest &&
          !atWelcome &&
          !atLogin &&
          !isGoingToLegal) {
        return '/welcome';
      }

      // If logged in and at welcome/login, go to home
      if (isLoggedIn && (atWelcome || atLogin)) {
        return '/diario';
      }

      // If guest and at welcome, go to home.
      // BUT Allow guest to visit /login to register.
      if (isGuest && atWelcome) {
        return '/diario';
      }

      return null;
    },
    routes: [
      // Onboarding / Welcome
      GoRoute(
        path: '/welcome',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const WelcomeScreen(),
      ),
      // Tutorial Interactivo
      GoRoute(
        path: '/tutorial',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const TutorialScreen(),
      ),
      // Ruta de Login (fuera del Shell/NavBar)
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AuthScreen(),
      ),
      // Ruta de Resolución (fuera del Shell para ser pantalla completa)
      GoRoute(
        path: '/solving',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extras = state.extra as Map<String, dynamic>;
          return SolvingScreen(
            technology: extras['technology'] as String,
            level: extras['level'] as String,
            challengeId:
                extras['id']
                    as String?, // Nuevo: soporte para retos específicos
          );
        },
      ),
      GoRoute(
        path: '/terms',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const TermsScreen(),
      ),
      GoRoute(
        path: '/privacy',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: '/pro-analytics',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProDashboardScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          // Branch Diario
          StatefulShellBranch(
            navigatorKey: _shellNavigatorDiarioKey,
            routes: [
              GoRoute(
                path: '/diario',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: DiarioScreen()),
              ),
            ],
          ),
          // Branch Practica
          StatefulShellBranch(
            navigatorKey: _shellNavigatorPracticaKey,
            routes: [
              GoRoute(
                path: '/practica',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: PracticaScreen()),
              ),
            ],
          ),
          // Branch Ranking
          StatefulShellBranch(
            navigatorKey: _shellNavigatorRankingKey,
            routes: [
              GoRoute(
                path: '/ranking',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: RankingScreen()),
              ),
            ],
          ),
          // Branch Perfil
          StatefulShellBranch(
            navigatorKey: _shellNavigatorPerfilKey,
            routes: [
              GoRoute(
                path: '/perfil',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: PerfilScreen()),
                routes: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
