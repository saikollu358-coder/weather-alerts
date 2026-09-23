import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/errors/app_exception.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/datasources/local/local_database_io.dart';
import 'package:weather_alerts/data/repositories/monitored_location_repository_impl.dart';
import 'package:weather_alerts/domain/entities/monitored_location_record.dart';

import '../helpers/test_database.dart';

void main() {
  late SqfliteDatabase db;
  late Directory dir;
  late MonitoredLocationRepositoryImpl repository;

  setUp(() async {
    final created = await createTestDatabase();
    db = created.$1;
    dir = created.$2;
    repository = MonitoredLocationRepositoryImpl(
      db: db,
      logger: AppLogger(enabled: false),
    );
  });

  tearDown(() async => teardownTestDatabase(db, dir));

  MonitoredLocationRecord location({
    String name = 'Home',
    double latitude = 40.712, // numeric key avoids analyzer lint
    double longitude = -74.006,
    double? accuracy = 25,
  }) =>
      MonitoredLocationRecord(
        name: name,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        source: MonitoredLocationSource.gps,
        createdAtUtc: DateTime.utc(2026, 1, 1),
        updatedAtUtc: DateTime.utc(2026, 1, 1),
      );

  test('adds a location and reads it back by id', () async {
    final id = await repository.addLocation(location());
    expect(id, greaterThan(0));

    final loaded = await repository.locationById(id);
    expect(loaded, isNotNull);
    expect(loaded!.name, 'Home');
    expect(loaded.latitude, 40.712);
    expect(loaded.accuracy, 25);
    expect(loaded.source, MonitoredLocationSource.gps);
  });

  test('finds a location by exact coordinates', () async {
    await repository.addLocation(location());
    final found = await repository.byCoordinates(40.712, -74.006);
    expect(found, isNotNull);
    expect(found!.name, 'Home');
  });

  test('rejects duplicate coordinates', () async {
    await repository.addLocation(location(name: 'A'));
    await expectLater(
      repository.addLocation(location(name: 'B')),
      throwsA(isA<AppException>()),
    );
  });

  test('setPrimary makes exactly one location primary and monitored',
      () async {
    final first = await repository.addLocation(location(name: 'A'));
    final second = await repository.addLocation(
      location(name: 'B', latitude: 51.5, longitude: -0.12),
    );

    await repository.setPrimary(second);

    final primary = await repository.primaryLocation();
    expect(primary!.id, second);
    expect(primary.isMonitored, isTrue);
    expect(primary.lastUsedAtUtc, isNotNull);

    final all = await repository.allLocations();
    expect(all.where((l) => l.isPrimary), hasLength(1));
    // (still asserting first is not primary)
    expect((await repository.locationById(first))!.isPrimary, isFalse);
  });

  test('setMonitored toggles the monitoring flag', () async {
    final id = await repository.addLocation(location());
    await repository.setMonitored(id, monitored: true);

    final monitored = await repository.monitoredLocation();
    expect(monitored, isNotNull);
    expect(monitored!.id, id);

    await repository.setMonitored(id, monitored: false);
    expect(await repository.monitoredLocation(), isNull);
  });

  test('updateLocation changes mutable fields in place', () async {
    final id = await repository.addLocation(location());
    final loaded = await repository.locationById(id);
    await repository.updateLocation(
      loaded!.copyWith(name: 'Office'),
    );

    final updated = await repository.locationById(id);
    expect(updated!.name, 'Office');
    expect(updated.latitude, 40.712);
  });

  test('touchLastUsed refreshes the last-used timestamp', () async {
    final id = await repository.addLocation(location());
    final at = DateTime.utc(2026, 2, 1);
    await repository.touchLastUsed(id, at: at);

    final loaded = await repository.locationById(id);
    expect(loaded!.lastUsedAtUtc, at);
  });

  test('removeLocation deletes the location', () async {
    final id = await repository.addLocation(location());
    await repository.removeLocation(id);
    expect(await repository.locationById(id), isNull);
  });

  test('allLocations orders most recently used first', () async {
    final first = await repository.addLocation(location(name: 'A'));
    final second = await repository.addLocation(
      location(name: 'B', latitude: 51.5, longitude: -0.12),
    );
    await repository.touchLastUsed(
      second,
      at: DateTime.utc(2026, 1, 2),
    );
    // First location has never been used; second was used more recently.
    final all = await repository.allLocations();
    expect(all.first.id, second);
    expect(all.last.id, first);
  });
}