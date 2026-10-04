# Notifications & Background Monitoring

Phases 9 + 11 wiring: local notifications, the periodic background weather
check, the foreground FCM bridge, and the user-facing notification settings
(settings screen + dashboard permission prompt). Background checks use the
cached `last_known_location` — the device's position at the last foreground
capture. This is an *app-generated
assessment only* — official warnings always take precedence (see
`AppConstants.assessmentDisclaimer`).

## Components

| File | Responsibility |
| --- | --- |
| `domain/services/notification_service.dart` | Boundary: `requestPermission`, `permissionStatus`, `openSystemSettings`, `showAlert`, `onOpenedPayloads`. Implementations degrade gracefully. |
| `domain/enums/notification_permission.dart` | `NotificationPermissionStatus { denied, permanentlyDenied, granted }` — UI branches on three cases. |
| `services/notifications/local_notification_service.dart` | `flutter_local_notifications` impl. Lazy, idempotent `initialize()`; Android channel `weather_alerts`; iOS via Darwin settings; `permissionStatus()` reads `areNotificationsEnabled`/`checkPermissions`; `openSystemSettings()` deep-links via `Geolocator.openAppSettings()`; delivery failures are never fatal. |
| `services/notifications/notification_service_providers.dart` | Riverpod providers for the service and the bootstrap. |
| `features/notifications/application/background_weather_check_use_case.dart` | Runs the deterministic pipeline once for the last known position and decides what (if anything) to notify. A no-op when no position has ever been cached. |
| `features/notifications/application/notification_preferences.dart` | Preference keys `notifications_enabled` (default: enabled) and `notification_prompt_dismissed` (default: false). |
| `features/notifications/application/notification_settings_state.dart` + `notification_settings_controller.dart` + `notification_settings_providers.dart` | `NotificationSettingsController` (Notifier): loads persisted toggle + `permissionStatus()`; exposes `toggleEnabled`, `allowNotifications`, `dismissPrompt`, `openSystemSettings`. |
| `features/notifications/presentation/notification_permission_banner.dart` | In-app permission prompt shown on the dashboard home tab while it can still help. |
| `services/notifications/workmanager_dispatcher.dart` | `workmanager` OS entry point (`@pragma('vm:entry-point')`). Builds its own object graph in the background isolate — no Riverpod reachable there. Registers the periodic task. |
| `services/notifications/notification_app_bootstrap.dart` | Startup wiring: plugin init → schedule periodic task (15 min) → forward foreground FCM pushes to a local notification. Explicit OS permission is NOT requested at startup — the settings screen and dashboard prompt own it (see `SETTINGS_AND_PERMISSION_UX.md`). |

`main.dart` now calls `notificationAppBootstrapProvider.initialize()` after the
Firebase and local-database bootstraps. `AndroidManifest.xml` gained
`RECEIVE_BOOT_COMPLETED` so the periodic task survives reboots.

## Notification decision rule (dedup + cooldown)

The engine and repositories are shared with the in-app pipeline — there is no
second weather-logic implementation, hence no drift between foreground and
background behavior.

For each actionable finding (`WeatherAnalysis.actionableFindings`) for the last
known position:

1. **Fresh onset** — no *active* alert record for that hazard+location → notify.
   A resolved alert does not count as active, so a cleared-and-reappeared hazard
   notifies again.
2. **Escalation** — the active record's persisted severity *index* is below the
   new finding's severity → notify (cooldown bypassed).
3. **Silent-past-cooldown** — otherwise notify only when the **stable
   notification key** has no delivery record, or its last delivery is older than
   `AppConstants.alertNotificationCooldown` (3 h).

### Stable notification key vs. alert fingerprint

- **Alert fingerprint** (`WeatherRiskEvaluator.fingerprintFor`) is anchored to
  the UTC **hour** bucket; the alert pipeline uses it for history
  deduplication and resolution.
- **Notification key** (`BackgroundWeatherCheckUseCase.notificationKeyFor`) is
  `notif:v{rulesVersion}:{hazard}:{locationKey}` — **no hour bucket** — so an
  ongoing condition is reported at most once per cooldown.

This is a deliberate split: reusing the hour-bucket fingerprint for
notification dedupe would NOTIFY every hour for a continuous condition, which
violates the `NotificationStateRepository` contract ("the same unchanged
condition must not notify repeatedly").

## Failure handling

- `BackgroundWeatherCheckUseCase.check()` never throws; errors are logged and
  degrade to an empty result.
- When notifications are disabled (`notifications_enabled == false`), the
  background task is a no-op (no weather load, no DB writes).
- The task handler (`handleBackgroundCheckTask`) returns `false` only on an unexpected
  failure so WorkManager may retry; a successful (even empty) run returns `true`.
- Logging never includes FCM tokens or other secrets (AppLogger policy).

## Scheduling

- `AppConstants.weatherRefreshInterval` (15 min) is the periodic frequency
  (Android minimum). `ExistingPeriodicWorkPolicy.update` keeps one task
  registered across app upgrades.
- The task runs only on Android/iOS; web/desktop never schedule it.
- Constraints: network connected. The background weather read is cache-first
  (`OpenMeteoWeatherService.load`), reusing the same SQLite cache as the app.

## Testing

`test/unit/background_weather_check_use_case_test.dart` covers, with in-memory
fakes: disabled preference no-op, no-cached-position no-op, benign no-op, fresh
notify-per-hazard, cooldown suppression, post-cooldown re-notify, escalation
bypass, re-detection after resolution, and weather-failure degradation.
`test/unit/notification_settings_controller_test.dart` and
`test/widget/settings_screen_test.dart` /
`test/widget/notification_permission_banner_test.dart` cover the Phase 11
settings + prompt surfaces.

## Later phases (intentionally deferred)

- Navigating from a tapped notification (`onOpenedPayloads`) to the alert
  detail route.
- Server-driven alerts (`functions/`) forwarded via FCM; this bootstrap already
  forwards compatible foreground pushes to the tray.