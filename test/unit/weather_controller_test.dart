import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/errors/app_exception.dart';
import 'package:weather_alerts/domain/entities/weather/weather_bundle.dart';
import 'package:weather_alerts/domain/entities/weather/weather_snapshot.dart';
import 'package:weather_alerts/domain/services/weather_service.dart';
import 'package:weather_alerts/features/weather/application/weather_state.dart';
import 'package:weather_alerts/services/weather/weather_service_providers.dart';
import 'package:weather_alerts/features/weather/application/weather_providers.dart';

WeatherBundle makeBundle() {
  final now = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
  return WeatherBundle(
    locationKey: '1.0,2.0',
    current: CurrentWeather(
      observedAtUtc: now,
      temperatureC: 18.2,
      apparentTemperatureC: 18.0,
      weatherCode: 2,
    ),
    hourly: const [],
    daily: const [],
    fetchedAtUtc: now,
    expiresAtUtc: now.add(const Duration(minutes: 30)),
  );
}

class FakeWeatherService implements WeatherService {
  FakeWeatherService({this.bundle, this.error});

  WeatherBundle? bundle;
  Exception? error;
  int calls = 0;
  String? lastLocationKey;
  bool? lastForceRefresh;

  @override
  Future<WeatherBundle> load({
    required String locationKey,
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    calls++;
    lastLocationKey = locationKey;
    lastForceRefresh = forceRefresh;
    final e = error;
    if (e != null) throw e;
    return bundle!;
  }
}

void main() {
  group('WeatherController', () {
    test('starts in the idle state', () {
      final container = ProviderContainer(
        overrides: [
          weatherServiceProvider.overrideWithValue(FakeWeatherService()),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(weatherControllerProvider).status,
        WeatherStatus.idle,
      );
    });

    test('loads successfully: idle -> loading -> ready with the bundle',
        () async {
      final fake = FakeWeatherService(bundle: makeBundle());
      final container = ProviderContainer(
        overrides: [weatherServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final future = container
          .read(weatherControllerProvider.notifier)
          .load(locationKey: '1.0,2.0', latitude: 1.0, longitude: 2.0);

      expect(container.read(weatherControllerProvider).status,
          WeatherStatus.loading);

      final result = await future;

      expect(result, isNotNull);
      expect(fake.lastLocationKey, '1.0,2.0');
      expect(fake.lastForceRefresh, isFalse);
      final state = container.read(weatherControllerProvider);
      expect(state.status, WeatherStatus.ready);
      expect(state.bundle, isNotNull);
      expect(state.bundle!.current.temperatureC, 18.2);
      expect(state.errorMessage, isNull);
      expect(state.isStale, isFalse);
    });

    test('forwards forceRefresh to the service', () async {
      final fake = FakeWeatherService(bundle: makeBundle());
      final container = ProviderContainer(
        overrides: [weatherServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(weatherControllerProvider.notifier).load(
            locationKey: '1.0,2.0',
            latitude: 1.0,
            longitude: 2.0,
            forceRefresh: true,
          );

      expect(fake.lastForceRefresh, isTrue);
    });

    test('surfaces a user-safe message when an AppException is thrown',
        () async {
      const serviceError =
          NetworkException(message: 'Weather data is currently unavailable.');
      final fake = FakeWeatherService(error: serviceError);
      final container = ProviderContainer(
        overrides: [weatherServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(weatherControllerProvider.notifier)
          .load(locationKey: '1.0,2.0', latitude: 1.0, longitude: 2.0);

      expect(result, isNull);
      final state = container.read(weatherControllerProvider);
      expect(state.status, WeatherStatus.error);
      expect(state.errorMessage, serviceError.message);
      expect(state.bundle, isNull);
    });

    test('falls back on an unexpected exception without leaking internals',
        () async {
      final fake = FakeWeatherService(error: Exception('boom'));
      final container = ProviderContainer(
        overrides: [weatherServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(weatherControllerProvider.notifier)
          .load(locationKey: '1.0,2.0', latitude: 1.0, longitude: 2.0);

      expect(result, isNull);
      final state = container.read(weatherControllerProvider);
      expect(state.status, WeatherStatus.error);
      expect(state.errorMessage, 'Could not load weather data.');
      expect(state.errorMessage, isNot(contains('boom')));
    });

    test('reset clears the loaded bundle', () async {
      final fake = FakeWeatherService(bundle: makeBundle());
      final container = ProviderContainer(
        overrides: [weatherServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container
          .read(weatherControllerProvider.notifier)
          .load(locationKey: '1.0,2.0', latitude: 1.0, longitude: 2.0);
      container.read(weatherControllerProvider.notifier).reset();

      final state = container.read(weatherControllerProvider);
      expect(state.status, WeatherStatus.idle);
      expect(state.bundle, isNull);
    });
  });
}