import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/config/app_config.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/domain/entities/geo_position.dart';
import 'package:weather_alerts/features/location/application/location_providers.dart';
import 'package:weather_alerts/features/location/presentation/locations_map_view.dart';
import 'package:weather_alerts/features/location/presentation/locations_tab.dart';
import 'package:weather_alerts/services/location/location_service_providers.dart';
import 'package:weather_alerts/services/notifications/notification_service_providers.dart';
import 'package:weather_alerts/services/weather/weather_service_providers.dart';
import 'package:weather_alerts/services/weather_maps/rain_viewer_service.dart';
import 'package:weather_alerts/services/weather_maps/weather_map_layers.dart';
import 'package:weather_alerts/services/weather_maps/weather_map_providers.dart';

import '../helpers/pipeline_fakes.dart';

const _noKeyConfig = AppConfig(
  environment: 'test',
  weatherApiBaseUrl: 'https://api.test.example/v1',
  geocodingApiBaseUrl: 'https://geocode.test.example/v1',
  openWeatherApiKey: '',
  loggingEnabled: false,
  firebaseWebApiKey: '',
  firebaseWebAuthDomain: '',
  firebaseWebProjectId: '',
  firebaseWebStorageBucket: '',
  firebaseWebMessagingSenderId: '',
  firebaseWebAppId: '',
);

const _withKeyConfig = AppConfig(
  environment: 'test',
  weatherApiBaseUrl: 'https://api.test.example/v1',
  geocodingApiBaseUrl: 'https://geocode.test.example/v1',
  openWeatherApiKey: 'test-owm-key-not-real',
  loggingEnabled: false,
  firebaseWebApiKey: '',
  firebaseWebAuthDomain: '',
  firebaseWebProjectId: '',
  firebaseWebStorageBucket: '',
  firebaseWebMessagingSenderId: '',
  firebaseWebAppId: '',
);

const _sampleRadar = RainViewerRadar(
  host: 'https://tilecache.example.invalid',
  pastFrames: [
    RainViewerFrame(time: 1710000000, path: '/v2/radar/1710000000'),
  ],
);

Widget _wrap({
  AppConfig config = _noKeyConfig,
  InMemoryMonitoredLocations? locations,
  RainViewerRadar? radar,
  FakeLocationService? location,
}) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      monitoredLocationRepositoryProvider.overrideWithValue(
        locations ?? InMemoryMonitoredLocations(),
      ),
      alertHistoryRepositoryProvider.overrideWithValue(InMemoryAlertHistory()),
      weatherServiceProvider.overrideWithValue(FakeWeatherService()),
      locationServiceProvider.overrideWithValue(
        location ?? FakeLocationService(),
      ),
      geocodingServiceProvider.overrideWithValue(FakeGeocodingService()),
      preferenceRepositoryProvider.overrideWithValue(InMemoryPreferences()),
      notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
      rainViewerRadarProvider.overrideWith(
        (ref) async => radar,
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: LocationsTab(onSelect: _ignoreSelect)),
    ),
  );
}

void _ignoreSelect(_) {}

