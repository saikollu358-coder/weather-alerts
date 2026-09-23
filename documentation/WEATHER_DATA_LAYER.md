# Weather Data Layer (Phase 6)

Acquires current conditions plus hourly/daily forecasts from Open-Meteo,
cache-first, and exposes them to the app as a typed `WeatherBundle`.

## Layer overview

| Layer | Location | Responsibility |
| --- | --- | --- |
| Entities | `lib/domain/entities/weather/` | `CurrentWeather`, `HourlyForecastPoint`, `DailyForecastPoint`, `WeatherBundle`; tolerant `fromJson`/`toJson` for both the wire and cache payload forms. |
| JSON helpers | `weather_json.dart` | Type coercion (`asDouble`/`asInt`/`at`), parallel-array alignment, offset-less ISO instants treated as UTC. |
| Interface | `lib/domain/services/weather_service.dart` | `load({locationKey, latitude, longitude, forceRefresh})`. |
| Impl | `lib/services/weather/open_meteo_weather_service.dart` | One `/forecast` call for current+hourly+daily; per-slice freshness windows; cache read/write. |
| Providers | `lib/services/weather/weather_service_providers.dart` | `weatherServiceProvider` (wired to the shared `httpClientProvider`). |
| Controller | `lib/features/weather/application/` | `WeatherController` (`idle → loading → ready/error`) + `WeatherState` with staleness and `errorMessage`. |
| Errors | `lib/core/errors/app_exception.dart` | Every failure maps to a user-safe `NetworkException`. |

## Behavior

* **Cache-first**: `load` reads `current`, hourly and daily from the local
  SQLite cache. If every slice is present *and* fresh (`isStale(now:)`), the
  bundle is rebuilt from cache **with zero network calls**. If any slice is
  missing or stale, exactly one `/forecast` call runs and all three fetched
  slices are persisted (`dataSource: 'open-meteo'`).
* **Freshness windows** (constants on the impl): current 30 min, hourly 1 h,
  daily 6 h. `forceRefresh` bypasses a fully fresh cache.
* **Request**: `timezone=UTC` keeps every timestamp unambiguous (an
  offset-less instant is parsed as UTC; stored/compared as UTC epoch-ms via the
  Phase 4 cache). Daily dates become UTC midnight.
* **Opaque weather codes**: the WMO `weather_code` int is carried through the
  models untouched. Code → condition/risk mapping is deliberately NOT here —
  it belongs to the weather-analysis engine (next phase, per AGENTS.md).
* A single API call supplies all three slices, so cache and network data never
  mix within one `load`: fetched data always wins over still-fresh cached
  slices.

## Error mapping

Non-200, timeouts, connectivity failures, malformed JSON, missing blocks and
invalid timestamps all collapse to:
`NetworkException -> 'Weather data is currently unavailable.'`
Internal details are logged (class name only) but never surfaced.

## Verification

```sh
flutter analyze
flutter test            # 172 tests, incl. 29 Phase 6 tests
flutter build web
```

Tests inject a `MockClient` (http), an in-memory `WeatherCacheRepository`
(cache), and a faked `WeatherService` (controller) so nothing hits the network
or a channel. The zero-call guarantee is asserted with a client that fails if
touched.