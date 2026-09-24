# Location & Geography Services (Phase 5)

The app resolves the device position (GPS) and human-readable places so later
phases can fetch weather for a monitored location and issue location-based
alerts.

## Layer overview

| Layer | Location | Responsibility |
| --- | --- | --- |
| Entities | `lib/domain/entities/geo_position.dart`, `place.dart` | `GeoPosition` (fix + metadata, `locationKey`, bounds check), `Place` (search result + `displayName`, `fromJson`). |
| Permission model | `lib/domain/enums/location_permission.dart` | `LocationPermissionStatus { denied, deniedForever, granted }` — platform's 5 states collapse into the 3 the UI branches on. |
| Interfaces | `lib/domain/services/location_service.dart`, `geocoding_service.dart` | Plugin/network-free contracts: GPS + permission; place search + reverse. |
| GPS impl | `lib/services/location/geolocator_location_service.dart` | Wraps `geolocator`; the `GeolocatorPlatform` is injectable so tests use a fake. |
| Geocoding impl | `lib/services/location/geocoding_api_service.dart` | Open-Meteo `GET /search` and `/reverse`, `http` client injectable. |
| Providers | `lib/services/location/location_service_providers.dart` | `locationServiceProvider`, `geocodingServiceProvider`, `httpClientProvider`. |
| Controller | `lib/features/location/application/location_controller.dart` + `location_state.dart` | Permission/ready state machine (`unknown → waitingPermission/denied/deniedForever/unavailable/ready`) and the live position stream. |
| Use case | `lib/features/location/application/save_current_location_use_case.dart` | Captures current position → `MonitoredLocationRepository` (source `gps`), naming via reverse geocoding. |
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
* `SaveCurrentLocationUseCase` uses a supplied name when given, otherwise the
  reverse-geocoded `Place.displayName`, falling back to "Current location" if
  geocoding fails. Duplicate coordinates are rejected by the Phase 4 unique
  index and surfaced as an `AppException` to the caller.

## Permissions

Android: `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` are declared (Phase 1),
and `geolocator` requests them at runtime. Web uses the browser geolocation
API (page must be served over HTTPS/localhost) and stays compilable; the same
conditional-import principle keeps location code testable without a device.

Right after sign-in, when no monitored location exists yet, the home tab calls
`DashboardController.promptForCurrentLocation()` **once** to resolve permission
(prompt only — nothing is saved automatically). Saving the current position is
explicit via the "Add current location" button / "Use my current GPS location"
action, which goes through `SaveCurrentLocationUseCase` and names the location
by reverse geocoding (falling back to "Current location").

## Map view (Locations tab)

The Locations tab offers a List / Map toggle. The map (`LocationsMapView`)
renders every saved monitored location as a marker; tapping a marker selects
that location for the weather dashboard (same behaviour as tapping the list
tile). When location permission was granted, the map also shows a live
blue-dot marker for the device position with a translucent accuracy circle,
plus zoom in/out and a "locate me" button (bottom-right controls). Saved
locations can be renamed from the list tile's action menu.

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
hits a real channel or network.