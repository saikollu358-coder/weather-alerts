# Dashboard Pipeline

The dashboard wires the post-authentication home experience end to end. Its
input is exactly one thing: where the device currently is.

```
current GPS position -> weather (WeatherController) -> analysis (weatherAnalysisProvider)
                      -> alerts (AlertIngestUseCase) -> DashboardState
```

All UI talks to providers -> controllers/use cases -> repositories. There is no
business logic inside widgets and no LLM anywhere in the alert path (rules come
solely from the deterministic analysis engine).

## Layer overview

| Layer | Location | Responsibility |
| --- | --- | --- |
| Navigation shell | `lib/features/dashboard/presentation/dashboard_shell.dart` | Post-auth `Scaffold` with a Material 3 `NavigationBar` (Weather/Alerts/Map) over an `IndexedStack`; profile action pushes `RoutePath.profile`. |
| Home tab | `lib/features/dashboard/presentation/dashboard_home_tab.dart` | The pipeline surface: current-location card, mandatory `Last updated:` + stale indicator, risk banner (`riskLabel` + `AppConstants.assessmentDisclaimer`), in-app notification permission prompt (`NotificationPermissionBanner`), hazard findings, current conditions, next-12-hours and weekly forecast, `needsLocation` + permission panels. |
| Alerts tab | `lib/features/alerts/presentation/alerts_tab.dart` | Active-alert list over `alertsControllerProvider`, acknowledge action, empty/error states. No history view. |
| Map tab | `lib/features/location/presentation/locations_tab.dart` | Map-only view over the current position (`locationsMapViewProvider`); permission panel or `LocationsMapView`. |
| Orchestrator | `lib/features/dashboard/application/dashboard_controller.dart` + `dashboard_state.dart` | `DashboardController` (Notifier) owns `DashboardStatus { bootstrapping, needsLocation, loading, ready, error }` and exposes `refresh`, `retry`, `promptForCurrentLocation`, `openSettings`. |
| Position resolution | `lib/features/location/application/resolve_current_location_use_case.dart` | Captures the fix, reverse-geocodes a label, persists it as the last known position, and pushes it to FCM routing. |
| Analysis provider | `lib/features/dashboard/application/dashboard_providers.dart` | `weatherAnalysisProvider` runs `WeatherRiskEvaluator.analyze(bundle, now: bundle.fetchedAtUtc)` — anchored to the fetch time so identical data yields identical analyses and identical alert fingerprints. |
| Alert conversion | `lib/features/alerts/application/alert_ingest_use_case.dart` | Upserts one `AlertRecord` per actionable finding (dedup by fingerprint), escalates on severity growth, resolves hazards no longer present, returns still-active alerts. |
| List owner | `lib/features/alerts/application/alerts_controller.dart` | Active-alert list state for the Alerts tab; `refresh`/`acknowledge` go through this, never repositories. |
| Label mapping | `lib/features/alerts/application/alert_text.dart`, `lib/features/alerts/presentation/alert_severity_colors.dart` | Engine enum -> display strings / Material colors (kept out of the portable engine). |

## Behavior

* **Bootstrap**: `DashboardController.build()` captures the live GPS position and
  immediately resolves it into a `CurrentLocation`. If a fix is available it
  loads weather for it; if the OS location service is on but permission is
  already granted, the pipeline proceeds without waiting for a first fix. Only a
  missing permission/service moves the state to `needsLocation`, where the home
  tab shows the Allow / Open Settings panels.
* **Cached position fallback**: when the capture fails (in-flight, permission
  pending, or service disabled) the controller falls back to the persisted
  `last_known_location` and labels the card as cached, so the dashboard still
  renders weather instead of an empty screen.
* **Movement reload**: a new position is only reloaded when it is more than
  `kReloadOnMoveMeters` (500 m) from the last loaded one. Explicit `refresh()`
  bypasses that check.
* **Analysis -> alerts**: on every new ready `WeatherState`, analysis is re-run;
  `AlertIngestUseCase.ingest` runs once per analysis (guarded by
  `analyzedAtUtc`), then `AlertsController.refresh()` repopulates the tab and
  the dashboard keeps `activeAlerts`.
* **Freshness**: the home tab always renders `Last updated: <UTC> (<source>)`
  and a `Data is stale` chip once `bundle.isStale()`; `RefreshIndicator` and the
  refresh button force-refresh the current position.
* **Determinism**: fingerprints anchor to the UTC hour of `analyzedAtUtc`, so
  repeated evaluations within the same hour never re-create alerts, while a
  severity increase escalates the existing record.
* **Failure layout**: weather load errors retain the last bundle and show an
  inline banner when refreshing, or the full error view on first load; repository
  failures surface user-safe messages without leaking internals.

There is no foreground refresh timer: new data arrives when the position moves,
when the user pulls to refresh, or when the app is reopened.

## Testing

* `test/helpers/pipeline_fakes.dart` — `FakeWeatherService`, `FakeLocationService`
  (with an `emit` helper for movement), `FakeGeocodingService`, in-memory
  `CurrentLocationRepository` / `AlertHistoryRepository`, deterministic
  `sampleBundle`/`currentLocation`, `makePipelineContainer` and `pumpUntil`.
* `test/unit/dashboard_controller_test.dart` — bootstrap states, permission
  handling, cached fallback, movement threshold, refresh forwarding, error
  surfaces, alert dedup across refreshes.
* `test/unit/alerts_controller_test.dart` — active-only splitting, acknowledge,
  repository error paths.
* `test/unit/alert_ingest_use_case_test.dart` — ingest/dedup/escalate/resolve
  against the real evaluation engine.
* `test/widget/dashboard_shell_test.dart` — tab navigation, permission flow,
  risk banner rendering, active-alert rendering.
* `test/widget/locations_map_view_test.dart` — map-only rendering and layers.

Run gates: `flutter analyze` and `flutter test` from the repository root.