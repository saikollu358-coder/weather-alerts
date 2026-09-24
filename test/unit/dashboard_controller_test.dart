import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/errors/app_exception.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
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

void main() {
  group('DashboardController pipeline', () {
    test('boots to needsLocation when there are no saved locations', () async {
      final container = makePipelineContainer();
      addTearDown(container.dispose);

      final state = await awaitDashboard(container);

      expect(state.status, DashboardStatus.needsLocation);
      expect(state.location, isNull);
    });

    test(
        'selects the primary location, loads weather, analyses it and '
        'persists alerts', () async {
      final at = DateTime.utc(2026, 9, 6, 12);
      final location = sampleLocation(id: 1, name: 'Testville', isPrimary: true);
      final locations = InMemoryMonitoredLocations(seed: [location]);
      final alerts = InMemoryAlertHistory();
      final weather = FakeWeatherService(
        bundle: sampleBundle(
          atUtc: at,
          hourly: [thunderHourlyPoint(at)],
        ),
      );
      final container = makePipelineContainer(
        weather: weather,
        locations: locations,
        alerts: alerts,
      );
      addTearDown(container.dispose);

      final state = await awaitDashboard(container);

      expect(state.status, DashboardStatus.ready);
      expect(state.location?.name, 'Testville');
      expect(state.bundle, isNotNull);
      expect(state.analysis, isNotNull);
      expect(state.analysis!.hasActiveHazards, isTrue);
      expect(weather.lastLocationKey, location.locationKey);

      await pumpUntil(
        () => container.read(alertsControllerProvider).active.isNotEmpty,
      );
      final active = container.read(alertsControllerProvider).active;
      expect(active.length, 2); // thunderstorm + lightning
      final hazards = active.map((a) => a.hazard).toSet();
      expect(hazards, contains('thunderstorm'));
      expect(hazards, contains('lightning'));
      expect(active.every((a) => a.locationKey == location.locationKey), isTrue);
    });

    test('selectLocation loads the chosen record and keeps it primary',
        () async {
      final secondary = sampleLocation(
        id: 2,
        name: 'Riverside',
        latitude: 3.0,
        longitude: 4.0,
      );
      final locations = InMemoryMonitoredLocations(
        seed: [sampleLocation(id: 1, isPrimary: true), secondary],
      );
      final weather = FakeWeatherService(
        bundle: sampleBundle(locationKey: '3.0,4.0'),
      );
      final container = makePipelineContainer(
        weather: weather,
        locations: locations,
      );
      addTearDown(container.dispose);

      // Let bootstrap settle on the primary location first, then switch.
      await awaitDashboard(container);
      expect(container.read(dashboardControllerProvider).location?.name,
          'Testville');

      await container
          .read(dashboardControllerProvider.notifier)
          .selectLocation(secondary);

      expect(container.read(dashboardControllerProvider).status,
          DashboardStatus.ready);
      expect(container.read(dashboardControllerProvider).location?.name,
          'Riverside');
      expect(weather.lastLocationKey, '3.0,4.0');

      final reloaded = await locations.allLocations();
      expect(reloaded.firstWhere((r) => r.id == 2).isPrimary, isTrue);
      expect(reloaded.firstWhere((r) => r.id == 1).isPrimary, isFalse);
    });

    test('useCurrentGps saves and selects the current position when granted',
        () async {
      final location = FakeLocationService(
        fix: geoPosition(42.36, -71.05),
        permission: LocationPermissionStatus.granted,
      );
      final locations = InMemoryMonitoredLocations();
      final weather = FakeWeatherService(
        bundle: sampleBundle(locationKey: '42.36,-71.05'),
      );
      final container = makePipelineContainer(
        weather: weather,
        location: location,
        locations: locations,
      );
      addTearDown(container.dispose);

      final saved = await container
          .read(dashboardControllerProvider.notifier)
          .useCurrentGps();

      expect(saved, isNotNull);
      expect(saved!.latitude, 42.36);

      await pumpUntil(
        () => container.read(dashboardControllerProvider).status ==
            DashboardStatus.ready,
      );
      final state = container.read(dashboardControllerProvider);
      expect(state.location?.name, '42.360, -71.050');
      expect(weather.lastLocationKey, saved.locationKey);

      final persisted = await locations.allLocations();
      expect(persisted.length, 1);
      expect(persisted.single.isPrimary, isTrue);
    });

    test('promptForCurrentLocation resolves permission without saving',
        () async {
      final location = FakeLocationService(
        fix: geoPosition(42.36, -71.05),
        permission: LocationPermissionStatus.granted,
      );
      final locations = InMemoryMonitoredLocations();
      final container = makePipelineContainer(
        location: location,
        locations: locations,
      );
      addTearDown(container.dispose);

      final granted = await container
          .read(dashboardControllerProvider.notifier)
          .promptForCurrentLocation();

      expect(granted, isTrue);
      final locationState = container.read(locationControllerProvider);
      expect(locationState.status, LocationStatus.ready);
      expect(locationState.position?.latitude, 42.36);
      expect((await locations.allLocations()), isEmpty);
    });

    test('promptForCurrentLocation surfaces a denial without saving',
        () async {
      final location = FakeLocationService(
        permission: LocationPermissionStatus.denied,
      );
      final locations = InMemoryMonitoredLocations();
      final container = makePipelineContainer(
        location: location,
        locations: locations,
      );
      addTearDown(container.dispose);

      final granted = await container
          .read(dashboardControllerProvider.notifier)
          .promptForCurrentLocation();

      expect(granted, isFalse);
      final locationState = container.read(locationControllerProvider);
      expect(locationState.status, LocationStatus.denied);
      expect((await locations.allLocations()), isEmpty);
    });

    test(
        'useCurrentGps requests permission when denied and saves once granted',
        () async {
      final location = FakeLocationService(
        fix: geoPosition(42.36, -71.05),
        permission: LocationPermissionStatus.denied,
      )..grantOnRequest = true;
      final weather = FakeWeatherService(
        bundle: sampleBundle(locationKey: '42.36,-71.05'),
      );
      final locations = InMemoryMonitoredLocations();
      final container = makePipelineContainer(
        weather: weather,
        location: location,
        locations: locations,
      );
      addTearDown(container.dispose);

      final saved = await container
          .read(dashboardControllerProvider.notifier)
          .useCurrentGps();

      expect(saved, isNotNull);
      final locationState = container.read(locationControllerProvider);
      expect(locationState.status, LocationStatus.ready);
      final persisted = await locations.allLocations();
      expect(persisted.length, 1);
      expect(persisted.single.isPrimary, isTrue);
      expect(persisted.single.name, '42.360, -71.050');
    });

    test('useCurrentGps saves nothing when permission stays denied', () async {
      final location = FakeLocationService(
        permission: LocationPermissionStatus.denied,
      );
      final locations = InMemoryMonitoredLocations();
      final container = makePipelineContainer(
        location: location,
        locations: locations,
      );
      addTearDown(container.dispose);

      final saved = await container
          .read(dashboardControllerProvider.notifier)
          .useCurrentGps();

      expect(saved, isNull);
      final locationState = container.read(locationControllerProvider);
      expect(locationState.status, LocationStatus.denied);
      expect((await locations.allLocations()), isEmpty);
    });

    test('refresh forwards forceRefresh to the weather service', () async {
      final locations = InMemoryMonitoredLocations(
        seed: [sampleLocation(id: 1, isPrimary: true)],
      );
      final weather = FakeWeatherService(bundle: sampleBundle());
      final container = makePipelineContainer(
        weather: weather,
        locations: locations,
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
      final locations = InMemoryMonitoredLocations(
        seed: [sampleLocation(id: 1, isPrimary: true)],
      );
      final container = makePipelineContainer(
        weather: FakeWeatherService(error: error),
        locations: locations,
      );
      addTearDown(container.dispose);

      final state = await awaitDashboard(container);

      expect(state.status, DashboardStatus.error);
      expect(state.errorMessage, error.message);
    });

    test('re-runs analysis after a refresh and dedupes alerts', () async {
      final at = DateTime.utc(2026, 9, 6, 12);
      final locations = InMemoryMonitoredLocations(
        seed: [sampleLocation(id: 1, isPrimary: true)],
      );
      final alerts = InMemoryAlertHistory();
      final weather = FakeWeatherService();
      final container = makePipelineContainer(
        weather: weather,
        locations: locations,
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