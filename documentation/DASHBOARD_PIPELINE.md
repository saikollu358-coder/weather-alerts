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
| Navigation shell | `lib/features/dashboard/presentation/dashboard_shell.dart` | Post-auth `Scaffold` with the app header, a persistent `_Sidebar` at `>= 900` CSS px and a Material 3 `NavigationBar` (Weather/Alerts/Map) below it, both driving one `IndexedStack` tab index; profile action pushes `RoutePath.profile`. |
| Home tab | `lib/features/dashboard/presentation/dashboard_home_tab.dart` | The pipeline surface: location hero, mandatory `Last updated:` + stale indicator, risk banner (`riskLabel` + `AppConstants.assessmentDisclaimer`), in-app notification permission prompt (`NotificationPermissionBanner`), hazard findings, current conditions, next-12-hours and weekly forecast, `needsLocation` + permission panels. |
| Alerts tab | `lib/features/alerts/presentation/alerts_tab.dart` | Active-alert list over `alertsControllerProvider`, acknowledge action, empty/error states. No history view. |
| Map tab | `lib/features/location/presentation/locations_tab.dart` | Map-only view over the current position (`locationsMapViewProvider`); permission panel or `LocationsMapView`. |
| Orchestrator | `lib/features/dashboard/application/dashboard_controller.dart` + `dashboard_state.dart` | `DashboardController` (Notifier) owns `DashboardStatus { bootstrapping, needsLocation, loading, ready, error }` and exposes `refresh`, `retry`, `promptForCurrentLocation`, `openSettings`. |
| Position resolution | `lib/features/location/application/resolve_current_location_use_case.dart` | Captures the fix, reverse-geocodes a label, persists it as the last known position, and pushes it to FCM routing. |
| Analysis provider | `lib/features/dashboard/application/dashboard_providers.dart` | `weatherAnalysisProvider` runs `WeatherRiskEvaluator.analyze(bundle, now: bundle.fetchedAtUtc)` — anchored to the fetch time so identical data yields identical analyses and identical alert fingerprints. |
| Alert conversion | `lib/features/alerts/application/alert_ingest_use_case.dart` | Upserts one `AlertRecord` per actionable finding (dedup by fingerprint), escalates on severity growth, resolves hazards no longer present, returns still-active alerts. |
| List owner | `lib/features/alerts/application/alerts_controller.dart` | Active-alert list state for the Alerts tab; `refresh`/`acknowledge` go through this, never repositories. |
| Label mapping | `lib/features/alerts/application/alert_text.dart`, `lib/features/alerts/presentation/alert_severity_colors.dart` | Engine enum -> display strings / Material colors (kept out of the portable engine). |

## Visual system

Presentation only — no provider, repository, route, threshold or data field
changed with it.

| Piece | Location | Notes |
| --- | --- | --- |
| Design tokens | `lib/core/theme/weather_palette.dart` | Dark navy canvas, cyan/blue accents, radii, borders, shadows, `canvasGradient`. |
| Theme | `lib/core/theme/app_theme.dart` | Material 3 `light()`/`dark()` built from the seed; the dark scheme overrides `surface`/`onSurface` etc. with the palette so tokens and scheme agree. |
| Surfaces | `lib/core/widgets/glass_card.dart` | `GlassCard`, `DashboardSectionHeader`, `DashboardPill`, `DashboardMetric`. Labels ellipsize/wrap rather than overflow; blur is opt-in. |
| Icons | `lib/core/widgets/weather_glyphs.dart` | WMO code -> label / icon / accent, shared by home and hourly rows. |
| Responsive rule | `dashboard_shell.dart` `_kSidebarBreakpoint` | `>= 900` logical px shows the sidebar; below it, the bottom `NavigationBar`. Both call the same tab index, so navigation tests hold at either width. |
| Theme mode | `lib/app.dart` | `ThemeMode.dark`. The home tab renders against `WeatherPalette` tokens, so following the system setting would render light tabs behind a dark shell. `AppTheme.light()` remains for a future toggle. |

Pushed screens (`AlertDetailScreen`, `SettingsScreen`, `ProfileScreen`) share
the shell's `canvasGradient` so opening one does not swap a dark surface for a
flat one.

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

## Presentation motion

Motion is applied on the home, alerts and shell surfaces only. It lives in one
place, `lib/core/widgets/app_motion.dart`, so screens stay declarative:

| Helper | Effect | Used for |
| --- | --- | --- |
| `AppMotion` | Shared durations (`quick`/`standard`/`relaxed`), stagger step, curves, `staggerFor(index)` | everywhere |
| `AnimatedEntrance` | One-shot fade + slide (+ optional scale) with a delay | Staggered reveal of the pipeline sections, permission panel, list items, error/empty states |
| `AnimatedNumber` | Tweens a numeric reading between values and formats it | Temperature, hazard count, hourly/daily temperatures and precipitation |
| `PopOnChange` | Single scale pop keyed on an identity value | Risk level, severity label, active-alert count |
| `PressableScale` | `Listener`-based press-down scale | Alert cards |

Rules the helpers keep:

* **Every animation is finite.** Nothing loops, so `pumpAndSettle()` returns in
  widget tests and no ticker outlives the screen that started it.
* **Reduced motion is honoured.** When `MediaQueryData.disableAnimations` is
  set, entrances jump to their final value and counters render their target
  immediately.
* **Safety information never animates away.** Severity and risk keep their text
  label next to any animated colour, the `Last updated:` timestamp and stale
  chip are untouched, and the disclaimer is never a transient.
* **Purely presentational.** No provider, repository, threshold or alert rule
  was changed; animation state is not business logic.

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
  risk banner rendering, active-alert rendering, plus a `renders without
  overflow` case at 1440x1100 (sidebar) and 420x1000 (bottom bar) that asserts
  the breakpoint swaps one navigation surface for the other.
* `test/widget/locations_map_view_test.dart` — map-only rendering and layers.

Run gates: `flutter analyze` and `flutter test` from the repository root.