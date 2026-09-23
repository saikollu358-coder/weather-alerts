import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import 'auth_state.dart';
import 'auth_providers.dart';

/// Owns the application authentication state and actions.
///
/// Widgets never call Firebase directly; they invoke [login], [register],
/// [logout] and [resetPassword], all of which funnel through the
/// [authRepositoryProvider]. The signed-in stream is subscribed once here and
/// drives both the UI and the router redirect.
class AuthController extends Notifier<AuthState> {
  StreamSubscription<dynamic>? _subscription;

  @override
  AuthState build() {
    final repository = ref.watch(authRepositoryProvider);
    final logger = ref.watch(appLoggerProvider);

    ref.onDispose(() => _subscription?.cancel());

    _subscription = repository.watchAuthState().listen(
      (user) {
        // While a sign-in is completing, ignore the transient null the
        // provider emits *before* the success event, so that event wins.
        if (state.status == AuthStatus.authenticating && user == null) {
          return;
        }
        state = user != null
            ? AuthState.authenticated(user)
            : const AuthState.unauthenticated();
      },
      onError: (Object e, StackTrace st) {
        final message = _friendlyMessage(e, logger);
        logger.warning(
          'AuthController',
          'auth stream failed: ${e.runtimeType}',
        );
        state = AuthState.unauthenticated(errorMessage: message);
      },
    );

    return const AuthState.unknown();
  }

  /// Signs in; returns true on success so the form can avoid double submits.
  Future<bool> login({required String email, required String password}) async {
    final logger = ref.read(appLoggerProvider);
    state = AuthState.authenticating(state.user);
    try {
      await ref
          .read(authRepositoryProvider)
          .login(email: email, password: password);
      return true;
    } catch (e) {
      state = AuthState.unauthenticated(
        errorMessage: _friendlyMessage(e, logger),
      );
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final logger = ref.read(appLoggerProvider);
    state = AuthState.authenticating(state.user);
    try {
      await ref
          .read(authRepositoryProvider)
          .register(username: username, email: email, password: password);
      return true;
    } catch (e) {
      state = AuthState.unauthenticated(
        errorMessage: _friendlyMessage(e, logger),
      );
      return false;
    }
  }

  Future<void> logout() async {
    final logger = ref.read(appLoggerProvider);
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (e) {
      state = AuthState.unauthenticated(
        errorMessage: _friendlyMessage(e, logger),
      );
    }
  }

  /// Updates the signed-in profile and keeps the session authenticated.
  ///
  /// Returns the user-safe error message on failure (null on success). The
  /// session stays signed in — unlike login/register, an edit failure must not
  /// drop the user to the sign-in screen.
  Future<String?> updateProfile({required String name}) async {
    final logger = ref.read(appLoggerProvider);
    final current = state.user;
    if (current == null) {
      state = const AuthState.unauthenticated(
        errorMessage: 'No account is signed in.',
      );
      return 'No account is signed in.';
    }
    try {
      final updated = await ref
          .read(authRepositoryProvider)
          .updateProfile(name: name);
      state = AuthState.authenticated(updated);
      return null;
    } catch (e) {
      state = AuthState.authenticated(current);
      final message = _friendlyMessage(e, logger);
      logger.warning(
        'AuthController',
        'profile update failed: ${e.runtimeType}',
      );
      return message;
    }
  }

  Future<bool> resetPassword({required String email}) async {
    final logger = ref.read(appLoggerProvider);
    try {
      await ref.read(authRepositoryProvider).resetPassword(email: email);
      return true;
    } catch (e) {
      state = AuthState.unauthenticated(
        errorMessage: _friendlyMessage(e, logger),
      );
      return false;
    }
  }

  /// Clears the last auth error message (e.g. after dismissing a banner).
  void clearError() {
    state = state.status == AuthStatus.authenticated
        ? state
        : AuthState.unauthenticated(errorMessage: null);
  }

  String _friendlyMessage(Object error, AppLogger logger) {
    if (error is AppException) return error.message;
    logger.warning(
      'AuthController',
      'unexpected auth error: ${error.runtimeType}',
    );
    return 'An unexpected problem occurred. Please try again.';
  }
}
