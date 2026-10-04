# Location & Geography Services

The app resolves the device position (GPS) and its human-readable place name.
There are no saved places: the only location is wherever the device currently
is, and every weather fetch, alert and notification is keyed on that position.

## Layer overview

| Layer | Location | Responsibility |
| --- | --- | --- |
| Entities | `lib/domain/entities/geo_position.dart`, `place.dart`, `current_location.dart` | `GeoPosition` (fix + metadata, `locationKey`, bounds check), `Place` (search result + `displayName`, `fromJson`), `CurrentLocation` (resolved position, label with coordinate fallback, JSON round-trip). |
| Permission model | `lib/domain/enums/location_permission.dart` | `LocationPermissionStatus { denied, deniedForever, granted }` — platform's 5 states collapse into the 3 the UI branches on. |
| Interfaces | `lib/domain/services/location_service.dart`, `geocoding_service.dart` | Plugin/network-free contracts: GPS + permission; place search + reverse. |
| GPS impl | `lib/services/location/geolocator_location_service.dart` | Wraps `geolocator`; the `GeolocatorPlatform` is injectable so tests use a fake. |
| Geocoding impl | `lib/services/location/geocoding_api_service.dart` | Open-Meteo `GET /search` for place names; keyless BigDataCloud reverse geocode for labels (`ReverseGeocodingProvider`, configurable via `AppConfig`). `http` client injectable. |
| Providers | `lib/services/location/location_service_providers.dart` | `locationServiceProvider`, `geocodingServiceProvider`, `httpClientProvider`. |
| Controller | `lib/features/location/application/location_controller.dart` + `location_state.dart` | Permission/ready state machine (`unknown → waitingPermission/denied/deniedForever/unavailable/ready`) and the live position stream. |
| Use case | `lib/features/location/application/resolve_current_location_use_case.dart` | Captures the current position → `CurrentLocationRepository`, naming via reverse geocoding with a per-session label cache. |
| Errors | `lib/core/errors/location_exception.dart` | User-safe `LocationPermissionDeniedException`, `LocationUnavailableException`, `GeocodingException`. |

## Behavior

* `LocationService.permissionStatus()`/`requestPermission()` collapse
  `whileInUse`/`always` → granted, `denied`/`unableToDetermine` → denied,
  `deniedForever` → deniedForever.
* `currentPosition` uses high accuracy with a timeout; plugin failures map to
  `LocationPermissionDeniedException` or `LocationUnavailableException` (never
  raw platform errors).
* `positionStream` transforms every `Position` into `GeoPosition` and maps
  stream errors the same way with `StreamTransformer.fromHandlers`.
* `LocationController.start()` guards on OS service enabled → permission →
  last-known fix → live stream; `requestPermission()` re-prompts after a
  denial; `stop()` cancels the subscription. Stream revocations move the state
  to `denied`.
* `ResolveCurrentLocationUseCase` captures the fix, resolves a label by reverse
  geocoding (BigDataCloud by default), and persists it through
  `CurrentLocationRepository` under the `last_known_location` preference.
  Coordinates are quantized to 4 decimals so the weather cache key, alert key
  and FCM `locationKeys` entry stay stable across reads. Geocoding failures are
  caught and logged: the label falls back to a `lat, lng` string and weather
  still loads. Labels are cached for the process lifetime so repeated captures
  in the same area do not re-hit the geocoder.

## Permissions

Android: `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` are declared and
`geolocator` requests them at runtime. Web uses the browser geolocation API
(page must be served over HTTPS/localhost) and stays compilable; the same
conditional-import principle keeps location code testable without a device.

The home tab resolves permission through `DashboardController`, which captures
the position whenever permission is already granted and only prompts when it is
not. `promptForCurrentLocation()` re-prompts after a denial, and the "Allow
location access" button on the permission banner does the same. Nothing is ever
saved as a *place* — the captured position is only cached as the last known fix
so background checks have something to work with.

## Map view (Map tab)

The Map tab is map-only: there is no location list and nothing to select. Before
permission is granted it renders the permission prompt; once granted,
`LocationsMapView` shows the device position as a blue-dot marker with a
translucent accuracy circle, plus zoom in/out and a recenter button
(bottom-right controls). Moving more than `kReloadOnMoveMeters` (500 m)
recenters and reloads weather for the new position.

The map is powered by `flutter_map` with a free OpenStreetMap base layer and
therefore requires **no API key and no billing account** for the base map. A
layer chip row lets the user overlay weather tiles on top:

| Layer | Provider | Cost / key |
| --- | --- | --- |
| Base | OpenStreetMap | Free, attribution required |
| Radar (precipitation) | RainViewer Weather Maps API | Free for personal/educational use, no key, attribution required; universal-blue 256px tiles up to zoom 7 |
| Temperature / Wind | OpenWeatherMap weather maps | Paid product; requires `WEATHER_ALERTS_OPENWEATHER_API_KEY` at build time |

No secrets are ever committed. The only optional key is the OpenWeatherMap one
(paid, temperature/wind layers only), injected via `--dart-define`:

```sh
flutter run --dart-define=WEATHER_ALERTS_OPENWEATHER_API_KEY=YOUR_KEY
flutter run -d chrome --dart-define=WEATHER_ALERTS_OPENWEATHER_API_KEY=YOUR_KEY
```

Without an OpenWeatherMap key the radar + base layers still work; the
temperature and wind chips are shown disabled with an explanatory note.
RainViewer radar is fetched at runtime and needs no key.

See `documentation/WEATHER_MAPS.md` for service and pricing details.

## Verification

```sh
flutter analyze
flutter test
flutter build web
```

Tests inject a fake `GeolocatorPlatform` (service), a `MockClient`
(geocoding), and a fake `LocationService` (controller/use case), so nothing
hits a real channel or network. `test/unit/current_location_repository_test.dart`
covers the preference round-trip and corrupt-JSON tolerance.