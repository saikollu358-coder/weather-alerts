import '../../../domain/entities/auth_user.dart';

/// High-level authentication phases.
enum AuthStatus {
  /// Startup; still resolving whether a session exists.
  unknown,

  /// Waiting for a sign-in / registration to complete.
  authenticating,

  /// Signed in with an identity available.
  authenticated,

  /// No signed-in user (signed out or never signed in).
  unauthenticated,

  /// The auth stream failed (transient); [AuthState.errorMessage] is set.
  error,
}

/// Immutable authentication state consumed by widgets and route guards.
class AuthState {
  const AuthState._({
    required this.status,
    this.user,
    this.errorMessage,
  });

  const AuthState.unknown() : this._(status: AuthStatus.unknown);

  const AuthState.authenticating(AuthUser? user)
      : this._(status: AuthStatus.authenticating, user: user);

  const AuthState.authenticated(AuthUser user)
      : this._(status: AuthStatus.authenticated, user: user);

  const AuthState.unauthenticated({String? errorMessage})
      : this._(status: AuthStatus.unauthenticated, errorMessage: errorMessage);

  const AuthState.error(String errorMessage)
      : this._(status: AuthStatus.error, errorMessage: errorMessage);

  final AuthStatus status;

  /// Signed-in user when [status] is authenticated.
  final AuthUser? user;

  /// User-safe message for the most recent auth failure.
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  bool get isLoading =>
      status == AuthStatus.unknown || status == AuthStatus.authenticating;

  /// Whether a cloud account is in use (false for the local/offline session).
  bool get usesCloudAccount =>
      isAuthenticated && user != null && !user!.isLocalGuest;

  @override
  String toString() => 'AuthState($status)';
}