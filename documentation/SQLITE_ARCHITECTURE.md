# SQLite Offline-First Storage (Phase 4)

The app persists weather cache, alert history, monitored locations, user
preferences, notification delivery state and sync metadata locally with
SQLite via `sqflite` on native targets (Android/desktop). This keeps the app
usable offline and in the Firebase-optional local-only guest mode.

## Layer overview

| Layer | Location | Responsibility |
| --- | --- | --- |
| Entities | `lib/domain/entities/` | Immutable domain records (`CachedWeatherEntry`, `AlertRecord`, `MonitoredLocationRecord`, `UserPreference`, `NotificationStateRecord`, `SyncStateRecord`, `AlertStatus`). |
| Repository interfaces | `lib/domain/repositories/` | Use-case-facing contracts, e.g. `WeatherCacheRepository`, `AlertHistoryRepository`. |
| Repositories | `lib/data/repositories/*_impl.dart` | Map entities <-> rows through `LocalMappers`, implement upserts/queries, fingerprint dedupe and cooldown logic. |
| Database abstraction | `lib/data/datasources/local/local_database.dart` | Platform-agnostic `LocalDatabase` surface (`query/insert/update/delete/transaction/close/deleteDatabase`). |
| IO adapter | `lib/data/datasources/local/local_database_io.dart` | `SqfliteDatabase` backed by `sqflite`, compiled only where `dart:io` exists. |
| Web fallback | `lib/data/datasources/local/local_database_unavailable.dart` | `UnavailableLocalDatabase` that always throws `DatabaseOpenException`; keeps web compilable. |
| Factory | `lib/data/datasources/local/local_database_factory.dart` | Conditional import (`dart.library.io`) selecting the adapter. |
| Schema/DDL | `lib/data/datasources/local/database_schema.dart` | Table/column constants, DDL, migration steps. |
| Mappers | `lib/data/models/local_models.dart` | `LocalMappers` convert records <-> maps. |
| Providers | `lib/data/repositories/local_repository_providers.dart` | Riverpod providers for the DB plus all six repositories. |

Storage failures surface as user-safe errors from
`lib/core/errors/storage_exception.dart`
(`DatabaseOpenException`, `StorageWriteException`, `StorageReadException`).

## Schema (current version 2)

All timestamps are stored as **UTC milliseconds since epoch** (integer
columns). Payloads (`payload`/`value`) are JSON strings.

| Table | Key | Purpose |
| --- | --- | --- |
| `cached_weather` | `location_key` | Snapshot of current weather per location. |
| `cached_forecast` | `(location_key, forecast_type)` | Hourly/daily forecast slices. |
| `alert_history` | autoincrement `id`, unique `fingerprint` | All detected/served alerts. |
| `monitored_locations` | autoincrement `id` | Locations the user monitors; unique index on `(latitude, longitude)`. |
| `user_preferences` | `pref_key` | Simple key/value settings. |
| `notification_state` | `fingerprint` | Notification delivery tracking (count, cooldown). |
| `sync_state` | `sync_key` | Per-domain sync metadata for future Firebase sync (Phase 14+). |

`PRAGMA foreign_keys = ON` is set on open; schema creation is idempotent and
`ensureOpen()` may be called repeatedly.

## Migration strategy

`DatabaseSchema.schemaVersion` is 2.

* Fresh installs run `onCreate` (base v1 statements + v2 statements).
* Existing installs run `onUpgrade` incrementally (`oldVersion < 2` applies
  the v2 statements: `sync_state` table, `monitored_locations.last_used_at_utc`
  column + index).
* `onCreateV1` is exposed as a test hook so the v1 -> v2 migration is covered
  by a unit test (`test/unit/app_database_test.dart`).

## Repository behavior

* **Weather cache** — upserts use `ConflictAlgorithm.replace`; freshness is a
  server-provided `expires_at_utc` falling back to `fetched_at_utc + maxAge`
  (`hasFreshCurrentWeather/hasFreshForecast`). `deleteLocation` clears weather
  and forecasts for one location only.
* **Alert history** — deduplicated by `fingerprint`; `activeAlerts` excludes
  `resolved`/`expired`; `updateStatus`/`markResolved` stamp resolution time;
  `purgeOlderThan` prunes history.
* **Monitored locations** — unique coordinates enforced via DB index; the
  conflict is rethrown as an `AppException` so callers can show a friendly
  message. `setPrimary` runs in a transaction that unsets any other primary
  first; `allLocations` orders most-recently-used first.
* **Notification state** — `recordNotification` increments per fingerprint;
  `shouldNotify(fingerprint, cooldown)` gates repeat alerts.
* **Sync state** — `recordAttempt/Success/Failure` keep last attempt/success
  timestamps per domain. `value` stores the Phase 14 reconciliation snapshot
  (`{"snapshot": {key: updatedAtUtcMillis}}`) that lets the
  `CloudSyncService` (`lib/services/sync/`) detect remote deletions across
  devices while keeping last-write-wins semantics.

## Web limitations

Web builds cannot use sqflite. The conditional import resolves to
`UnavailableLocalDatabase`, which reports `isAvailable == false` and throws
user-safe `DatabaseOpenException` on any operation. `main.dart` catches this
during startup so the app still boots on web (read-only, no offline storage).

## Verification

```sh
flutter analyze
flutter test            # includes unit/app_database_test.dart + 6 repo suites (98 tests)
```

`test/helpers/test_database.dart` boots sqflite-common-ffi in a temp directory
so all storage behavior is covered on the host VM without any device.