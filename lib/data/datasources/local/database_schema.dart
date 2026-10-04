import 'package:sqflite_common/sqlite_api.dart';

/// Column-name constants and DDL for the local SQLite database.
///
/// All timestamps are stored as UTC milliseconds since epoch (integer
/// columns). Kept as a self-contained schema so the platform adapter
/// (IO/web) stays thin and migrations are easy to test.
abstract final class LocalTables {
  LocalTables._();

  static const String cachedWeather = 'cached_weather';
  static const String cachedForecast = 'cached_forecast';
  static const String alertHistory = 'alert_history';
  static const String userPreferences = 'user_preferences';
  static const String notificationState = 'notification_state';

  /// Retired in schema v3. Kept only so the v2 -> v3 migration can drop it.
  static const String monitoredLocations = 'monitored_locations';

  /// Retired in schema v3. Kept only so the v2 -> v3 migration can drop it.
  static const String syncState = 'sync_state';
}

/// Table/column constants used by the SQL DDL and the data mappers.
abstract final class LocalColumns {
  LocalColumns._();

  // cached_weather / cached_forecast
  static const String locationKey = 'location_key';
  static const String payload = 'payload';
  static const String dataSource = 'data_source';
  static const String dataVersion = 'data_version';
  static const String fetchedAtUtc = 'fetched_at_utc';
  static const String expiresAtUtc = 'expires_at_utc';
  static const String forecastType = 'forecast_type';

  // alert_history
  static const String id = 'id';
  static const String fingerprint = 'fingerprint';
  static const String hazard = 'hazard';
  static const String severity = 'severity';
  static const String status = 'status';
  static const String title = 'title';
  static const String description = 'description';
  static const String reason = 'reason';
  static const String detectedAtUtc = 'detected_at_utc';
  static const String updatedAtUtc = 'updated_at_utc';
  static const String resolvedAtUtc = 'resolved_at_utc';
  static const String acknowledged = 'acknowledged';

  // monitored_locations
  static const String name = 'name';
  static const String latitude = 'latitude';
  static const String longitude = 'longitude';
  static const String accuracy = 'accuracy';
  static const String source = 'source';
  static const String isMonitored = 'is_monitored';
  static const String isPrimary = 'is_primary';
  static const String createdAtUtc = 'created_at_utc';
  static const String lastUsedAtUtc = 'last_used_at_utc';

  // user_preferences
  static const String prefKey = 'pref_key';
  static const String prefValue = 'pref_value';

  // notification_state
  static const String lastNotifiedAtUtc = 'last_notified_at_utc';
  static const String notificationCount = 'notification_count';

  // sync_state
  static const String syncKey = 'sync_key';
  static const String value = 'value';
  static const String lastAttemptUtc = 'last_attempt_utc';
  static const String lastSuccessUtc = 'last_success_utc';
}

/// Database DDL: current schema (v3) plus incremental migrations.
abstract final class DatabaseSchema {
  DatabaseSchema._();

  /// Current schema version exposed to sqflite.
  static const int schemaVersion = 3;

  /// Version that created the base tables (before v2 additions).
  static const int baseSchemaVersion = 1;

  // ---------------------------------------------------------------
  // v1 base tables
  // ---------------------------------------------------------------

  static const String createCachedWeather = '''
    CREATE TABLE ${LocalTables.cachedWeather} (
      location_key TEXT NOT NULL PRIMARY KEY,
      payload TEXT NOT NULL,
      data_source TEXT NOT NULL,
      data_version INTEGER NOT NULL DEFAULT 1,
      fetched_at_utc INTEGER NOT NULL,
      expires_at_utc INTEGER
    )
  ''';

  static const String createCachedForecast = '''
    CREATE TABLE ${LocalTables.cachedForecast} (
      location_key TEXT NOT NULL,
      forecast_type TEXT NOT NULL,
      payload TEXT NOT NULL,
      data_source TEXT NOT NULL,
      data_version INTEGER NOT NULL DEFAULT 1,
      fetched_at_utc INTEGER NOT NULL,
      expires_at_utc INTEGER,
      PRIMARY KEY (location_key, forecast_type)
    )
  ''';

