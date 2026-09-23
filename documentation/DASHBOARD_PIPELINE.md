# Dashboard Pipeline (Phase 7)

The dashboard wires the post-authentication home experience end to end:

```
location -> weather (WeatherController) -> analysis (weatherAnalysisProvider)
         -> alerts (AlertIngestUseCase) -> DashboardState
```

All UI talks to providers -> controllers/use cases -> repositories. There is no
business logic inside widgets and no LLM anywhere in the alert path (rules come
solely from the Phase 8 engine).

## Layer overview

| Layer | Location | Responsibility |
| --- | --- | --- |
| Navigation shell | `lib/features/dashboard/presentation/dashboard_shell.dart` | Post-auth `Scaffold` with a Material 3 `NavigationBar` (Weather/Alerts/Locations) over an `IndexedStack`; profile action pushes `RoutePath.profile`. Tab switches hand the selected location back via callbacks. |
| Home tab | `lib/features/dashboard/presentation/dashboard_home_tab.dart` | The pipeline surface: location card, mandatory `Last updated:` + stale indicator, risk banner (`riskLabel` + `AppConstants.assessmentDisclaimer`), in-app notification permission prompt (`NotificationPermissionBanner`), hazard findings, current conditions, next-12-hours and weekly forecast, `needsLocation` + permission panels. |
| Alerts tab | `lib/features/alerts/presentation/alerts_tab.dart` | Active vs history segmented view over `alertsControllerProvider`, acknowledge action, empty/error states. |
| Locations tab | `lib/features/location/presentation/locations_tab.dart` | Saved-locations list over `locationsControllerProvider`; use / make-primary / remove actions, add-current-location button. |
| Orchestrator | `lib/features/dashboard/application/dashboard_controller.dart` + `dashboard_state.dart` | `DashboardController` (Notifier) owns `DashboardStatus { bootstrapping, needsLocation, loading, ready, error }` and exposes `selectLocation`, `useCurrentGps`, `requestPermissionAndUseGps`, `openSettings`, `refresh`, `retry`. |
| Analysis provider | `lib/features/dashboard/application/dashboard_providers.dart` | `weatherAnalysisProvider` runs `WeatherRiskEvaluator.analyze(bundle, now: bundle.fetchedAtUtc)` — anchored to the fetch time so identical data yields identical analyses and identical alert fingerprints. |
| Alert conversion | `lib/features/alerts/application/alert_ingest_use_case.dart` | Upserts one `AlertRecord` per actionable finding (dedup by fingerprint), escalates on severity growth, resolves hazards no longer present, returns still-active alerts. |
| List owners | `lib/features/alerts/application/alerts_controller.dart`, `lib/features/location/application/locations_controller.dart` | Read-only list state for their tabs; callbacks (`refresh`, `acknowledge`, `setPrimary`, `remove`) go through these, never repositories. |
| Label mapping | `lib/features/alerts/application/alert_text.dart`, `lib/features/alerts/presentation/alert_severity_colors.dart` | Engine enum -> display strings / Material colors (kept out of the portable engine). |

## Behavior

* **Bootstrap**: `DashboardController.build()` listens to `weatherControllerProvider`
  and picks the primary saved location (falling back to the first saved one).
  With none, state becomes `needsLocation` and the home tab shows the add flow.
* **GPS add**: `useCurrentGps()` starts `LocationController`; only when
  permission is `ready` does it capture the position, reverse-geocode a name,
  persist via `SaveCurrentLocationUseCase`, mark the record primary and load.
  Permission denials surface the matching panel (Allow / Open Settings).
* **Analysis -> alerts**: on every new ready `WeatherState`, analysis is re-run;
  `AlertIngestUseCase.ingest` runs once per analysis (guarded by
  `analyzedAtUtc`), then `AlertsController.refresh()` repopulates the tab and
  the dashboard keeps `activeAlerts`.
* **Freshness**: the home tab always renders `Last updated: <UTC> (<source>)`
  and a `Data is stale` chip once `bundle.isStale()`; `RefreshIndicator` and the
  refresh button force-refresh the current location.
* **Determinism**: fingerprints anchor to the UTC hour of `analyzedAtUtc`, so
  repeated evaluations within the same hour never re-create alerts, while a
  severity increase escalates the existing record.
* **Failure layout**: weather load errors retain the last bundle and show an
  inline banner when refreshing, or the full error view on first load; repository
  failures surface user-safe messages without leaking internals.

## Testing

* `test/helpers/pipeline_fakes.dart` — `FakeWeatherService`, `FakeLocationService`,
  `FakeGeocodingService`, in-memory `MonitoredLocationRepository` /
  `AlertHistoryRepository`, deterministic `sampleBundle`/`sampleLocation`,
  `makePipelineContainer` and `pumpUntil`.
* `test/unit/dashboard_controller_test.dart` — bootstrap states, selection,
  GPS add, refresh forwarding, error surfaces, alert dedup across refreshes.
* `test/unit/alerts_controller_test.dart` / `locations_controller_test.dart` —
  list splitting, acknowledge, primary/remove, error paths.
* `test/unit/alert_ingest_use_case_test.dart` — ingest/dedup/escalate/resolve
  against the real evaluation engine.
* `test/widget/dashboard_shell_test.dart` — tab navigation, add-location flow,
  risk banner rendering, location selection round-trip.

Run gates: `flutter analyze` and `flutter test` from the repository root.