# Settings & Notification Permission UX

Phase 11: a user-facing settings screen and an in-app permission prompt, so
notification permission is requested in context instead of dangling off an
advisory startup dialog.

## Design principle

Since Phase 11 the app **never requests OS notification permission at startup**.
Permission is only requested when the user is clearly told why:

1. **In-app prompt** — a dismissible banner on the dashboard home tab.
2. **Settings screen** — an explicit "Allow notifications" action.

Delivery therefore hangs off a conscious user choice, and a "Not now" choice is
persisted so the banner stays out of the way until the user re-enables from
settings.

## Surfaces

### NotificationPermissionBanner (`features/notifications/presentation/`)

Shown in the dashboard home-tab pipeline only when all of these hold
(`NotificationSettingsState.canShowPrompt`):

- the master switch is **on** (`notifications_enabled`),
- the OS permission is **not granted**,
- the prompt was **not dismissed** (`notification_prompt_dismissed != true`),
- the settings state finished loading.

Actions:

| State | Actions |
| --- | --- |
| `denied` | **Allow** (re-prompts once) and **Not now** (persists dismissal) |
| `permanentlyDenied` | **Open app settings** and **Not now** |
| `granted` | banner hidden |

### SettingsScreen (`features/settings/presentation/settings_screen.dart`)

Reachable from the dashboard app-bar gear button (`settings_button`); route
`/settings` (`RoutePath.settings`, already guarded by the auth redirect).

- **Notifications** section:
  - Master `SwitchListTile` backed by `notifications_enabled` (absent = enabled,
    so disabling stores an explicit `'false'`).
  - Permission panel:
    - `granted` → "Notifications are active" status card.
    - `denied` → "Allow notifications" (re-prompt) + "Open app settings".
    - `permanentlyDenied` → "Open app settings" only.
- **About** section: app name, tagline, `AppConstants.assessmentDisclaimer`.

## Permission model

`domain/enums/notification_permission.dart` exposes the three cases the UI
branches on; `LocalNotificationService.permissionStatus()` maps the platforms:

- Android: `areNotificationsEnabled()` — `false` + ≥ 2 dismissed prompts →
  `permanentlyDenied`.
- iOS: `checkPermissions()` — same ≥ 2 dismissals heuristic.
- Unsupported / plugin missing → `granted` (app stays fully usable).

`openSystemSettings()` reuses `Geolocator.openAppSettings()` (geolocator is
already a dependency) and degrades to a no-op where unavailable, so
permanently-denied users can always re-grant from the OS page.

## Controller

`NotificationSettingsController` (a Riverpod `Notifier`) owns all state:

| Method | Behavior |
| --- | --- |
| `build` | async-resolves toggle + dismissal + `permissionStatus()`; failures degrade to `isLoading=false` + `errorMessage`, never crash |
| `toggleEnabled(bool)` | updates state immediately, persists `'true'`/`'false'` |
| `allowNotifications()` | calls the OS prompt, then re-reads `permissionStatus()` |
| `dismissPrompt()` | persists `notification_prompt_dismissed = 'true'` |
| `openSystemSettings()` | deep-links to the OS app-settings page |

## Testing

- `test/unit/notification_settings_controller_test.dart` — resolve defaults,
  persisted off, denied/dismissed resolution, toggle persistence, allow →
  grant/decline, dismiss persistence, settings open, read-failure degradation.
- `test/widget/settings_screen_test.dart` — toggle persistence, permission
  panels per state, and the dashboard → `/settings` navigation.
- `test/widget/notification_permission_banner_test.dart` — hidden on granted /
  switch off, Allow + Not now actions, persist-on-dismiss, permanently-denied
  routing.

Fakes: `FakeNotificationService` and `InMemoryPreferences` in
`test/helpers/pipeline_fakes.dart`.