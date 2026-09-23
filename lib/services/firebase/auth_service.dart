import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/services/auth_service.dart';
import 'auth_error_mapper.dart';
import 'firebase_availability.dart';

/// [AuthService] backed by Firebase Authentication.
///
/// All operations are guarded by [FirebaseAvailability]; in a local-only build
/// every sign-in request fails with [FirebaseUnavailableException] instead of
/// touching the plugin.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({required this.firebase, required this.logger});

  final FirebaseAvailability firebase;
  final AppLogger logger;

  FirebaseAuth get _auth {
    _requireAvailable();
    return FirebaseAuth.instance;
  }

  void _requireAvailable() {
    if (!firebase.isAvailable) {
      throw const FirebaseUnavailableException();
    }
  }

  @override
  bool get isAvailable => firebase.isAvailable;

  @override
  AuthUser? get currentUser {
    if (!firebase.isAvailable) return null;
    return _toAuthUser(FirebaseAuth.instance.currentUser);
  }

  @override
  Stream<AuthUser?> watchAuthState() {
    if (!firebase.isAvailable) return const Stream.empty();
    return FirebaseAuth.instance.authStateChanges().map(_toAuthUser);
  }

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _userOrThrow(credential.user);
    } on FirebaseAuthException catch (e) {
      throw AuthErrorMapper.map(e);
    } on AppException {
      rethrow;
    } on Exception catch (e) {
      logger.warning('AuthService', 'login failed: ${e.runtimeType}');
      throw const FirebaseUnavailableException.withMessage(
        'Sign-in is not available right now. Please try again.',
      );
    }
  }

  @override
  Future<AuthUser> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await credential.user?.updateDisplayName(username.trim());
      return _userOrThrow(credential.user);
    } on FirebaseAuthException catch (e) {
      throw AuthErrorMapper.map(e);
    } on AppException {
      rethrow;
    } on Exception catch (e) {
      logger.warning('AuthService', 'register failed: ${e.runtimeType}');
      throw const FirebaseUnavailableException.withMessage(
        'Registration is not available right now. Please try again.',
      );
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw AuthErrorMapper.map(e);
    } on Exception catch (e) {
      logger.warning('AuthService', 'logout failed: ${e.runtimeType}');
      throw const FirebaseUnavailableException.withMessage(
        'Sign-out failed. Try again.',
      );
    }
  }

  @override
  Future<AuthUser> updateProfile({required String name}) async {
    final auth = _auth;
    try {
      final user = auth.currentUser;
      if (user == null) {
        throw const FirebaseUnavailableException.withMessage(
          'No signed-in session. Please sign in again.',
        );
      }
      await user.updateDisplayName(name.trim());
      await user.reload();
      return _userOrThrow(auth.currentUser);
    } on FirebaseAuthException catch (e) {
      throw AuthErrorMapper.map(e);
    } on AppException {
      rethrow;
    } on Exception catch (e) {
      logger.warning('AuthService', 'profile update failed: ${e.runtimeType}');
      throw const FirebaseUnavailableException.withMessage(
        'Could not update your profile. Please try again.',
      );
    }
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    final auth = _auth;
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthErrorMapper.map(e);
    } on Exception catch (e) {
      logger.warning('AuthService', 'reset failed: ${e.runtimeType}');
      throw const FirebaseUnavailableException.withMessage(
        'Could not send the reset email. Please try again.',
      );
    }
  }

  AuthUser _userOrThrow(User? user) {
    final mapped = _toAuthUser(user);
    if (mapped == null) {
      throw const FirebaseUnavailableException.withMessage(
        'Account created but the session could not be started. Please sign in.',
      );
    }
    return mapped;
  }

  AuthUser? _toAuthUser(User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      name: user.displayName,
      email: user.email,
      createdAt: user.metadata.creationTime,
    );
  }
}
