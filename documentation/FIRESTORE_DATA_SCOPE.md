# Firestore: identity and push routing only

Firestore stores **who you are** and **where to send your alerts**. Nothing
else. Weather, positions and alert history live on the device.

## What is in Firestore

| Path | Purpose |
|---|---|
| `users/{uid}/profile/default` | Display name and email for the account. |
| `users/{uid}/devices/{deviceId}` | This device's FCM token and the `locationKeys` the server-side router matches against. |

`firestore.rules` grants owner read/write for `users/{uid}/{document=**}`, so no
rule changes were needed when the sync domains were removed.

## What is deliberately not in Firestore

- **Positions.** The app has no saved places; the only location is wherever the
  device currently is. The last known fix is cached locally under the
  `last_known_location` preference and never uploaded.
- **Preferences.** Notification toggles are per-device.
- **Alert history.** The Alerts tab shows what is active right now; resolved and
  expired records stay local for deduplication and escalation tracking.

There is no sync engine: no `CloudSyncService`, no `SyncPlanner`, no `SyncDomain`,
no `sync_state` table. `main.dart` no longer starts a sync bootstrap.

## `locationKeys` on the device document

`users/{uid}/devices/{deviceId}.locationKeys` is the list of location keys that
should receive a push for this device. It holds **at most one** key — the
device's own current position, written by
`DeviceTokenService.syncCurrentLocation()` whenever the app captures a fix.

It is empty until the app has captured a fix in the foreground: advertising an
unknown key would route alerts to a device that is not there.

See `SERVER_SIDE_ALERTS.md` for how the router consumes it.

## Verification

```sh
flutter analyze
flutter test
```