import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('defaults read from environment without defines', () {
      final config = AppConfig.fromEnvironment();

      expect(config.environment, 'dev');
      expect(config.loggingEnabled, isTrue);
      expect(
        config.weatherApiBaseUrl,
        'https://api.open-meteo.com/v1',
      );
      expect(
        config.geocodingApiBaseUrl,
        'https://geocoding-api.open-meteo.com/v1',
      );
      expect(config.openWeatherApiKey, isEmpty);
      expect(config.isProduction, isFalse);
    });

    test('firebase web options are null when no values supplied', () {
      final config = AppConfig.fromEnvironment();

      expect(config.firebaseWebOptions, isNull);
      expect(config.hasWebFirebaseConfig, isFalse);
    });

    test('explicit values are honored', () {
      const config = AppConfig(
        environment: 'prod',
        weatherApiBaseUrl: 'https://example.invalid/v1',
        geocodingApiBaseUrl: 'https://geo.example.invalid/v1',
        reverseGeocodingApiBaseUrl: 'https://reverse.example.invalid/v1',
        reverseGeocodingProvider: ReverseGeocodingProvider.disabled,
        openWeatherApiKey: '',
        loggingEnabled: false,
        firebaseWebApiKey: '',
        firebaseWebAuthDomain: '',
        firebaseWebProjectId: '',
        firebaseWebStorageBucket: '',
        firebaseWebMessagingSenderId: '',
        firebaseWebAppId: '',
      );

      expect(config.environment, 'prod');
      expect(config.loggingEnabled, isFalse);
      expect(config.isProduction, isTrue);
    });
  });
}