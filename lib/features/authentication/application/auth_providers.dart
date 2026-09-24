import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/repositories/auth_repository_impl.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../domain/services/auth_service.dart';
import '../../../services/firebase/auth_service.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../../services/firebase/local_auth_service.dart';
import 'auth_controller.dart';
import 'auth_state.dart';

/// Shared instance of the offline/local auth backend.
///
/// Kept as a singleton so the [LocalModeScreen] gate can opt the user into the
/// guest session through the exact service the [authControllerProvider] listens
/// to.
final localAuthServiceProvider = Provider<LocalAuthService>(
  (ref) => LocalAuthService(),
);

/// Selects the auth backend: Firebase when configured, otherwise a
/// deterministic local/offline session.
final authServiceProvider = Provider<AuthService>((ref) {
  final firebase = ref.watch(firebaseServiceProvider);
  if (firebase.isAvailable) {
    return FirebaseAuthService(
      firebase: firebase,
      logger: ref.watch(appLoggerProvider),
    );
  }
  return ref.watch(localAuthServiceProvider);
});

/// Whether a cloud (Firebase) sign-in backend is available in this build.
///
/// The router uses this to decide between the login flow (cloud available) and
/// the local-mode gate (cloud unavailable), so a build without Firebase never
/// silently skips the login page.
final cloudAuthAvailableProvider = Provider<bool>(
  (ref) => ref.watch(authServiceProvider).isAvailable,
);

/// Data-layer boundary between the controller UI and the auth backend.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    authService: ref.watch(authServiceProvider),
    firestore: ref.watch(firestoreServiceProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// The single authentication state provider for the application.
final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);