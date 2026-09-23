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

## Map view (Locations tab)

The Locations tab offers a List / Map toggle. The map (`LocationsMapView`)
renders every saved monitored location as a marker; tapping a marker selects
that location for the weather dashboard (same behaviour as tapping the list
tile).

The map is powered by `google_maps_flutter` and is **opt-in**: it only renders
when a Google Maps API key was supplied at build time. No key is ever
committed — configuration enters via:

| Platform | Key source |
| --- | --- |
| Android | `WEATHER_ALERTS_GOOGLE_MAPS_API_KEY` `--dart-define` (guards the Dart widget) **and** the same value as an env var / Gradle property so Gradle injects it into the manifest placeholder |
| Web | `WEATHER_ALERTS_GOOGLE_MAPS_API_KEY` `--dart-define` (drives the Dart-side guard) **and** the Maps JavaScript API `<script>` tag in `web/index.html` |

Run with a key on Android (pass the dart-define so the Dart guard allows the map,
and the env var so Gradle can inject the manifest value):

```sh
$env:WEATHER_ALERTS_GOOGLE_MAPS_API_KEY="YOUR_KEY"
flutter run --dart-define=WEATHER_ALERTS_GOOGLE_MAPS_API_KEY=YOUR_KEY
```

Build web with both the dart-define and the `web/index.html` script tag
(see the commented placeholder there):

```sh
flutter run -d chrome --dart-define=WEATHER_ALERTS_GOOGLE_MAPS_API_KEY=YOUR_KEY
```

Without a key the map falls back to a "Map not configured" hint, so the app
(and its widget tests) stays fully deterministic and testable on the host.

## Verification

```sh
flutter analyze
flutter test            # 143 tests, incl. 45 Phase 5 tests
flutter build web
```

Tests inject a fake `GeolocatorPlatform` (service), a `MockClient`
(geocoding), and a fake `LocationService` (controller/use case), so nothing
hits a real channel or network.