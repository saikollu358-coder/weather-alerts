import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/domain/entities/geo_position.dart';
import 'package:weather_alerts/domain/entities/place.dart';

GeoPosition position(double latitude, double longitude) => GeoPosition(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('GeoPosition', () {
    test('accepts valid coordinates', () {
      final valid = position(12.3, 45.6);
      expect(valid.isValid, isTrue);
      expect(valid.locationKey, '12.3,45.6');
    });

    test('rejects out-of-range coordinates', () {
      expect(position(91, 0).isValid, isFalse);
      expect(position(0, 181).isValid, isFalse);
      expect(position(-91, 0).isValid, isFalse);
      expect(position(0, -181).isValid, isFalse);
    });
  });

  group('Place', () {
    test('displayName joins name, region and country', () {
      const place = Place(
        name: 'Berlin',
        latitude: 52.5,
        longitude: 13.4,
        region: 'Land Berlin',
        country: 'Germany',
      );
      expect(place.displayName, 'Berlin, Land Berlin, Germany');
    });

    test('displayName omits missing parts', () {
      const nameOnly = Place(name: 'Kyiv', latitude: 50.4, longitude: 30.5);
      expect(nameOnly.displayName, 'Kyiv');

      const noName = Place(
        name: 'New York',
        latitude: 40.7,
        longitude: -74.0,
        country: 'United States',
      );
      expect(noName.displayName, 'New York, United States');
    });

    test('fromJson maps Open-Meteo fields', () {
      final place = Place.fromJson({
        'id': 2950159,
        'name': 'Berlin',
        'latitude': 52.52437,
        'longitude': 13.41053,
        'elevation': 74,
        'country_code': 'DE',
        'admin1': 'Land Berlin',
        'country': 'Germany',
        'population': 3546354,
        'timezone': 'Europe/Berlin',
      });

      expect(place.id, 2950159);
      expect(place.name, 'Berlin');
      expect(place.latitude, 52.52437);
      expect(place.countryCode, 'DE');
      expect(place.region, 'Land Berlin');
      expect(place.population, 3546354);
      expect(place.elevation, 74.0);
      expect(place.timezone, 'Europe/Berlin');
    });

    test('fromJson tolerates missing optional fields', () {
      final place = Place.fromJson({'latitude': 1, 'longitude': 2});
      expect(place.id, isNull);
      expect(place.name, 'Unknown place');
      expect(place.region, isNull);
      expect(place.country, isNull);
    });
  });
}