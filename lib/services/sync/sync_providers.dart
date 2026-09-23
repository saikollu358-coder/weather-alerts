import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import '../../data/repositories/local_repository_providers.dart';
import '../../features/authentication/application/auth_providers.dart';
import '../firebase/firebase_providers.dart';
import 'cloud_sync_bootstrap.dart';
import 'cloud_sync_service.dart';

/// Phase 14 cloud-sync orchestrator reconciling local SQLite data with the
/// user's Firestore sub-collections.
final cloudSyncServiceProvider = Provider<CloudSyncService>(
  (ref) => CloudSyncService(
    store: ref.watch(firestoreServiceProvider),
    auth: ref.watch(authServiceProvider),
    locations: ref.watch(monitoredLocationRepositoryProvider),
    preferences: ref.watch(preferenceRepositoryProvider),
    alerts: ref.watch(alertHistoryRepositoryProvider),
    syncState: ref.watch(syncStateRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Startup wiring that listens for auth changes and drives the periodic resync.
final cloudSyncBootstrapProvider = Provider<CloudSyncBootstrap>(
  (ref) => CloudSyncBootstrap(
    sync: ref.watch(cloudSyncServiceProvider),
    auth: ref.watch(authServiceProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);