import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/config/app_config.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/domain/entities/geo_position.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
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
  reverseGeocodingApiBaseUrl: 'https://reverse.test.example/reverse',
  reverseGeocodingProvider: ReverseGeocodingProvider.bigDataCloud,
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
  reverseGeocodingApiBaseUrl: 'https://reverse.test.example/reverse',
  reverseGeocodingProvider: ReverseGeocodingProvider.bigDataCloud,
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

/// The tab renders the map shell as soon as permission is granted, so most
/// tests start GPS before pumping to get a fix on screen.
Widget _wrap({
  AppConfig config = _noKeyConfig,
  RainViewerRadar? radar,
  FakeLocationService? location,
}) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      alertHistoryRepositoryProvider.overrideWithValue(InMemoryAlertHistory()),
      currentLocationRepositoryProvider
          .overrideWithValue(InMemoryCurrentLocation()),
      weatherServiceProvider.overrideWithValue(
        FakeWeatherService(bundle: sampleBundle()),
      ),
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
      home: Scaffold(body: LocationsTab()),
    ),
  );
}

bool _hasMarkerAt(
  List<MarkerLayer> layers,
  double latitude,
  double longitude,
) {
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
  testWidgets('renders the map as soon as the pipeline resolves a position',
      (tester) async {
    await tester.pumpWidget(_wrap(radar: _sampleRadar));
    await tester.pumpAndSettle();

    expect(find.byType(LocationsMapView), findsOneWidget);
    expect(find.byKey(const ValueKey('locations_map')), findsOneWidget);
    expect(find.byKey(const ValueKey('my_location_marker')), findsOneWidget);
  });

  testWidgets('renders the map with a my-location marker once GPS returns',
      (tester) async {
    final location = FakeLocationService(
      fix: geoPosition(42.1234, -71.9876),
      permission: LocationPermissionStatus.granted,
    );
    await tester.pumpWidget(_wrap(radar: _sampleRadar, location: location));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LocationsTab)));
    await container.read(locationControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('locations_map')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('my_location_marker')),
      findsOneWidget,
    );
    final markerLayers =
        tester.widgetList<MarkerLayer>(find.byType(MarkerLayer)).toList();
    expect(_hasMarkerAt(markerLayers, 42.1234, -71.9876), isTrue);
    expect(find.byKey(const ValueKey('map_locate')), findsOneWidget);
  });

  testWidgets('radar is selectable by default and every layer is offered',
      (tester) async {
    final location = FakeLocationService(
      fix: geoPosition(42.1234, -71.9876),
      permission: LocationPermissionStatus.granted,
    );
    await tester.pumpWidget(_wrap(radar: _sampleRadar, location: location));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LocationsTab)));
    await container.read(locationControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    for (final name in WeatherMapLayer.values) {
      expect(find.byKey(ValueKey('map_layer_${name.name}')), findsOneWidget);
    }
    final radarChip =
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('map_layer_radar')));
    expect(radarChip.selected, isTrue);
  });

  testWidgets('radar chip is disabled when radar data is unavailable',
      (tester) async {
    final location = FakeLocationService(
      fix: geoPosition(42.1234, -71.9876),
      permission: LocationPermissionStatus.granted,
    );
    await tester.pumpWidget(_wrap(radar: null, location: location));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LocationsTab)));
    await container.read(locationControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    final radarChip = tester
        .widget<ChoiceChip>(find.byKey(const ValueKey('map_layer_radar')));
    expect(radarChip.onSelected, isNull);
    expect(find.text('Radar data is currently unavailable.'), findsOneWidget);
  });

  testWidgets('temperature and wind need an OpenWeatherMap key', (tester) async {
    final location = FakeLocationService(
      fix: geoPosition(42.1234, -71.9876),
      permission: LocationPermissionStatus.granted,
    );
    await tester.pumpWidget(_wrap(radar: _sampleRadar, location: location));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LocationsTab)));
    await container.read(locationControllerProvider.notifier).start();
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
    final location = FakeLocationService(
      fix: geoPosition(42.1234, -71.9876),
      permission: LocationPermissionStatus.granted,
    );
    await tester.pumpWidget(_wrap(
      config: _withKeyConfig,
      radar: _sampleRadar,
      location: location,
    ));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LocationsTab)));
    await container.read(locationControllerProvider.notifier).start();
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

  testWidgets('zoom, locate and the accuracy circle all work', (tester) async {
    final fix = geoPosition(42.1234, -71.9876);
    final location = FakeLocationService(
      fix: GeoPosition(
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracy: 250,
        timestamp: fix.timestamp,
      ),
      permission: LocationPermissionStatus.granted,
    );
    await tester.pumpWidget(_wrap(radar: _sampleRadar, location: location));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LocationsTab)));
    await container.read(locationControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map_zoom_in')), findsOneWidget);
    expect(find.byKey(const ValueKey('map_zoom_out')), findsOneWidget);
    expect(find.byKey(const ValueKey('map_locate')), findsOneWidget);

    final circleLayer = tester.widget<CircleLayer>(find.byType(CircleLayer));
    expect(circleLayer.circles.single.radius, 250);

    await tester.tap(find.byKey(const ValueKey('map_zoom_in')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('map_zoom_out')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('map_locate')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a declined permission prompt replaces the map with a gate',
      (tester) async {
    final location = FakeLocationService(
      permission: LocationPermissionStatus.denied,
    );
    await tester.pumpWidget(_wrap(location: location));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LocationsTab)));
    await container.read(locationControllerProvider.notifier).start();
    await tester.pumpAndSettle();
    await container.read(locationControllerProvider.notifier).requestPermission();
    await tester.pumpAndSettle();

    expect(find.byType(LocationsMapView), findsNothing);
    expect(find.byKey(const ValueKey('allow_location_button')), findsOneWidget);
  });

  testWidgets('permanently denied permission offers a settings shortcut',
      (tester) async {
    final location = FakeLocationService(
      permission: LocationPermissionStatus.deniedForever,
    );
    await tester.pumpWidget(_wrap(location: location));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LocationsTab)));
    await container.read(locationControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    expect(find.byType(LocationsMapView), findsNothing);
    expect(find.byKey(const ValueKey('open_settings_button')), findsOneWidget);
  });
}