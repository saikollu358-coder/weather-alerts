import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import 'fcm_service.dart';
import 'firebase_service.dart';
import 'firestore_service.dart';

/// Provider exposing the shared [FirebaseService].
///
/// `main()` calls `bootstrap()` on the resolved instance before running the app
/// so the runtime availability flag is known before any widget reads it.
final firebaseServiceProvider = Provider<FirebaseService>(
  (ref) => FirebaseService(
    config: ref.watch(appConfigProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Provider exposing the shared [FirestoreService].
final firestoreServiceProvider = Provider<FirestoreService>(
  (ref) => FirestoreService(
    firebase: ref.watch(firebaseServiceProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Provider exposing the shared [FcmService].
final fcmServiceProvider = Provider<FcmService>(
  (ref) => FcmService(
    firebase: ref.watch(firebaseServiceProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);