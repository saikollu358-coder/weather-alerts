import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/errors/app_exception.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
import 'package:weather_alerts/domain/entities/place.dart';
import 'package:weather_alerts/features/alerts/application/alerts_providers.dart';
import 'package:weather_alerts/features/dashboard/application/dashboard_providers.dart';
import 'package:weather_alerts/features/dashboard/application/dashboard_state.dart';
import 'package:weather_alerts/features/location/application/location_providers.dart';
import 'package:weather_alerts/features/location/application/location_state.dart';

import '../helpers/pipeline_fakes.dart';

/// Triggers dashboard bootstrap, then waits until it leaves
/// [DashboardStatus.bootstrapping] and returns the state.
Future<DashboardState> awaitDashboard(ProviderContainer container) async {
  container.read(dashboardControllerProvider);
  await pumpUntil(
    () => container.read(dashboardControllerProvider).status !=
        DashboardStatus.bootstrapping,
  );
  return container.read(dashboardControllerProvider);
}

/// A reverse-geocoding fake that always resolves to [name].
FakeGeocodingService geocodingFor(String name) => FakeGeocodingService(
      place: Place(name: name, latitude: 1, longitude: 2),
    );

void main() {
  group('DashboardController pipeline', () {
    test('boots to needsLocation when there is no cached or live position',
        () async {
      final container = makePipelineContainer(
        location: FakeLocationService(permission: LocationPermissionStatus.denied),
      );
      addTearDown(container.dispose);

      final state = await awaitDashboard(container);

      expect(state.status, DashboardStatus.needsLocation);
      expect(state.location, isNull);
    });

    test(
        'captures the live fix, loads weather, analyses it and persists alerts',
        () async {
      final at = DateTime.utc(2026, 9, 6, 12);
      final location = FakeLocationService(
        fix: geoPosition(18.149, -83.371),
        permission: LocationPermissionStatus.granted,
      );
      final alerts = InMemoryAlertHistory();
      final weather = FakeWeatherService(
        bundle: sampleBundle(atUtc: at, hourly: [thunderHourlyPoint(at)]),
      );
      final container = makePipelineContainer(
        weather: weather,
        location: location,
        geocoding: geocodingFor('San Juan'),
        alerts: alerts,
      );
      addTearDown(container.dispose);

      final state = await awaitDashboard(container);

      expect(state.status, DashboardStatus.ready);
      expect(state.location?.label, 'San Juan');
      expect(state.location?.hasResolvedName, isTrue);
      expect(state.bundle, isNotNull);
      expect(state.analysis, isNotNull);
      expect(state.analysis!.hasActiveHazards, isTrue);
      expect(weather.lastLocationKey, '18.149,-83.371');

      await pumpUntil(
        () => container.read(alertsControllerProvider).active.isNotEmpty,
      );
      final active = container.read(alertsControllerProvider).active;
      expect(active.length, 2); // thunderstorm + lightning
      final hazards = active.map((a) => a.hazard).toSet();
      expect(hazards, contains('thunderstorm'));
      expect(hazards, contains('lightning'));
      expect(
        active.every((a) => a.locationKey == state.location!.locationKey),
        isTrue,
      );
    });

    test('records the captured fix as the last known position', () async {
      final cache = InMemoryCurrentLocation();
      final container = makePipelineContainer(
        location: FakeLocationService(
          fix: geoPosition(18.149, -83.371),
          permission: LocationPermissionStatus.granted,
        ),
        geocoding: geocodingFor('San Juan'),
        currentLocation: cache,
      );
      addTearDown(container.dispose);

      await awaitDashboard(container);

      expect(cache.stored, isNotNull);
      expect(cache.stored!.label, 'San Juan');
      expect(cache.stored!.latitude, 18.149);
      expect(cache.stored!.longitude, -83.371);
    });

test('falls back to a coordinate label when reverse geocoding fails',
        () async {
      final container = makePipelineContainer(
        weather: FakeWeatherService(
          bundle: sampleBundle(locationKey: '42.36,-71.05'),
        ),
        location: FakeLocationService(
          fix: geoPosition(42.36, -71.05),
          permission: LocationPermissionStatus.granted,
        ),
        geocoding: FakeGeocodingService(error: StateError('offline')),
      );
      addTearDown(container.dispose);

      final state = await awaitDashboard(container);

      expect(state.status, DashboardStatus.ready);
      expect(state.location?.label, '42.360, -71.050');
      expect(state.location?.hasResolvedName, isFalse);
    });

    test('shows the cached position before the first fix arrives', () async {
      final cached = sampleCurrentLocation(
        latitude: 18.149,
        longitude: -83.371,
        label: 'San Juan',
      );
      final weather = FakeWeatherService(
        bundle: sampleBundle(locationKey: '18.149,-83.371'),
      );
      final container = makePipelineContainer(
        weather: weather,
        location: FakeLocationService(permission: LocationPermissionStatus.denied),
        currentLocation: InMemoryCurrentLocation(seed: cached),
      );
      addTearDown(container.dispose);

      final state = await awaitDashboard(container);

      expect(state.status, DashboardStatus.ready);
      expect(state.location?.label, 'San Juan');
      expect(weather.lastLocationKey, '18.149,-83.371');
    });

    test('requestPermission resolves the permission and captures the fix',
        () async {
      final cache = InMemoryCurrentLocation();
      final container = makePipelineContainer(
        location: FakeLocationService(
          fix: geoPosition(42.36, -71.05),
          permission: LocationPermissionStatus.granted,
        ),
        weather: FakeWeatherService(bundle: sampleBundle(locationKey: '42.36,-71.05')),
        geocoding: geocodingFor('Boston'),
        currentLocation: cache,
      );
      addTearDown(container.dispose);

      await container
          .read(dashboardControllerProvider.notifier)
          .requestPermission();

      await pumpUntil(
        () => container.read(dashboardControllerProvider).status ==
            DashboardStatus.ready,
      );
      final locationState = container.read(locationControllerProvider);
      expect(locationState.status, LocationStatus.ready);
      expect(locationState.position?.latitude, 42.36);
      expect(cache.stored?.label, 'Boston');
    });

    test('requestPermission surfaces a denial without recording a position',
        () async {
      final cache = InMemoryCurrentLocation();
      final container = makePipelineContainer(
        location: FakeLocationService(
          permission: LocationPermissionStatus.denied,
        ),
        currentLocation: cache,
      );
      addTearDown(container.dispose);

      await container
          .read(dashboardControllerProvider.notifier)
          .requestPermission();

      expect(container.read(locationControllerProvider).status,
          LocationStatus.denied);
      expect(cache.stored, isNull);
    });

    test('requestPermission captures once the user accepts the OS prompt',
        () async {
      final cache = InMemoryCurrentLocation();
      final container = makePipelineContainer(
        location: FakeLocationService(
          fix: geoPosition(42.36, -71.05),
          permission: LocationPermissionStatus.denied,
        )..grantOnRequest = true,
        geocoding: geocodingFor('Boston'),
        currentLocation: cache,
      );
      addTearDown(container.dispose);

      await container
          .read(dashboardControllerProvider.notifier)
          .requestPermission();

      expect(container.read(locationControllerProvider).status,
          LocationStatus.ready);
      expect(cache.stored?.label, 'Boston');
    });

    test('reuses the weather bundle for jitter below the reload threshold',
        () async {
      final location = FakeLocationService(
        fix: geoPosition(18.1490, -83.3710),
        permission: LocationPermissionStatus.granted,
      );
      final weather = FakeWeatherService(
        bundle: sampleBundle(locationKey: '18.149,-83.371'),
      );
      final container = makePipelineContainer(
        weather: weather,
        location: location,
        geocoding: geocodingFor('San Juan'),
      );
      addTearDown(container.dispose);

      await awaitDashboard(container);
      final fetchesAfterBoot = weather.calls;

      // ~11 m of jitter: inside GPS noise, so no new weather request is made.
      location.emit(geoPosition(18.1491, -83.3710));
      await pumpUntil(
        () => container.read(dashboardControllerProvider).status ==
            DashboardStatus.ready,
      );
      await Future<void>.delayed(Duration.zero);

      expect(weather.calls, fetchesAfterBoot);
      expect(
        container.read(dashboardControllerProvider).location?.latitude,
        18.1491,
        reason: 'the displayed position still follows the device',
      );
    });

    test('refetches weather once the device moves past the threshold',
        () async {
      final location = FakeLocationService(
        fix: geoPosition(18.1490, -83.3710),
        permission: LocationPermissionStatus.granted,
      );
      final weather = FakeWeatherService(
        bundle: sampleBundle(locationKey: '18.149,-83.371'),
      );
      final container = makePipelineContainer(
        weather: weather,
        location: location,
        geocoding: geocodingFor('San Juan'),
      );
      addTearDown(container.dispose);

      await awaitDashboard(container);
      final fetchesAfterBoot = weather.calls;

      // ~2.2 km north: well past kReloadOnMoveMeters.
      location.emit(geoPosition(18.1690, -83.3710));
      await pumpUntil(() => weather.calls > fetchesAfterBoot);

      expect(weather.calls, fetchesAfterBoot + 1);
      expect(
        container.read(dashboardControllerProvider).location?.latitude,
        18.169,
      );
    });

    test('refresh forwards forceRefresh to the weather service', () async {
      final weather = FakeWeatherService(bundle: sampleBundle());
      final container = makePipelineContainer(
        weather: weather,
        location: FakeLocationService(
          permission: LocationPermissionStatus.granted,
        ),
      );
      addTearDown(container.dispose);

      await awaitDashboard(container);
      await container.read(dashboardControllerProvider.notifier).refresh();

      expect(weather.lastForceRefresh, isTrue);
      expect(
        container.read(dashboardControllerProvider).status,
        DashboardStatus.ready,
      );
    });

    test('surfaces a user-safe message when weather loading fails', () async {
      const error =
          NetworkException(message: 'Weather data is currently unavailable.');
      final container = makePipelineContainer(
        weather: FakeWeatherService(error: error),
        location: FakeLocationService(
          permission: LocationPermissionStatus.granted,
        ),
      );
      addTearDown(container.dispose);

      final state = await awaitDashboard(container);

      expect(state.status, DashboardStatus.error);
      expect(state.errorMessage, error.message);
    });

    test('re-runs analysis after a refresh and dedupes alerts', () async {
      final at = DateTime.utc(2026, 9, 6, 12);
      final alerts = InMemoryAlertHistory();
      final weather = FakeWeatherService();
      final container = makePipelineContainer(
        weather: weather,
        location: FakeLocationService(
          permission: LocationPermissionStatus.granted,
        ),
        alerts: alerts,
      );
      addTearDown(container.dispose);

      weather.bundle = sampleBundle(
        atUtc: at,
        hourly: [thunderHourlyPoint(at)],
      );
      await awaitDashboard(container);
      await pumpUntil(
        () => container.read(alertsControllerProvider).active.isNotEmpty,
      );
      final firstCount = container.read(alertsControllerProvider).active.length;

      // Same fetch time, same bundle -> same fingerprints, no new alerts.
      await container.read(dashboardControllerProvider.notifier).refresh();
      await pumpUntil(
        () => container.read(alertsControllerProvider).active.length == firstCount,
      );
      expect(container.read(alertsControllerProvider).active.length, firstCount);
    });
  });
}