  static const String createAlertHistory = '''
    CREATE TABLE ${LocalTables.alertHistory} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fingerprint TEXT NOT NULL UNIQUE,
      hazard TEXT NOT NULL,
      severity TEXT NOT NULL,
      status TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL,
      reason TEXT NOT NULL,
      payload TEXT NOT NULL DEFAULT '{}',
      location_key TEXT NOT NULL,
      detected_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL,
      resolved_at_utc INTEGER,
      expires_at_utc INTEGER,
      acknowledged INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const String createMonitoredLocations = '''
    CREATE TABLE ${LocalTables.monitoredLocations} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      accuracy REAL,
      source TEXT NOT NULL,
      is_monitored INTEGER NOT NULL DEFAULT 0,
      is_primary INTEGER NOT NULL DEFAULT 0,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )
  ''';

  static const String createUserPreferences = '''
    CREATE TABLE ${LocalTables.userPreferences} (
      pref_key TEXT NOT NULL PRIMARY KEY,
      pref_value TEXT NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )
  ''';

  static const String createNotificationState = '''
    CREATE TABLE ${LocalTables.notificationState} (
      fingerprint TEXT NOT NULL PRIMARY KEY,
      last_notified_at_utc INTEGER NOT NULL,
      notification_count INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'sent',
      updated_at_utc INTEGER NOT NULL
    )
  ''';

  static const List<String> baseIndexStatements = [
    'CREATE INDEX idx_cached_forecast_fetched '
        'ON ${LocalTables.cachedForecast}(fetched_at_utc)',
    'CREATE INDEX idx_alert_history_status '
        'ON ${LocalTables.alertHistory}(status)',
    'CREATE INDEX idx_alert_history_detected '
        'ON ${LocalTables.alertHistory}(detected_at_utc)',
    'CREATE UNIQUE INDEX idx_monitored_coords '
        'ON ${LocalTables.monitoredLocations}(latitude, longitude)',
    'CREATE INDEX idx_monitored_monitored '
        'ON ${LocalTables.monitoredLocations}(is_monitored)',
    'CREATE INDEX idx_notification_updated '
        'ON ${LocalTables.notificationState}(updated_at_utc)',
  ];

  static const List<String> baseStatements = [
    createCachedWeather,
    createCachedForecast,
    createAlertHistory,
    createMonitoredLocations,
    createUserPreferences,
    createNotificationState,
    ...baseIndexStatements,
  ];

  // ---------------------------------------------------------------
  // v2 additions: sync metadata + last-used tracking on locations
  // ---------------------------------------------------------------

  static const String createSyncState = '''
    CREATE TABLE ${LocalTables.syncState} (
      sync_key TEXT NOT NULL PRIMARY KEY,
      value TEXT,
      last_attempt_utc INTEGER NOT NULL,
      last_success_utc INTEGER,
      status TEXT NOT NULL DEFAULT 'never'
    )
  ''';

  static const String addMonitoredLastUsed = '''
    ALTER TABLE ${LocalTables.monitoredLocations}
    ADD COLUMN last_used_at_utc INTEGER
  ''';

  static const String createMonitoredLastUsedIndex = '''
    CREATE INDEX idx_monitored_last_used
    ON ${LocalTables.monitoredLocations}(last_used_at_utc)
  ''';

  static const List<String> v2Statements = [
    createSyncState,
    addMonitoredLastUsed,
    createMonitoredLastUsedIndex,
  ];

  // ---------------------------------------------------------------
  // v3 additions: Firestore is identity-only and there are no saved places.
  // Both retired tables are dropped; the last-known device position lives in
  // user_preferences instead.
  // ---------------------------------------------------------------

  static const String dropSyncState =
      'DROP TABLE IF EXISTS ${LocalTables.syncState}';

  static const String dropMonitoredLocations =
      'DROP TABLE IF EXISTS ${LocalTables.monitoredLocations}';

  static const List<String> v3Statements = [
    dropSyncState,
    dropMonitoredLocations,
  ];

  // ---------------------------------------------------------------
  // Entry points
  // ---------------------------------------------------------------

  /// Creates the full current schema (called on fresh databases).
  static Future<void> onCreate(Database db, int version) async {
    for (final sql in baseStatements) {
      await db.execute(sql);
    }
    for (final sql in v2Statements) {
      await db.execute(sql);
    }
    for (final sql in v3Statements) {
      await db.execute(sql);
    }
  }

  /// Creates only the v1 schema (test hook for migration coverage).
  static Future<void> onCreateV1(Database db, int version) async {
    for (final sql in baseStatements) {
      await db.execute(sql);
    }
  }

  /// Applies incremental migrations from [oldVersion] to the current version.
  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Version 1 -> 2: sync metadata + location last-used tracking.
    if (oldVersion < 2 && newVersion >= 2) {
      for (final sql in v2Statements) {
        await db.execute(sql);
      }
    }
    // Version 2 -> 3: cloud sync metadata and saved locations are gone.
    if (oldVersion < 3 && newVersion >= 3) {
      for (final sql in v3Statements) {
        await db.execute(sql);
      }
    }
  }
}