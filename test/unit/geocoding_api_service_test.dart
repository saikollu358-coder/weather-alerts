import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:weather_alerts/core/config/app_config.dart';
import 'package:weather_alerts/core/errors/location_exception.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/services/location/geocoding_api_service.dart';

const testConfig = AppConfig(
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

Map<String, dynamic> searchResults() => {
      'results': [
        {
          'id': 2950159,
          'name': 'Berlin',
          'latitude': 52.52437,
          'longitude': 13.41053,
          'elevation': 74.0,
          'feature_code': 'PPLC',
          'country_code': 'DE',
          'admin1': 'Land Berlin',
          'country': 'Germany',
          'population': 3546354,
          'timezone': 'Europe/Berlin',
        },
        {
          'id': 2938912,
          'name': 'Berlin',
          'latitude': 43.46867,
          'longitude': 12.77027,
          'elevation': 451.0,
          'feature_code': 'PPL',
          'country_code': 'US',
          'admin1': 'New Hampshire',
          'country': 'United States',
          'population': 10,
        },
      ],
    };

void main() {
  late GeocodingApiService service;
  late List<http.Request> requests;

  setUp(() {
    requests = [];
  });

  geocodingService(http.Response Function(http.Request request) respond) {
    final client = MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
    service = GeocodingApiService(
      config: testConfig,
      client: client,
      logger: AppLogger(enabled: false),
    );
  }

  test('searchPlaces parses the results into Places', () async {
    geocodingService(
      (request) => http.Response.bytes(
        utf8.encode(jsonEncode(searchResults())),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    final places = await service.searchPlaces('Berlin', limit: 2);

    expect(places, hasLength(2));
    final first = places.first;
    expect(first.id, 2950159);
    expect(first.name, 'Berlin');
    expect(first.latitude, 52.52437);
    expect(first.longitude, 13.41053);
    expect(first.region, 'Land Berlin');
    expect(first.country, 'Germany');
    expect(first.countryCode, 'DE');
    expect(first.population, 3546354);
    expect(first.timezone, 'Europe/Berlin');
    expect(first.displayName, 'Berlin, Land Berlin, Germany');
  });

  test('searchPlaces sends the expected query parameters', () async {
    geocodingService(
      (request) => http.Response('{"results":[]}', 200),
    );

    await service.searchPlaces('Rome', limit: 5);

    final request = requests.single;
    expect(request.url.path, '/v1/search');
    expect(request.url.queryParameters['name'], 'Rome');
    expect(request.url.queryParameters['count'], '5');
    expect(request.url.queryParameters['language'], 'en');
  });

  test('searchPlaces returns an empty list when there are no results', () async {
    geocodingService((request) => http.Response('{"results":[]}', 200));

    final places = await service.searchPlaces('zzzz');
    expect(places, isEmpty);
  });

  test('reverseGeocode returns the closest place', () async {
    geocodingService(
      (request) => http.Response.bytes(
        utf8.encode(jsonEncode(searchResults())),
        200,
      ),
    );

    final place = await service.reverseGeocode(52.5, 13.4);
    expect(place, isNotNull);
    expect(place!.name, 'Berlin');
  });

  test('reverseGeocode returns null when nothing is nearby', () async {
    geocodingService((request) => http.Response('{"results":[]}', 200));
    expect(await service.reverseGeocode(0, 0), isNull);
  });

  test('non-200 responses raise a user-safe geocoding error', () async {
    geocodingService((request) => http.Response('oops', 500));
    await expectLater(
      service.searchPlaces('Berlin'),
      throwsA(isA<GeocodingException>()),
    );
  });

  test('malformed JSON raises a user-safe geocoding error', () async {
    geocodingService((request) => http.Response('not json', 200));
    await expectLater(
      service.reverseGeocode(1, 1),
      throwsA(isA<GeocodingException>()),
    );
  });

  test('client failures raise a user-safe geocoding error', () async {
    geocodingService((_) => throw http.ClientException('offline'));
    await expectLater(
      service.searchPlaces('Berlin'),
      throwsA(isA<GeocodingException>()),
    );
  });
}