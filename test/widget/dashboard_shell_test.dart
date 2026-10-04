import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
import 'package:weather_alerts/features/dashboard/presentation/dashboard_shell.dart';
import 'package:weather_alerts/features/location/presentation/locations_map_view.dart';
import 'package:weather_alerts/services/location/location_service_providers.dart';
import 'package:weather_alerts/services/notifications/notification_service_providers.dart';
import 'package:weather_alerts/services/weather/weather_service_providers.dart';
import 'package:weather_alerts/core/utils/logger.dart';

import '../helpers/pipeline_fakes.dart';

Widget _wrap({
  FakeWeatherService? weather,
  FakeLocationService? location,
  FakeGeocodingService? geocoding,
  InMemoryCurrentLocation? currentLocation,
  InMemoryAlertHistory? alerts,
}) {
  return ProviderScope(
    overrides: [
      alertHistoryRepositoryProvider.overrideWithValue(
        alerts ?? InMemoryAlertHistory(),
      ),
      currentLocationRepositoryProvider.overrideWithValue(
        currentLocation ?? InMemoryCurrentLocation(),
      ),
      weatherServiceProvider.overrideWithValue(
        weather ??
            FakeWeatherService(bundle: sampleBundle(locationKey: '42.1234,-71.9876')),
      ),
      locationServiceProvider.overrideWithValue(
        location ?? FakeLocationService(),
      ),
      geocodingServiceProvider.overrideWithValue(
        geocoding ?? FakeGeocodingService(),
      ),
      preferenceRepositoryProvider.overrideWithValue(InMemoryPreferences()),
      notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
    ],
    child: const MaterialApp(home: DashboardShell()),
  );
}

void main() {
  testWidgets('shell asks for location access when there is no position',
      (tester) async {
    await tester.pumpWidget(
      _wrap(location: FakeLocationService(
        permission: LocationPermissionStatus.denied,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('allow_location_button')), findsOneWidget);
  });

  testWidgets('navigates between the weather, alerts and map tabs',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav_alerts')));
    await tester.pumpAndSettle();
    expect(
      find.text('No active alerts. We will warn you here when hazardous '
          'weather reaches your current location.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('nav_locations')));
    await tester.pumpAndSettle();
    expect(find.byType(LocationsMapView), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav_weather')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Last updated:'), findsOneWidget);
  });

  testWidgets('alerts tab offers no history view, only what is active now',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav_alerts')));
    await tester.pumpAndSettle();

    expect(find.text('No active alerts'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
    expect(find.text('History'), findsNothing);
  });

  testWidgets('renders the risk assessment for the current position',
      (tester) async {
    final at = DateTime.utc(2026, 9, 6, 12);
    final weather = FakeWeatherService(
      bundle: sampleBundle(
        atUtc: at,
        hourly: [thunderHourlyPoint(at)],
      ),
    );
    await tester.pumpWidget(
      _wrap(
        weather: weather,
        location: FakeLocationService(
          fix: geoPosition(42.1234, -71.9876),
          permission: LocationPermissionStatus.granted,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('42.123, -71.988'), findsOneWidget);
    expect(find.text('High risk'), findsOneWidget);
    expect(find.textContaining('Last updated:'), findsOneWidget);
    expect(find.text('Hazards'), findsOneWidget);
    expect(find.textContaining('Thunderstorm'), findsWidgets);
    expect(find.textContaining('2 hazards active'), findsOneWidget);
  });

  testWidgets('manual refresh reloads the weather for the current position',
      (tester) async {
    final weather = FakeWeatherService(
      bundle: sampleBundle(locationKey: '42.1234,-71.9876'),
    );
    await tester.pumpWidget(
      _wrap(
        weather: weather,
        location: FakeLocationService(
          fix: geoPosition(42.1234, -71.9876),
          permission: LocationPermissionStatus.granted,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final callsBeforeRefresh = weather.calls;

    await tester.tap(find.byKey(const ValueKey('refresh_button')));
    await tester.pumpAndSettle();

    expect(weather.calls, callsBeforeRefresh + 1);
    expect(weather.lastForceRefresh, isTrue);
    expect(weather.lastLocationKey, '42.1234,-71.9876');
  });

  testWidgets('surfaces a weather failure with a retry action', (tester) async {
    await tester.pumpWidget(
      _wrap(
        weather: FakeWeatherService(),
        location: FakeLocationService(
          fix: geoPosition(42.1234, -71.9876),
          permission: LocationPermissionStatus.granted,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The fake has no bundle to return, so the pipeline surfaces an error
    // instead of a risk assessment.
    expect(find.text('Turn on location'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });
}