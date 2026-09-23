import '../entities/auth_user.dart';

/// Contract for who the device user is.
///
/// Implementations: [FirebaseAuthService] when Firebase is configured, and
/// [LocalAuthService] for the deterministic offline/local-only session.
abstract interface class AuthService {
  /// False when no cloud sign-in backend exists in this build.
  bool get isAvailable;

  /// Currently signed-in user, or null.
  AuthUser? get currentUser;

  /// Emits the signed-in user whenever it changes (and null on sign-out).
  Stream<AuthUser?> watchAuthState();

  /// Registers a new email/password account.
  Future<AuthUser> register({
    required String username,
    required String email,
    required String password,
  });

  /// Signs in an existing account.
  Future<AuthUser> login({required String email, required String password});

  /// Signs the current user out.
  Future<void> logout();

  /// Updates the signed-in user's display name.
  Future<AuthUser> updateProfile({required String name});

  /// Sends a password-reset email.
  Future<void> sendPasswordReset({required String email});
}
