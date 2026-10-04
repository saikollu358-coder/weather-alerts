# SQLite Offline-First Storage

The app persists weather cache, alert history, user preferences and
notification delivery state locally with SQLite via `sqflite` on native targets
(Android/desktop). This keeps the app usable offline and in the Firebase-optional
local-only guest mode.

The device's last known position is **not** a table: it is a single preference
(`last_known_location`) holding a JSON blob, because there is only ever one
position and nothing to query.

## Layer overview

| Layer | Location | Responsibility |
| --- | --- | --- |
| Entities | `lib/domain/entities/` | Immutable domain records (`CachedWeatherEntry`, `AlertRecord`, `CurrentLocation`, `UserPreference`, `NotificationStateRecord`, `AlertStatus`). |
| Repository interfaces | `lib/domain/repositories/` | Use-case-facing contracts, e.g. `WeatherCacheRepository`, `AlertHistoryRepository`, `CurrentLocationRepository`. |
| Repositories | `lib/data/repositories/*_impl.dart` | Map entities <-> rows through `LocalMappers`, implement upserts/queries, fingerprint dedupe and cooldown logic. |
| Database abstraction | `lib/data/datasources/local/local_database.dart` | Platform-agnostic `LocalDatabase` surface (`query/insert/update/delete/transaction/close/deleteDatabase`). |
| IO adapter | `lib/data/datasources/local/local_database_io.dart` | `SqfliteDatabase` backed by `sqflite`, compiled only where `dart:io` exists. |
| Web fallback | `lib/data/datasources/local/local_database_unavailable.dart` | `UnavailableLocalDatabase` that always throws `DatabaseOpenException`; keeps web compilable. |
| Factory | `lib/data/datasources/local/local_database_factory.dart` | Conditional import (`dart.library.io`) selecting the adapter. |
| Schema/DDL | `lib/data/datasources/local/database_schema.dart` | Table/column constants, DDL, migration steps. |
| Mappers | `lib/data/models/local_models.dart` | `LocalMappers` convert records <-> maps. |
| Providers | `lib/data/repositories/local_repository_providers.dart` | Riverpod providers for the DB plus all repositories. |

Storage failures surface as user-safe errors from
`lib/core/errors/storage_exception.dart`
(`DatabaseOpenException`, `StorageWriteException`, `StorageReadException`).

## Schema (current version 3)

All timestamps are stored as **UTC milliseconds since epoch** (integer
columns). Payloads (`payload`/`value`) are JSON strings.

| Table | Key | Purpose |
| --- | --- | --- |
| `cached_weather` | `location_key` | Snapshot of current weather per location. |
| `cached_forecast` | `(location_key, forecast_type)` | Hourly/daily forecast slices. |
| `alert_history` | autoincrement `id`, unique `fingerprint` | All detected/served alerts, including resolved and expired ones used for dedupe/escalation. |
| `user_preferences` | `pref_key` | Simple key/value settings, including `last_known_location`. |
| `notification_state` | `fingerprint` | Notification delivery tracking (count, cooldown). |

`PRAGMA foreign_keys = ON` is set on open; schema creation is idempotent and
`ensureOpen()` may be called repeatedly.

## Migration strategy

`DatabaseSchema.schemaVersion` is 3.

* Fresh installs run `onCreate` (base v1 statements + v2 statements + v3
  statements).
* Existing installs run `onUpgrade` incrementally:
  * `oldVersion < 2` applies the v2 statements (`sync_state` table,
    `monitored_locations.last_used_at_utc` column + index).
  * `oldVersion < 3` applies the v3 statements, which **drop** `sync_state` and
    `monitored_locations`. Both features are retired: Firestore is identity-only
    and the app has no saved places.
* `onCreateV1` is exposed as a test hook so the v1 -> v3 migration is covered by
  a unit test (`test/unit/app_database_test.dart`), including the assertion that
  user data survived and the retired tables are gone.

Dropping `monitored_locations` is safe because nothing wrote to it once the
last-known position moved to `user_preferences`; on upgrade the cache key in
`cached_weather` simply becomes unreachable and ages out.

## Repository behavior

* **Weather cache** — upserts use `ConflictAlgorithm.replace`; freshness is a
  server-provided `expires_at_utc` falling back to `fetched_at_utc + maxAge`
  (`hasFreshCurrentWeather/hasFreshForecast`). `deleteLocation` clears weather
  and forecasts for one location only.
* **Alert history** — deduplicated by `fingerprint`; `activeAlerts` excludes
  `resolved`/`expired`; `updateStatus`/`markResolved` stamp resolution time;
  `purgeOlderThan` prunes history. The Alerts tab only ever reads
  `activeAlerts`, but resolved/expired rows stay for the ingest pipeline.
* **Current location** — `CurrentLocationRepositoryImpl` reads/writes the
  `last_known_location` preference. Corrupt or absent JSON yields `null` rather
  than throwing, so a background task never crashes on it.
* **User preferences** — `read`/`write`/`delete` plus `readBool`/`writeBool`
  helpers. `device_id` and `last_known_location` live here and never leave the
  device.
* **Notification state** — `recordNotification` increments per fingerprint;
  `shouldNotify(fingerprint, cooldown)` gates repeat alerts.

## Web limitations

Web builds cannot use sqflite. The conditional import resolves to
`UnavailableLocalDatabase`, which reports `isAvailable == false` and throws
user-safe `DatabaseOpenException` on any operation. `main.dart` catches this
during startup so the app still boots on web (read-only, no offline storage).

## Verification

```sh
flutter analyze
flutter test            # includes unit/app_database_test.dart migration coverage
```

`test/helpers/test_database.dart` boots sqflite-common-ffi in a temp directory
so all storage behavior is covered on the host VM without any device.