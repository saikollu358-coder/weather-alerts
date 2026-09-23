import '../../core/errors/app_exception.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/services/auth_service.dart';

/// Deterministic offline/local-only session, used when Firebase is not
/// configured.
///
/// The device still gets a stable local identity so the full weather /
/// alerts / settings experience remains usable, clearly marked as a local
/// (non-account) session. Sign-in/registration are not possible: they require
/// cloud configuration and fail with a friendly [FirebaseUnavailableException].
class LocalAuthService implements AuthService {
  LocalAuthService();

  static const AuthUser guest = AuthUser(
    uid: 'local-guest',
    name: 'Local profile',
    email: null,
    createdAt: null,
    isLocalGuest: true,
  );

  @override
  bool get isAvailable => false;

  @override
  AuthUser? get currentUser => guest;

  @override
  Stream<AuthUser?> watchAuthState() => Stream.value(guest);

  @override
  Future<AuthUser> register({
    required String username,
    required String email,
    required String password,
  }) {
    throw _cloudRequired();
  }

  @override
  Future<AuthUser> login({required String email, required String password}) {
    throw _cloudRequired();
  }

  @override
  Future<AuthUser> updateProfile({required String name}) {
    throw _cloudRequired();
  }

  @override
  Future<void> sendPasswordReset({required String email}) {
    throw _cloudRequired();
  }

  @override
  Future<void> logout() async {
    // Local sessions cannot be signed out of; the guest identity is reused.
  }

  Object _cloudRequired() {
    throw const FirebaseUnavailableException.withMessage(
      'Cloud sign-in requires Firebase configuration. '
      'This build is running in local mode.',
    );
  }
}
