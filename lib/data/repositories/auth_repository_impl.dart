import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/services/auth_service.dart';
import '../../services/firebase/cloud_data_store.dart';
import '../../services/firebase/firestore_paths.dart';

/// Default [AuthRepository].
///
/// Delegates identity to an [AuthService] (Firebase or local) and enriches and
/// persists the signed-in user's minimal profile in Firestore when available.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required this.authService,
    required this.firestore,
    required this.logger,
  });

  final AuthService authService;
  final CloudDataStore firestore;
  final AppLogger logger;

  @override
  AuthUser? get currentUser => authService.currentUser;

  @override
  Stream<AuthUser?> watchAuthState() {
    return authService.watchAuthState().asyncMap((user) async {
      if (user == null) return null;
      try {
        return await _mergeProfile(user);
      } on AppException {
        logger.debug(
          'AuthRepository',
          'profile unavailable; using auth identity',
        );
        return user;
      }
    });
  }

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final user = await authService.login(email: email, password: password);
    return authService.isAvailable ? await _mergeProfile(user) : user;
  }

  @override
  Future<AuthUser> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final user = await authService.register(
      username: username,
      email: email,
      password: password,
    );
    // Minimal profile creation (the only user data we store server-side).
    if (authService.isAvailable) {
      try {
        await firestore.setDocument(
          ownerId: user.uid,
          collection: FirestorePaths.profileCollection,
          documentId: FirestorePaths.profileDocument,
          data: {
            'username': username.trim(),
            'email': email.trim(),
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          merge: true,
        );
      } on AppException catch (e) {
        logger.warning(
          'AuthRepository',
          'profile write failed: ${e.runtimeType}',
        );
      }
    }
    return user;
  }

  @override
  Future<void> logout() => authService.logout();

  @override
  Future<AuthUser> updateProfile({required String name}) async {
    final user = await authService.updateProfile(name: name);
    // Keep the stored profile in sync with the auth identity.
    if (authService.isAvailable) {
      try {
        await firestore.setDocument(
          ownerId: user.uid,
          collection: FirestorePaths.profileCollection,
          documentId: FirestorePaths.profileDocument,
          data: {
            'username': name.trim(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          merge: true,
        );
      } on AppException catch (e) {
        logger.warning(
          'AuthRepository',
          'profile write failed on update: ${e.runtimeType}',
        );
      }
    }
    return user;
  }

  @override
  Future<void> resetPassword({required String email}) =>
      authService.sendPasswordReset(email: email);

  /// Merges the Firestore profile username into the auth identity.
  Future<AuthUser> _mergeProfile(AuthUser user) async {
    final profile = await firestore.getDocument(
      ownerId: user.uid,
      collection: FirestorePaths.profileCollection,
      documentId: FirestorePaths.profileDocument,
    );
    if (profile == null) return user;
    final storedName = profile['username'] as String?;
    return AuthUser(
      uid: user.uid,
      name: (storedName?.isNotEmpty ?? false) ? storedName : user.name,
      email: (profile['email'] as String?) ?? user.email,
      createdAt: user.createdAt,
    );
  }
}
