import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/config/app_config.dart';
import 'package:weather_alerts/services/weather_maps/rain_viewer_service.dart';
import 'package:weather_alerts/services/weather_maps/weather_map_layers.dart';

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
  openWeatherApiKey: 'test-owm-key',
  loggingEnabled: false,
  firebaseWebApiKey: '',
  firebaseWebAuthDomain: '',
  firebaseWebProjectId: '',
  firebaseWebStorageBucket: '',
  firebaseWebMessagingSenderId: '',
  firebaseWebAppId: '',
);

const _radar = RainViewerRadar(
  host: 'https://tilecache.rainviewer.example',
  pastFrames: [
    RainViewerFrame(time: 1710000000, path: '/v2/radar/1710000000'),
    RainViewerFrame(time: 1710000060, path: '/v2/radar/1710000060'),
  ],
);

const _emptyHostRadar = RainViewerRadar(host: '', pastFrames: []);

void main() {
  group('WeatherMapLayers', () {
    test('base layer is always available', () {
      final layers = WeatherMapLayers(config: _noKeyConfig);
      expect(layers.supports(WeatherMapLayer.base), isTrue);
      expect(
        layers.tileSpec(WeatherMapLayer.base)!.urlTemplate,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      );
    });

    test('radar requires host and frames and uses the latest frame', () {
      final layers = WeatherMapLayers(config: _noKeyConfig, radar: _radar);
      expect(layers.supports(WeatherMapLayer.radar), isTrue);
      expect(
        layers.tileSpec(WeatherMapLayer.radar)!.urlTemplate,
        'https://tilecache.rainviewer.example/v2/radar/1710000060/'
        '256/{z}/{x}/{y}/2/1_1.png',
      );
    });

    test('radar is unavailable without a host or frames', () {
      final noRadar = WeatherMapLayers(config: _noKeyConfig);
      final emptyRadar = WeatherMapLayers(
        config: _noKeyConfig,
        radar: _emptyHostRadar,
      );
      expect(noRadar.supports(WeatherMapLayer.radar), isFalse);
      expect(emptyRadar.supports(WeatherMapLayer.radar), isFalse);
      expect(noRadar.tileSpec(WeatherMapLayer.radar), isNull);
    });

    test('temperature and wind need an OpenWeatherMap key', () {
      final withoutKey = WeatherMapLayers(config: _noKeyConfig, radar: _radar);
      expect(withoutKey.supports(WeatherMapLayer.temperature), isFalse);
      expect(withoutKey.supports(WeatherMapLayer.wind), isFalse);
      expect(withoutKey.tileSpec(WeatherMapLayer.temperature), isNull);
      expect(withoutKey.tileSpec(WeatherMapLayer.wind), isNull);

      final withKey = WeatherMapLayers(config: _withKeyConfig, radar: _radar);
      expect(withKey.supports(WeatherMapLayer.temperature), isTrue);
      expect(withKey.supports(WeatherMapLayer.wind), isTrue);
      expect(
        withKey.tileSpec(WeatherMapLayer.temperature)!.urlTemplate,
        'https://tile.openweathermap.org/map/temp_new/{z}/{x}/{y}.png'
        '?appid=test-owm-key',
      );
      expect(
        withKey.tileSpec(WeatherMapLayer.wind)!.urlTemplate,
        'https://tile.openweathermap.org/map/wind_new/{z}/{x}/{y}.png'
        '?appid=test-owm-key',
      );
    });

    test('radar tile works independently of the OpenWeatherMap key', () {
      final withKey = WeatherMapLayers(config: _withKeyConfig, radar: _radar);
      expect(withKey.supports(WeatherMapLayer.radar), isTrue);
    });
  });
}