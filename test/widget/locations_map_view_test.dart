import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/config/app_config.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/features/location/presentation/locations_map_view.dart';
import 'package:weather_alerts/features/location/presentation/locations_tab.dart';
import 'package:weather_alerts/services/location/location_service_providers.dart';
import 'package:weather_alerts/services/notifications/notification_service_providers.dart';
import 'package:weather_alerts/services/weather/weather_service_providers.dart';

import '../helpers/pipeline_fakes.dart';

const _noKeyConfig = AppConfig(
  environment: 'test',
  weatherApiBaseUrl: 'https://api.test.example/v1',
  geocodingApiBaseUrl: 'https://geocode.test.example/v1',
  googleMapsApiKey: '',
  loggingEnabled: false,
  firebaseWebApiKey: '',
  firebaseWebAuthDomain: '',
  firebaseWebProjectId: '',
  firebaseWebStorageBucket: '',
  firebaseWebMessagingSenderId: '',
  firebaseWebAppId: '',
);

Widget _wrap({
  AppConfig config = _noKeyConfig,
  InMemoryMonitoredLocations? locations,
}) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      monitoredLocationRepositoryProvider.overrideWithValue(
        locations ?? InMemoryMonitoredLocations(),
      ),
      alertHistoryRepositoryProvider.overrideWithValue(InMemoryAlertHistory()),
      weatherServiceProvider.overrideWithValue(FakeWeatherService()),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      geocodingServiceProvider.overrideWithValue(FakeGeocodingService()),
      preferenceRepositoryProvider.overrideWithValue(InMemoryPreferences()),
      notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: LocationsTab(onSelect: _ignoreSelect)),
    ),
  );
}

void _ignoreSelect(_) {}

void main() {
  testWidgets('locations tab shows the list view by default', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add_current_location_button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('locations_view_toggle')), findsOneWidget);
    expect(find.byType(LocationsMapView), findsNothing);
  });

  testWidgets('toggling to the map view shows the setup hint without an API '
      'key', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    expect(find.byType(LocationsMapView), findsOneWidget);
    expect(find.text('Map not configured'), findsOneWidget);
    expect(find.byKey(const ValueKey('locations_map')), findsNothing);
  });

  testWidgets('map view with saved locations still shows the setup hint when '
      'no key is configured', (tester) async {
    final locations = InMemoryMonitoredLocations(
      seed: [
        sampleLocation(id: 1, name: 'Testville', isPrimary: true),
        sampleLocation(id: 2, name: 'Riverside', latitude: 3.0),
      ],
    );
    await tester.pumpWidget(_wrap(locations: locations));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    expect(find.byType(LocationsMapView), findsOneWidget);
    expect(find.text('Map not configured'), findsOneWidget);
    expect(find.text('No saved locations to show on the map yet.'),
        findsNothing);
  });

  testWidgets('map view with a key but no locations shows the empty message',
      (tester) async {
    const withKey = AppConfig(
      environment: 'test',
      weatherApiBaseUrl: 'https://api.test.example/v1',
      geocodingApiBaseUrl: 'https://geocode.test.example/v1',
      googleMapsApiKey: 'test-key-not-real',
      loggingEnabled: false,
      firebaseWebApiKey: '',
      firebaseWebAuthDomain: '',
      firebaseWebProjectId: '',
      firebaseWebStorageBucket: '',
      firebaseWebMessagingSenderId: '',
      firebaseWebAppId: '',
    );
    await tester.pumpWidget(_wrap(config: withKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    expect(find.text('No saved locations to show on the map yet.'),
        findsOneWidget);
  });

  testWidgets('toggling back to the list restores the list view',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.byType(LocationsMapView), findsOneWidget);

    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(find.byType(LocationsMapView), findsNothing);
    expect(find.text('No saved locations yet.'), findsOneWidget);
  });
}
