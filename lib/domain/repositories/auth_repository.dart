import '../entities/auth_user.dart';

/// Repository boundary for authentication.
///
/// The UI layer depends on this interface (never directly on Firebase), so the
/// auth backend can be swapped without changing widgets or controllers.
abstract interface class AuthRepository {
  /// Currently authenticated user, or null.
  AuthUser? get currentUser;

  /// Stream of the current auth state.
  Stream<AuthUser?> watchAuthState();

  /// Signs in with email + password.
  Future<AuthUser> login({required String email, required String password});

  /// Registers a new account, creates the Firestore profile and signs in.
  Future<AuthUser> register({
    required String username,
    required String email,
    required String password,
  });

  /// Signs the current user out.
  Future<void> logout();

  /// Updates the signed-in user's profile (display name) and returns the
  /// refreshed identity.
  Future<AuthUser> updateProfile({required String name});

  /// Sends a password-reset email.
  Future<void> resetPassword({required String email});
}
