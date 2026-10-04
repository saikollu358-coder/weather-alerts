import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import '../../domain/repositories/alert_history_repository.dart';
import '../../domain/repositories/current_location_repository.dart';
import '../../domain/repositories/notification_state_repository.dart';
import '../../domain/repositories/preference_repository.dart';
import '../../domain/repositories/weather_cache_repository.dart';
import '../datasources/local/local_database.dart';
import '../datasources/local/local_database_factory.dart';
import 'alert_history_repository_impl.dart';
import 'current_location_repository_impl.dart';
import 'notification_state_repository_impl.dart';
import 'preference_repository_impl.dart';

import 'weather_cache_repository_impl.dart';

/// The platform-appopriate local SQLite database (sqflite-backed on native,
/// gracefully unavailable on web).
final localDatabaseProvider = Provider<LocalDatabase>(
  (ref) => createPlatformLocalDatabase(),
);

/// Local weather/forecast cache repository.
final weatherCacheRepositoryProvider = Provider<WeatherCacheRepository>(
  (ref) => WeatherCacheRepositoryImpl(
    db: ref.watch(localDatabaseProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Local alert history repository.
final alertHistoryRepositoryProvider = Provider<AlertHistoryRepository>(
  (ref) => AlertHistoryRepositoryImpl(
    db: ref.watch(localDatabaseProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Local user preferences repository.
final preferenceRepositoryProvider = Provider<PreferenceRepository>(
  (ref) => PreferenceRepositoryImpl(
    db: ref.watch(localDatabaseProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Last-known device position, used by background work that cannot resolve GPS.
final currentLocationRepositoryProvider = Provider<CurrentLocationRepository>(
  (ref) => CurrentLocationRepositoryImpl(
    preferences: ref.watch(preferenceRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Local notification-state repository.
final notificationStateRepositoryProvider = Provider<NotificationStateRepository>(
  (ref) => NotificationStateRepositoryImpl(
    db: ref.watch(localDatabaseProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);