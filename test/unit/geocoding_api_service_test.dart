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

const openMeteoReverseConfig = AppConfig(
  environment: 'test',
  weatherApiBaseUrl: 'https://api.test.example/v1',
  geocodingApiBaseUrl: 'https://geocode.test.example/v1',
  reverseGeocodingApiBaseUrl: 'https://geocode.test.example/v1',
  reverseGeocodingProvider: ReverseGeocodingProvider.openMeteo,
  openWeatherApiKey: '',
  loggingEnabled: false,
  firebaseWebApiKey: '',
  firebaseWebAuthDomain: '',
  firebaseWebProjectId: '',
  firebaseWebStorageBucket: '',
  firebaseWebMessagingSenderId: '',
  firebaseWebAppId: '',
);

const disabledReverseConfig = AppConfig(
  environment: 'test',
  weatherApiBaseUrl: 'https://api.test.example/v1',
  geocodingApiBaseUrl: 'https://geocode.test.example/v1',
  reverseGeocodingApiBaseUrl: 'https://reverse.test.example/reverse',
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

/// Mirrors the real `reverse-geocode-client` payload, which is a flat object
/// rather than Open-Meteo's `results` array and has no `elevation` field.
Map<String, dynamic> bigDataCloudReverseBody() => {
      'latitude': 18.149,
      'longitude': 83.371,
      'continent': 'Asia',
      'continentCode': 'AS',
      'countryName': 'India',
      'countryCode': 'IN',
      'principalSubdivision': 'Andhra Pradesh',
      'principalSubdivisionCode': 'IN-AP',
      'city': 'Vizianagaram',
      'locality': 'Vizianagaram',
      'postcode': '',
      'lookupSource': 'coordinates',
    };

/// Encodes [body] as a UTF-8 JSON response.
///
/// The content-type header matters: without it `http.Response.bytes` defaults
/// to latin1 and mangles non-ASCII place names.
http.Response jsonResponse(Object body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
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

  geocodingService(
    http.Response Function(http.Request request) respond, [
    AppConfig config = testConfig,
  ]) {
    final client = MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
    service = GeocodingApiService(
      config: config,
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

  group('reverseGeocode (BigDataCloud)', () {
    test('maps the flat payload into a Place', () async {
      geocodingService((request) => jsonResponse(bigDataCloudReverseBody()));

      final place = await service.reverseGeocode(18.149, 83.371);

      expect(place, isNotNull);
      expect(place!.name, 'Vizianagaram');
      expect(place.region, 'Andhra Pradesh');
      expect(place.country, 'India');
      expect(place.countryCode, 'IN');
      expect(place.displayName, 'Vizianagaram, Andhra Pradesh, India');
    });

    test('sends coordinates and language to the reverse endpoint', () async {
      geocodingService((request) => jsonResponse(bigDataCloudReverseBody()));

      await service.reverseGeocode(18.149, 83.371);

      final request = requests.single;
      expect(request.url.host, 'reverse.test.example');
      expect(request.url.path, '/reverse');
      expect(request.url.queryParameters['latitude'], '18.149');
      expect(request.url.queryParameters['longitude'], '83.371');
      expect(request.url.queryParameters['localityLanguage'], 'en');
    });

    test('preserves the caller coordinates rather than the rounded ones',
        () async {
      geocodingService((request) => jsonResponse(bigDataCloudReverseBody()));

      final place = await service.reverseGeocode(18.149123, 83.371456);

      expect(place!.latitude, 18.149123);
      expect(place.longitude, 83.371456);
    });

    test('falls back through coarse areas when no city is reported', () async {
      geocodingService(
        (request) => jsonResponse({
          'countryName': 'Iceland',
          'principalSubdivision': 'Höfuðborgarsvæðið',
        }),
      );

      final place = await service.reverseGeocode(64.14, -21.94);

      expect(place!.name, 'Höfuðborgarsvæðið');
      expect(place.region, 'Höfuðborgarsvæðið');
    });

    test('returns null when the payload carries no usable name', () async {
      geocodingService((request) => http.Response('{}', 200));
      expect(await service.reverseGeocode(0, 0), isNull);
    });

    test('returns null on a non-200 response instead of throwing', () async {
      geocodingService((request) => http.Response('oops', 500));
      expect(await service.reverseGeocode(1, 1), isNull);
    });

    test('returns null on malformed JSON instead of throwing', () async {
      geocodingService((request) => http.Response('not json', 200));
      expect(await service.reverseGeocode(1, 1), isNull);
    });

    test('returns null when the client fails', () async {
      geocodingService((_) => throw http.ClientException('offline'));
      expect(await service.reverseGeocode(1, 1), isNull);
    });
  });

  group('reverseGeocode (Open-Meteo)', () {
    test('parses the results array', () async {
      geocodingService(
        (request) => jsonResponse(searchResults()),
        openMeteoReverseConfig,
      );

      final place = await service.reverseGeocode(52.5, 13.4);

      expect(place, isNotNull);
      expect(place!.name, 'Berlin');
      expect(requests.single.url.path, '/v1/reverse');
    });

    test('returns null when nothing is nearby', () async {
      geocodingService(
        (request) => http.Response('{"results":[]}', 200),
        openMeteoReverseConfig,
      );
      expect(await service.reverseGeocode(0, 0), isNull);
    });

    test('returns null on a non-200 response instead of throwing', () async {
      geocodingService(
        (request) => http.Response('oops', 404),
        openMeteoReverseConfig,
      );
      expect(await service.reverseGeocode(1, 1), isNull);
    });
  });

  group('reverseGeocode (disabled)', () {
    test('returns null without issuing a request', () async {
      geocodingService(
        (request) => http.Response('{}', 200),
        disabledReverseConfig,
      );
      expect(await service.reverseGeocode(1, 1), isNull);
      expect(requests, isEmpty);
    });
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
      service.searchPlaces('Berlin'),
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