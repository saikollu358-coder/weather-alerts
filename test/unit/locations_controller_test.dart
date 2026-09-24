import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/features/location/application/location_providers.dart';
import 'package:weather_alerts/features/location/application/locations_state.dart';

import '../helpers/pipeline_fakes.dart';

void main() {
  group('LocationsController', () {
    test('loads seeded locations into a ready state', () async {
      final locations = InMemoryMonitoredLocations(seed: [
        sampleLocation(id: 1, name: 'Testville', isPrimary: true),
        sampleLocation(id: 2, name: 'Riverside', latitude: 3.0),
      ]);
      final container = makePipelineContainer(locations: locations);
      addTearDown(container.dispose);

      container.read(locationsControllerProvider);
      await pumpUntil(
        () => container.read(locationsControllerProvider).status ==
            LocationsStatus.ready,
      );

      final state = container.read(locationsControllerProvider);
      expect(state.status, LocationsStatus.ready);
      expect(state.locations.length, 2);
      expect(state.primary?.name, 'Testville');
    });

    test('setPrimary moves the primary flag', () async {
      final locations = InMemoryMonitoredLocations(seed: [
        sampleLocation(id: 1, name: 'Testville', isPrimary: true),
        sampleLocation(id: 2, name: 'Riverside', latitude: 3.0),
      ]);
      final container = makePipelineContainer(locations: locations);
      addTearDown(container.dispose);

      await container
          .read(locationsControllerProvider.notifier)
          .setPrimary(2);

      final state = container.read(locationsControllerProvider);
      expect(state.primary?.id, 2);
      final reloaded = await locations.allLocations();
      expect(reloaded.firstWhere((r) => r.id == 2).isPrimary, isTrue);
      expect(reloaded.firstWhere((r) => r.id == 1).isPrimary, isFalse);
    });

    test('remove deletes a saved location', () async {
      final locations = InMemoryMonitoredLocations(seed: [
        sampleLocation(id: 1, name: 'Testville', isPrimary: true),
        sampleLocation(id: 2, name: 'Riverside', latitude: 3.0),
      ]);
      final container = makePipelineContainer(locations: locations);
      addTearDown(container.dispose);

      await container.read(locationsControllerProvider.notifier).remove(2);

      expect(container.read(locationsControllerProvider).locations.length, 1);
      expect((await locations.allLocations()).any((r) => r.id == 2), isFalse);
    });

    test('rename updates the saved name', () async {
      final locations = InMemoryMonitoredLocations(seed: [
        sampleLocation(id: 1, name: 'Testville', isPrimary: true),
      ]);
      final container = makePipelineContainer(locations: locations);
      addTearDown(container.dispose);

      await container
          .read(locationsControllerProvider.notifier)
          .rename(1, ' Home ');

      expect(container.read(locationsControllerProvider).locations.single.name,
          'Home');
      expect((await locations.locationById(1))!.name, 'Home');
    });

    test('rename ignores blank and unchanged names', () async {
      final locations = InMemoryMonitoredLocations(seed: [
        sampleLocation(id: 1, name: 'Testville', isPrimary: true),
      ]);
      final container = makePipelineContainer(locations: locations);
      addTearDown(container.dispose);

      await container.read(locationsControllerProvider.notifier).rename(1, '  ');
      expect((await locations.locationById(1))!.name, 'Testville');

      await container.read(locationsControllerProvider.notifier).rename(1, 'Testville');
      expect((await locations.locationById(1))!.name, 'Testville');
    });

    test('surfaces an error state when the repository throws', () async {
      final locations = InMemoryMonitoredLocations()..failLoads = true;
      final container = makePipelineContainer(locations: locations);
      addTearDown(container.dispose);

      await pumpUntil(
        () => container.read(locationsControllerProvider).status ==
            LocationsStatus.error,
      );

      final state = container.read(locationsControllerProvider);
      expect(state.status, LocationsStatus.error);
      expect(state.errorMessage, isNotNull);
      expect(state.errorMessage, isNot(contains('boom')));
    });
  });
}