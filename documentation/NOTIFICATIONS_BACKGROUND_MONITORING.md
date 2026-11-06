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

## Tapping a notification

A tap is a *navigation hint*, never a safety decision: nothing in this path
re-evaluates whether a condition is hazardous.

| File | Responsibility |
| --- | --- |
| `features/alerts/application/alert_tap_payload.dart` | `AlertTapPayload`: lenient parser for both payload producers (JSON from the background check, string-only FCM `data` map from `functions/src/server_alerts/push_router.ts`). Values are trimmed; an id-less or unparsable payload yields `hasAlert == false` instead of throwing. |
| `features/alerts/application/alert_tap_controller.dart` | `AlertTapController` (Notifier): subscribes to all three tap entrypoints — `NotificationService.onOpenedPayloads()`, `FcmService.onMessageOpenedApp()` and the one-shot `FcmService.getInitialMessage()` (cold start). Holds only *which* alert was tapped; `consume()` clears it. FCM guards degrade to empty streams, so the local-only build takes the same safe path. |
| `features/alerts/application/alert_detail_providers.dart` | `alertDetailProvider(fingerprint)` (repository lookup, `null` when the alert is no longer stored) and `acknowledgeAlertProvider`, which invalidates the detail view *and* `alertsControllerProvider` so the alerts tab cannot show a stale "Acknowledge" button. |
| `features/alerts/presentation/alert_detail_screen.dart` | Detail view: severity-tinted header, status/severity chips, "Why this was flagged", measured reading, timestamps, the assessment disclaimer, and Acknowledge. A missing record explains itself; a failed lookup offers a retry. |
| `routing/app_routes.dart` / `routing/app_router.dart` | `/alerts/:id` (`RouteName.alertDetails`), behind the existing auth guard. `RoutePath.alertDetailsFor` percent-encodes the id: fingerprints contain `:` and `,` (e.g. `v8:Thunderstorm:42.123,-71.988:2026-09-06T12:00:00.000Z`) and would otherwise be ambiguous inside a path segment. go_router decodes the parameter again. |
| `features/dashboard/presentation/dashboard_shell.dart` | Performs the navigation. A tap that arrived before the shell existed (cold start) is opened on the first frame; every tap is consumed before pushing, so a rebuild cannot re-open a detail screen behind the user's back. The route is pushed, not replaced, so back returns to the dashboard. |

Tapping is safe in all three launch states: foreground/background taps arrive on
the local-notification stream, a cold start arrives on `getInitialMessage()`, and
until the user authenticates the guard keeps the detail route unreachable — the
pending fingerprint simply waits in `AlertTapController`.

### Testing

`test/unit/alert_tap_payload_test.dart` and
`test/unit/alert_tap_controller_test.dart` cover payload parsing and the three
tap entrypoints; `test/widget/alert_detail_screen_test.dart` covers route
encoding/decoding, every detail-screen state, and end-to-end tap navigation
(including a tap that precedes the dashboard and a tap for an unknown alert).

## Later phases (intentionally deferred)

- Server-driven alerts (`functions/`) forwarded via FCM; this bootstrap already
  forwards compatible foreground pushes to the tray.