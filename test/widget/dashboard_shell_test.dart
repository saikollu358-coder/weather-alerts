import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
import 'package:weather_alerts/features/dashboard/presentation/dashboard_shell.dart';
import 'package:weather_alerts/services/location/location_service_providers.dart';
import 'package:weather_alerts/services/notifications/notification_service_providers.dart';
import 'package:weather_alerts/services/weather/weather_service_providers.dart';
import 'package:weather_alerts/core/utils/logger.dart';

import '../helpers/pipeline_fakes.dart';

Widget _wrap({
  FakeWeatherService? weather,
  FakeLocationService? location,
  InMemoryMonitoredLocations? locations,
  InMemoryAlertHistory? alerts,
}) {
  return ProviderScope(
    overrides: [
      monitoredLocationRepositoryProvider.overrideWithValue(
        locations ?? InMemoryMonitoredLocations(),
      ),
      alertHistoryRepositoryProvider.overrideWithValue(
        alerts ?? InMemoryAlertHistory(),
      ),
      weatherServiceProvider.overrideWithValue(weather ?? FakeWeatherService()),
      locationServiceProvider.overrideWithValue(
        location ?? FakeLocationService(),
      ),
      geocodingServiceProvider.overrideWithValue(FakeGeocodingService()),
      preferenceRepositoryProvider.overrideWithValue(InMemoryPreferences()),
      notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
    ],
    child: const MaterialApp(home: DashboardShell()),
  );
}

void main() {
  testWidgets('shell shows the add-location flow on the home tab',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Add a location to start'), findsOneWidget);
    expect(find.text('Choose from saved locations'), findsOneWidget);
  });

  testWidgets('navigates between the weather, alerts and locations tabs',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav_alerts')));
    await tester.pumpAndSettle();
    expect(find.text('No active alerts. Check back when weather changes.'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav_locations')));
    await tester.pumpAndSettle();
    expect(find.text('No saved locations yet.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav_weather')));
    await tester.pumpAndSettle();
    expect(find.text('Add a location to start'), findsOneWidget);
  });

  testWidgets('renders the risk assessment for a loaded location',
      (tester) async {
    final at = DateTime.utc(2026, 9, 6, 12);
    final weather = FakeWeatherService(
      bundle: sampleBundle(
        atUtc: at,
        hourly: [thunderHourlyPoint(at)],
      ),
    );
    final locations = InMemoryMonitoredLocations(
      seed: [sampleLocation(id: 1, name: 'Testville', isPrimary: true)],
    );
    await tester.pumpWidget(_wrap(weather: weather, locations: locations));
    await tester.pumpAndSettle();

    expect(find.text('Testville'), findsOneWidget);
    expect(find.text('High risk'), findsOneWidget);
    expect(find.textContaining('Last updated:'), findsOneWidget);
    expect(find.text('Hazards'), findsOneWidget);
    expect(find.textContaining('Thunderstorm'), findsWidgets);
    expect(find.textContaining('2 hazards active'), findsOneWidget);
  });

  testWidgets('selecting a saved location loads it back on the home tab',
      (tester) async {
    final at = DateTime.utc(2026, 9, 6, 12);
    final weather = FakeWeatherService(
      bundle: sampleBundle(
        atUtc: at,
        hourly: [thunderHourlyPoint(at)],
      ),
    );
    final locations = InMemoryMonitoredLocations(
      seed: [
        sampleLocation(id: 1, name: 'Testville', isPrimary: true),
        sampleLocation(id: 2, name: 'Riverside', latitude: 3.0),
      ],
    );
    await tester.pumpWidget(_wrap(weather: weather, locations: locations));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav_locations')));
    await tester.pumpAndSettle();
    expect(find.text('Riverside'), findsOneWidget);

    await tester.tap(find.text('Riverside'));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardShell), findsOneWidget);
    expect(find.text('Riverside'), findsWidgets);
    expect(weather.lastLocationKey, '3.0,2.0');
  });

  testWidgets('adding the current location saves it to the locations list',
      (tester) async {
    final location = FakeLocationService(
      fix: geoPosition(42.1234, -71.9876),
    );
    await tester.pumpWidget(
      _wrap(location: location, locations: InMemoryMonitoredLocations()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav_locations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add_current_location_button')));
    await tester.pumpAndSettle();

    expect(find.text('Current location added.'), findsOneWidget);
    expect(find.text('42.1234, -71.9876'), findsOneWidget);
  });

  testWidgets('adding the current location asks for permission when denied',
      (tester) async {
    final location = FakeLocationService(
      permission: LocationPermissionStatus.denied,
    );
    await tester.pumpWidget(
      _wrap(location: location, locations: InMemoryMonitoredLocations()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav_locations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add_current_location_button')));
    await tester.pumpAndSettle();

    expect(find.text('Location permission required to add the current '
        'location.'), findsOneWidget);
  });
}