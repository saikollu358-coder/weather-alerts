import 'dart:async';

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
///
/// Unlike a cloud session, the local guest is NOT activated automatically on
/// launch: the app first shows a "local mode" gate so a missing cloud
/// connection is never silently hidden and the login page is not skipped for a
/// build that cannot sign in. [startLocalGuest] opts into the guest identity;
/// until then [currentUser] is null and [watchAuthState] emits no signed-in
/// user.
class LocalAuthService implements AuthService {
  LocalAuthService();

  static const AuthUser guest = AuthUser(
    uid: 'local-guest',
    name: 'Local profile',
    email: null,
    createdAt: null,
    isLocalGuest: true,
  );

  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();
  bool _guestActive = false;

  /// Opts into the local (offline-first) guest session.
  ///
  /// Emits [guest] to [watchAuthState] listeners so the app can proceed to the
  /// dashboard. Called by the local-mode gate screen.
  void startLocalGuest() {
    if (_guestActive) return;
    _guestActive = true;
    _controller.add(guest);
  }

  @override
  bool get isAvailable => false;

  @override
  AuthUser? get currentUser => _guestActive ? guest : null;

  @override
  Stream<AuthUser?> watchAuthState() async* {
    yield currentUser;
    yield* _controller.stream;
  }

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