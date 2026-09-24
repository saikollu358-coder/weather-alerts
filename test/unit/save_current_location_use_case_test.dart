import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/errors/app_exception.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/domain/entities/geo_position.dart';
import 'package:weather_alerts/domain/entities/monitored_location_record.dart';
import 'package:weather_alerts/domain/entities/place.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
import 'package:weather_alerts/domain/repositories/monitored_location_repository.dart';
import 'package:weather_alerts/domain/services/geocoding_service.dart';
import 'package:weather_alerts/domain/services/location_service.dart';
import 'package:weather_alerts/features/location/application/save_current_location_use_case.dart';

class FakeLocationService implements LocationService {
  FakeLocationService(this.fix);

  final GeoPosition fix;
  int currentPositionCalls = 0;

  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<LocationPermissionStatus> permissionStatus() async =>
      LocationPermissionStatus.granted;

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<GeoPosition> currentPosition({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    currentPositionCalls++;
    return fix;
  }

  @override
  Future<GeoPosition?> lastKnownPosition() async => fix;

  @override
  Stream<GeoPosition> positionStream({
    Duration? timeLimit,
    double distanceFilter = 0,
  }) =>
      const Stream.empty();
}

class FakeGeocodingService implements GeocodingService {
  FakeGeocodingService({this.place, this.error});

  final Place? place;
  final Object? error;

  @override
  Future<List<Place>> searchPlaces(String query, {int limit = 10}) async => [];

  @override
  Future<Place?> reverseGeocode(double latitude, double longitude) async {
    final err = error;
    if (err != null) throw err;
    return place;
  }
}

class DuplicateLocationException extends AppException {
  const DuplicateLocationException()
      : super(message: 'A location already exists there.');
}

class InMemoryMonitoredLocations implements MonitoredLocationRepository {
  final _records = <MonitoredLocationRecord>[];
  int _nextId = 1;

  @override
  Future<List<MonitoredLocationRecord>> allLocations() async => List.of(_records);

  @override
  Future<MonitoredLocationRecord?> locationById(int id) async {
    for (final record in _records) {
      if (record.id == id) return record;
    }
    return null;
  }

  @override
  Future<MonitoredLocationRecord?> byCoordinates(
      double latitude, double longitude) async {
    for (final record in _records) {
      if (record.latitude == latitude && record.longitude == longitude) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<int> addLocation(MonitoredLocationRecord record) async {
    final existing = await byCoordinates(record.latitude, record.longitude);
    if (existing != null) {
      throw const DuplicateLocationException();
    }
    final id = _nextId++;
    _records.add(record.copyWith(id: id));
    return id;
  }

  @override
  Future<void> updateLocation(MonitoredLocationRecord record) async {}

  @override
  Future<void> removeLocation(int id) async {}

  @override
  Future<void> setMonitored(int id, {required bool monitored}) async {}

  @override
  Future<void> setPrimary(int id) async {}

  @override
  Future<MonitoredLocationRecord?> primaryLocation() async => null;

  @override
  Future<MonitoredLocationRecord?> monitoredLocation() async => null;

  @override
  Future<void> touchLastUsed(int id, {DateTime? at}) async {}

  @override
  Future<void> clear() async {
    _records.clear();
  }
}

void main() {
  final positioned = GeoPosition(
    latitude: 40.7128,
    longitude: -74.006,
    accuracy: 12.5,
    timestamp: DateTime.utc(2026, 1, 1),
  );

  const nyc = Place(
    name: 'New York',
    latitude: 40.7128,
    longitude: -74.006,
    region: 'New York',
    country: 'United States',
    countryCode: 'US',
  );

  SaveCurrentLocationUseCase build({
    GeocodingService? geocoding,
    MonitoredLocationRepository? locations,
  }) {
    return SaveCurrentLocationUseCase(
      locationService: FakeLocationService(positioned),
      geocodingService: geocoding ?? FakeGeocodingService(),
      locations: locations ?? InMemoryMonitoredLocations(),
      logger: AppLogger(enabled: false),
    );
  }

  test('saves the current position as a GPS-sourced location', () async {
    final repo = InMemoryMonitoredLocations();
    final useCase = build(locations: repo);

    final saved = await useCase.run(name: 'Near Home');

    expect(saved.name, 'Near Home');
    expect(saved.latitude, 40.7128);
    expect(saved.longitude, -74.006);
    expect(saved.accuracy, 12.5);
    expect(saved.source, MonitoredLocationSource.gps);
    expect(saved.id, isNotNull);
    expect(await repo.allLocations(), hasLength(1));
  });

  test('fills the name via reverse geocoding when not provided', () async {
    final useCase = build(geocoding: FakeGeocodingService(place: nyc));

    final saved = await useCase.run();

    expect(saved.name, 'New York, New York, United States');
  });

  test('falls back to a coordinates label when reverse geocoding has no result',
      () async {
    final useCase = build(geocoding: FakeGeocodingService());

    final saved = await useCase.run();

    expect(saved.name, '40.713, -74.006');
  });

  test('falls back gracefully when reverse geocoding fails', () async {
    final useCase = build(
      geocoding: FakeGeocodingService(error: StateError('offline')),
    );

    final saved = await useCase.run();

    expect(saved.name, '40.713, -74.006');
  });

  test('surfaces duplicate-coordinate rejection from the repository', () async {
    final repo = InMemoryMonitoredLocations();
    await repo.addLocation(
      MonitoredLocationRecord(
        name: 'Existing',
        latitude: 40.7128,
        longitude: -74.006,
        source: MonitoredLocationSource.manual,
        createdAtUtc: DateTime.utc(2026, 1, 1),
        updatedAtUtc: DateTime.utc(2026, 1, 1),
      ),
    );
    final useCase = build(
      geocoding: FakeGeocodingService(place: nyc),
      locations: repo,
    );

    await expectLater(useCase.run(), throwsA(isA<AppException>()));
  });

  test('captures exactly one GPS fix per run', () async {
    final service = FakeLocationService(positioned);
    final useCase = SaveCurrentLocationUseCase(
      locationService: service,
      geocodingService: FakeGeocodingService(),
      locations: InMemoryMonitoredLocations(),
      logger: AppLogger(enabled: false),
    );

    await useCase.run();
    expect(service.currentPositionCalls, 1);
  });
}