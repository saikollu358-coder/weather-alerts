# Weather Map Layers (Map tab)

The Map tab renders the device's current position on a **free** base map and can
overlay weather tiles to give context for risk assessment. When OS location
permission has been granted it shows a blue-dot marker plus accuracy circle,
with zoom in/out and recenter controls.

There is nothing to select on this map: the app has no saved places, so the only
marker is where the device is now.

## Architecture

| Piece | Location | Notes |
| --- | --- | --- |
| Map view | `lib/features/location/presentation/locations_map_view.dart` | `flutter_map` + OSM base, live my-location marker + accuracy circle, zoom in/out + recenter controls, layer chip row. |
| Layer resolution | `lib/services/weather_maps/weather_map_layers.dart` | Pure, deterministic: which layers are available and their `TileLayer` URL templates. |
| Radar source | `lib/services/weather_maps/rain_viewer_service.dart` | Fetches the RainViewer tile index; parses host + past frames. |
| Providers | `lib/services/weather_maps/weather_map_providers.dart` | `rainViewerServiceProvider`, `rainViewerRadarProvider`, `weatherMapLayersProvider`. |
| Config | `lib/core/config/app_config.dart` | `openWeatherApiKey` from `WEATHER_ALERTS_OPENWEATHER_API_KEY` (empty when not supplied). |

The map view is a *display* layer only — it never feeds the alert path.
Safety rules and thresholds stay centralized in `lib/services/weather_analysis/`
and are unaffected by which overlay is on screen.

## Current-position marker

* Permission is resolved by `DashboardController`, which prompts only when
  permission has not been granted yet; the permission banner on the home tab
  re-prompts after a denial.
* The live fix comes from `locationControllerProvider` (`LocationStatus.ready` +
  `position`); the Map tab watches it and renders a blue-dot marker and a
  translucent accuracy `CircleLayer`.
* Zoom controls (`map_zoom_in` / `map_zoom_out`) adjust the camera; the recenter
  button (`map_locate`, only shown when a fix exists) re-centers on the device.
  Moving more than `kReloadOnMoveMeters` (500 m) also triggers a recenter and a
  weather reload.

## Layer providers

### Base — OpenStreetMap (`flutter_map`)

* Free; attribution required (`© OpenStreetMap contributors` — shown on the map).
* No billing account, no API key. Works on Android, iOS, web and desktop.
* URL: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`.

### Radar — RainViewer Weather Maps API

* Free for personal/educational use; no API key; attribution required.
* Index endpoint: `https://api.rainviewer.com/public/weather-maps.json`.
* Free tier uses the **universal-blue** 256px tiles up to zoom 7
  (the map overscales them to higher display zooms via `maxNativeZoom`).
* Radar shows past radar frames; the newest frame is used as the overlay.
* Docs: <https://www.rainviewer.com/api.html>.

### Temperature / Wind — OpenWeatherMap weather maps

* Weather-map **tiles are a paid product**; OpenWeatherMap's free tier does not
  include them.
* Only activated when `WEATHER_ALERTS_OPENWEATHER_API_KEY` is supplied at build
  time. Without it the chips are disabled with an explanatory note.
* Layer names: `temp_new` (temperature), `wind_new` (wind).
* URL template: `https://tile.openweathermap.org/map/{layer}/{z}/{x}/{y}.png?appid=...`.

## Configuration

```sh
# Optional; enables Temperature + Wind layers in the map.
flutter run --dart-define=WEATHER_ALERTS_OPENWEATHER_API_KEY=YOUR_KEY
```

The key is read via `String.fromEnvironment`, so it is compile-time only and
never stored in the repository.

## Testing

Unit and widget tests inject a fake `RainViewerRadar` through
`rainViewerRadarProvider` and never hit the network:

```sh
flutter test test/unit/rain_viewer_service_test.dart
flutter test test/unit/weather_map_layers_test.dart
flutter test test/widget/locations_map_view_test.dart
```