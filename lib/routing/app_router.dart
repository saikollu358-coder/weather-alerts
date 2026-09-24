import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/authentication/application/auth_providers.dart';
import '../features/authentication/application/auth_state.dart';
import '../features/authentication/presentation/screens/forgot_password_screen.dart';
import '../features/authentication/presentation/screens/local_mode_screen.dart';
import '../features/authentication/presentation/screens/login_screen.dart';
import '../features/authentication/presentation/screens/register_screen.dart';
import '../features/dashboard/presentation/dashboard_shell.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/splash/presentation/splash_screen.dart';
import 'app_routes.dart';

/// Application navigator with authentication-based route protection.
class AppRouter {
  AppRouter._();

  static GoRouter create(Ref ref) {
    // GoRouter re-evaluates redirects whenever auth state changes.
    final refreshNotifier = ValueNotifier<int>(0);
    ref.listen(authControllerProvider, (_, _) {
      refreshNotifier.value++;
    });

    return GoRouter(
      initialLocation: RoutePath.splash,
      refreshListenable: refreshNotifier,
      routes: [
        GoRoute(
          path: RoutePath.splash,
          name: RouteName.splash,
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: RoutePath.localMode,
          name: RouteName.localMode,
          builder: (context, state) => const LocalModeScreen(),
        ),
        GoRoute(
          path: RoutePath.login,
          name: RouteName.login,
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: RoutePath.register,
          name: RouteName.register,
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: RoutePath.forgotPassword,
          name: RouteName.forgotPassword,
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: RoutePath.home,
          name: RouteName.home,
          builder: (context, state) => const DashboardShell(),
        ),
        GoRoute(
          path: RoutePath.profile,
          name: RouteName.profile,
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: RoutePath.settings,
          name: RouteName.settings,
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
      redirect: (context, state) => _guard(ref, state),
    );
  }

  /// Route guard: keeps unauthenticated users away from protected screens and
  /// authenticated users away from login/register.
  static String? _guard(Ref ref, GoRouterState state) {
    final auth = ref.read(authControllerProvider);
    final location = state.matchedLocation;

    if (auth.isAuthenticated) {
      final onAuthScreen = _authScreens.contains(location) ||
          location == RoutePath.splash;
      if (onAuthScreen) return RoutePath.home;
      return null;
    }

    switch (auth.status) {
      case AuthStatus.unknown:
      case AuthStatus.authenticating:
        // Wait for the session to resolve on the splash screen.
        return null;
      case AuthStatus.unauthenticated:
      case AuthStatus.error:
        if (!ref.read(cloudAuthAvailableProvider)) {
          // No cloud backend in this build: sign-in/registration are unusable,
          // so park on the local-mode gate instead of a login page that could
          // never succeed.
          final onGate = _localModeScreens.contains(location);
          return onGate ? null : RoutePath.localMode;
        }
        final allowed = _publicScreens.contains(location);
        return allowed ? null : RoutePath.login;
      case AuthStatus.authenticated:
        return null; // handled above
    }
  }

  /// Screens reachable without authentication. Note: the splash path is NOT
  /// included — once auth resolves unused it must move on to login/home, so
  /// the guard redirects it away.
  static const Set<String> _publicScreens = {
    RoutePath.login,
    RoutePath.register,
    RoutePath.forgotPassword,
  };

  /// Screens reachable in a build without a cloud backend.
  ///
  /// The splash path is deliberately NOT included: like the cloud login flow,
  /// an unauthenticated local-only user must move off the splash screen onto
  /// the gate. (The splash screen itself is only shown while [AuthStatus]
  /// is still resolving.)
  static const Set<String> _localModeScreens = {
    RoutePath.localMode,
  };

  /// Screens an already-authenticated user must not see.
  static const Set<String> _authScreens = {
    RoutePath.localMode,
    RoutePath.login,
    RoutePath.register,
    RoutePath.forgotPassword,
  };
}

/// Provider exposing the application [GoRouter].
final appRouterProvider = Provider<GoRouter>(
  (ref) => AppRouter.create(ref),
);