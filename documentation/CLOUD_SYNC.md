# Cloud Sync (Phase 14)

Backs up and shares user data across devices via per-user Firestore
sub-collections, tracked by the local `sync_state` table.

## Scope

Only data owned by the signed-in user is synced, under `users/{uid}`:

| Domain | Collection | Document id | Keys |
|---|---|---|---|
| Monitored locations | `locations` | `locationKey` (`lat,lng`) | `name`, coords, `source`, `isMonitored`, `isPrimary`, timestamps |
| Preferences | `preferences` | preference key | whitelisted keys only |
| Alert history | `user_alerts` | alert `fingerprint` | full `AlertRecord` fields |

`firestore.rules` already grants owner read/write for `users/{uid}/{document=**}`,
so no rule changes were required.

## Semantics

- **Last-write-wins** per record, decided on `updatedAtUtc`.
- **Deletions** are detected with a persistent snapshot of the last reconciled
  remote state (`sync_key` → `sync_state.value` → `{"snapshot": {key: ms}}`).
  A record missing on one side but present in the snapshot is treated as
  deleted on that side — but only if the surviving copy is *unchanged* (not
  newer than the snapshot).
- **Alerts are append-only** (`deletionsEnabled: false`): a locally purged or
  remotely missing alert is re-created (applied/uploaded) rather than deleted,
  because local purge is cache hygiene, not an authoritative delete.
- Only `syncablePreferenceKeys` (`notifications_enabled`,
  `notification_prompt_dismissed`) sync. Local tokens such as `device_id`
  never leave the device.

## Architecture

```
CloudSyncBootstrap (main.dart)   auth.watchAuthState()
        └─ non-guest sign-in ──► CloudSyncService.syncAll() + startPeriodic()
                                   │  per SyncDomain
                                   ├─ load local (repos) + remote (CloudDataStore.queryData)
                                   ├─ load snapshot (sync_state)
                                   ├─ SyncPlanner.plan(...)            [pure, tested]
                                   ├─ execute upload / delete / apply
                                   └─ persist next snapshot (sync_state.value)
```

- `CloudDataStore` (`lib/services/firebase/cloud_data_store.dart`) is the narrow
  interface the sync layer depends on; `FirestoreService` implements it, and
  tests use an in-memory fake.
- Serialization lives in module-private codecs in
  `lib/services/sync/cloud_sync_service.dart` (`_locationToDoc`, `_preferenceToDoc`,
  `_alertToDoc` + inverse). Payloads are stored as JSON strings; malformed input
  degrades to empty values.
- `startPeriodic()` schedules a resync every
  `AppConstants.weatherRefreshInterval` (15 min) and is idempotent; guests and
  Firebase-less sessions are no-ops (`isSyncAvailable`).
- Domain failures are isolated: `syncAll` runs each domain in its own
  try/catch and records the outcome in `sync_state`.

## Known trade-offs

- Applying a remote preference writes locally with a fresh `now` timestamp, so
  an uploaded-then-applied value may win once more on the next cycle and then
  converge (documented, acceptable for boolean flags).
- Alerts purged locally will be re-pulled on the next successful sync
  (append-only guarantee).

## Verification

```sh
flutter analyze
flutter test test/unit/sync_planner_test.dart test/unit/cloud_sync_service_test.dart
```