bool _hasMarkerAt(List<MarkerLayer> layers, double latitude, double longitude) {
  for (final layer in layers) {
    for (final marker in layer.markers) {
      final point = marker.point;
      if ((point.latitude - latitude).abs() < 1e-9 &&
          (point.longitude - longitude).abs() < 1e-9) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  testWidgets('locations tab shows the list view by default', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add_current_location_button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('locations_view_toggle')), findsOneWidget);
    expect(find.byType(LocationsMapView), findsNothing);
  });

  testWidgets('toggling to the map view shows the empty message without saved '
      'locations', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    expect(find.byType(LocationsMapView), findsOneWidget);
    expect(find.text('No saved locations to show on the map yet.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('locations_map')), findsNothing);
  });

  testWidgets('map view renders and radar is selectable by default',
      (tester) async {
    final locations = InMemoryMonitoredLocations(
      seed: [
        sampleLocation(id: 1, name: 'Testville', isPrimary: true),
        sampleLocation(id: 2, name: 'Riverside', latitude: 3.0),
      ],
    );
    await tester.pumpWidget(_wrap(locations: locations, radar: _sampleRadar));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    expect(find.byType(LocationsMapView), findsOneWidget);
    expect(find.byKey(const ValueKey('locations_map')), findsOneWidget);
    expect(find.byKey(const ValueKey('location_marker_1.0,2.0')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('location_marker_3.0,2.0')),
        findsOneWidget);

    for (final name in WeatherMapLayer.values) {
      expect(find.byKey(ValueKey('map_layer_${name.name}')), findsOneWidget);
    }
    ChoiceChip radarChip() =>
        tester.widget(find.byKey(const ValueKey('map_layer_radar')));
    expect(radarChip().selected, isTrue);
  });

  testWidgets('radar chip is disabled when radar data is unavailable',
      (tester) async {
    final locations = InMemoryMonitoredLocations(
      seed: [sampleLocation(id: 1, name: 'Testville', isPrimary: true)],
    );
    await tester.pumpWidget(_wrap(locations: locations, radar: null));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    final radarChip =
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('map_layer_radar')));
    expect(radarChip.onSelected, isNull);
  });

  testWidgets('temperature and wind need an OpenWeatherMap key',
      (tester) async {
    final locations = InMemoryMonitoredLocations(
      seed: [sampleLocation(id: 1, name: 'Testville', isPrimary: true)],
    );
    await tester.pumpWidget(_wrap(locations: locations, radar: _sampleRadar));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('WEATHER_ALERTS_OPENWEATHER_API_KEY'),
      findsOneWidget,
    );
    final temperatureChip = tester
        .widget<ChoiceChip>(find.byKey(const ValueKey('map_layer_temperature')));
    final windChip =
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('map_layer_wind')));
    expect(temperatureChip.onSelected, isNull);
    expect(windChip.onSelected, isNull);
  });

  testWidgets('temperature layer is selectable when a key is configured',
      (tester) async {
    final locations = InMemoryMonitoredLocations(
      seed: [sampleLocation(id: 1, name: 'Testville', isPrimary: true)],
    );
    await tester.pumpWidget(
      _wrap(locations: locations, config: _withKeyConfig, radar: _sampleRadar),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('WEATHER_ALERTS_OPENWEATHER_API_KEY'),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('map_layer_temperature')));
    await tester.pump();

    final temperatureChip = tester
        .widget<ChoiceChip>(find.byKey(const ValueKey('map_layer_temperature')));
    final radarChip =
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('map_layer_radar')));
    expect(temperatureChip.selected, isTrue);
    expect(radarChip.selected, isFalse);
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

  testWidgets('map offers zoom controls and hides locate without a fix',
      (tester) async {
    final locations = InMemoryMonitoredLocations(
      seed: [sampleLocation(id: 1, name: 'Testville', isPrimary: true)],
    );
    await tester.pumpWidget(_wrap(locations: locations, radar: _sampleRadar));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map_zoom_in')), findsOneWidget);
    expect(find.byKey(const ValueKey('map_zoom_out')), findsOneWidget);
    expect(find.byKey(const ValueKey('map_locate')), findsNothing);
    final markerLayers = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .toList();
    expect(_hasMarkerAt(markerLayers, 42.1234, -71.9876), isFalse);

    await tester.tap(find.byKey(const ValueKey('map_zoom_in')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('map_zoom_out')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('map shows a my-location marker and locate with a GPS fix',
      (tester) async {
    final locations = InMemoryMonitoredLocations(
      seed: [sampleLocation(id: 1, name: 'Testville', isPrimary: true)],
    );
    final location = FakeLocationService(
      fix: geoPosition(42.1234, -71.9876),
    );
    await tester.pumpWidget(
      _wrap(locations: locations, radar: _sampleRadar, location: location),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LocationsTab)));
    await container.read(locationControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    expect(container.read(locationControllerProvider).position?.latitude,
        42.1234);
    final markerLayers = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .toList();
    expect(_hasMarkerAt(markerLayers, 42.1234, -71.9876), isTrue);
    expect(find.byKey(const ValueKey('map_locate')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map_locate')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('map shows an accuracy circle when the fix reports one',
      (tester) async {
    final locations = InMemoryMonitoredLocations(
      seed: [sampleLocation(id: 1, name: 'Testville', isPrimary: true)],
    );
    final fix = geoPosition(42.1234, -71.9876);
    final location = FakeLocationService(
      fix: GeoPosition(
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracy: 250,
        timestamp: fix.timestamp,
      ),
    );
    await tester.pumpWidget(
      _wrap(locations: locations, radar: _sampleRadar, location: location),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LocationsTab)));
    await container.read(locationControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    final markerLayers = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .toList();
    expect(_hasMarkerAt(markerLayers, 42.1234, -71.9876), isTrue);
    final circleLayer = tester.widget<CircleLayer>(find.byType(CircleLayer));
    expect(circleLayer.circles.single.radius, 250);
  });
}