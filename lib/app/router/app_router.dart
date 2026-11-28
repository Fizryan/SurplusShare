import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/app/router/router_enum.dart';
import 'package:surplus_share/app/shell/app_shell.dart';
import 'package:surplus_share/core/auth/models/auth_state.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/permission/permission_policy.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/features/auth/presentation/screens/login_screen.dart';
import 'package:surplus_share/features/auth/presentation/screens/unauthorized_screen.dart';
import 'package:surplus_share/features/impact/presentation/screens/impact_profile_screen.dart';
import 'package:surplus_share/features/listing/presentation/screens/feed_screen.dart';
import 'package:surplus_share/features/location/presentation/screens/explore_screen.dart';
import 'package:surplus_share/features/reservation/presentation/screens/reservations_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();

  ref
    ..listen<AuthState>(
      authNotifierProvider,
      (_, _) => refreshNotifier.refresh(),
    )
    ..listen(currentPermissionProvider, (_, _) => refreshNotifier.refresh());

  final router = GoRouter(
    initialLocation: RouteEnum.login.path,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final permissions = ref.read(currentPermissionProvider);
      final targetRoute = _matchRoute(state.matchedLocation);

      if (authState is AuthInitial || authState is AuthLoading) {
        return null;
      }

      if (authState is AuthUnauthenticated) {
        if (targetRoute == null || targetRoute.requiredAuth) {
          return RouteEnum.login.path;
        }
        return null;
      }

      if (authState is AuthAuthenticated) {
        if (targetRoute == RouteEnum.login) {
          final canAccessFeed = PermissionPolicy.hasAll(
            permissions,
            RouteEnum.feed.requiredPermission,
          );
          return canAccessFeed
              ? RouteEnum.feed.path
              : RouteEnum.unauthorized.path;
        }

        if (targetRoute != null &&
            targetRoute.requiredPermission.isNotEmpty &&
            !PermissionPolicy.hasAll(
              permissions,
              targetRoute.requiredPermission,
            )) {
          return RouteEnum.unauthorized.path;
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: RouteEnum.login.path,
        name: RouteEnum.login.name,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteEnum.unauthorized.path,
        name: RouteEnum.unauthorized.name,
        builder: (context, state) => const UnauthorizedScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteEnum.feed.path,
                name: RouteEnum.feed.name,
                builder: (context, state) => const FeedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteEnum.explore.path,
                name: RouteEnum.explore.name,
                builder: (context, state) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteEnum.reservations.path,
                name: RouteEnum.reservations.name,
                builder: (context, state) => const ReservationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteEnum.impact.path,
                name: RouteEnum.impact.name,
                builder: (context, state) => const ImpactProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refreshNotifier.dispose();
  });

  return router;
});

RouteEnum? _matchRoute(String location) {
  for (final route in RouteEnum.values) {
    if (route.path == location) return route;
  }
  return null;
}

final class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
