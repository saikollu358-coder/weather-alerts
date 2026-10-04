import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import '../../data/repositories/device_token_firestore_repository.dart';
import '../../data/repositories/local_repository_providers.dart';
import '../../domain/repositories/device_token_repository.dart';
import '../../features/authentication/application/auth_providers.dart';
import '../firebase/device_token_service.dart';
import '../firebase/firebase_providers.dart';

/// Firestore-backed device token repository (Phase 12).
final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>(
  (ref) => DeviceTokenFirestoreRepository(
    firestore: ref.watch(firestoreServiceProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// The device token service that manages FCM token lifecycle.
final deviceTokenServiceProvider = Provider<DeviceTokenService>(
  (ref) => DeviceTokenService(
    fcm: ref.watch(fcmServiceProvider),
    auth: ref.watch(authServiceProvider),
    deviceTokens: ref.watch(deviceTokenRepositoryProvider),
    currentLocation: ref.watch(currentLocationRepositoryProvider),
    preferences: ref.watch(preferenceRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);
