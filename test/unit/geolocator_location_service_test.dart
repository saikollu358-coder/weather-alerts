import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:weather_alerts/core/errors/location_exception.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/domain/entities/geo_position.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
import 'package:weather_alerts/services/location/geolocator_location_service.dart';

class FakeGeolocatorPlatform extends GeolocatorPlatform {
  FakeGeolocatorPlatform({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.currentPosition,
  });

  bool serviceEnabled;
  LocationPermission permission;
  Position? currentPosition;
  Object? currentPositionError;
  bool openAppSettingsResult = true;
  final positionController = StreamController<Position>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<bool> openAppSettings() async => openAppSettingsResult;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
    LocationSettings? locationSettings,
  }) async =>
      currentPosition;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    final error = currentPositionError;
    if (error != null) throw error;
    return currentPosition!;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      positionController.stream;
}

Position makePosition({
  double latitude = 40.7128,
  double longitude = -74.006,
  double accuracy = 6.0,
}) =>
    Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: DateTime.utc(2026, 1, 2, 3, 4),
      accuracy: accuracy,
      altitude: 12.5,
      altitudeAccuracy: 3.0,
      heading: 90.0,
      headingAccuracy: 2.0,
      speed: 1.2,
      speedAccuracy: 0.5,
      isMocked: false,
    );

void main() {
  late FakeGeolocatorPlatform platform;
  late GeolocatorLocationService service;

  setUp(() {
    platform = FakeGeolocatorPlatform(currentPosition: makePosition());
    service = GeolocatorLocationService(
      logger: AppLogger(enabled: false),
      platform: platform,
    );
  });

  tearDown(() async {
    await platform.positionController.close();
  });

  test('isServiceEnabled reflects the platform state', () async {
    expect(await service.isServiceEnabled(), isTrue);
    platform.serviceEnabled = false;
    expect(await service.isServiceEnabled(), isFalse);
  });

  group('permission mapping', () {
    Future<LocationPermissionStatus> status(LocationPermission p) async {
      platform.permission = p;
      return service.permissionStatus();
    }

    test('whileInUse and always map to granted', () async {
      expect(await status(LocationPermission.whileInUse), equals(LocationPermissionStatus.granted));
      expect(await status(LocationPermission.always), equals(LocationPermissionStatus.granted));
    });

    test('denied and unableToDetermine map to denied', () async {
      expect(await status(LocationPermission.denied), equals(LocationPermissionStatus.denied));
      expect(
        await status(LocationPermission.unableToDetermine),
        equals(LocationPermissionStatus.denied),
      );
    });

    test('deniedForever maps to deniedForever', () async {
      expect(
        await status(LocationPermission.deniedForever),
        equals(LocationPermissionStatus.deniedForever),
      );
    });

    test('requestPermission returns the mapped result', () async {
      platform.permission = LocationPermission.whileInUse;
      expect(await service.requestPermission(), equals(LocationPermissionStatus.granted));
    });
  });

  test('currentPosition maps to a GeoPosition preserving metadata', () async {
    final geo = await service.currentPosition();
    expect(geo.latitude, 40.7128);
    expect(geo.longitude, -74.006);
    expect(geo.accuracy, 6.0);
    expect(geo.altitude, 12.5);
    expect(geo.speed, 1.2);
    expect(geo.timestamp, DateTime.utc(2026, 1, 2, 3, 4));
  });

  test('currentPosition maps permission denial to a user-safe error', () async {
    platform.currentPositionError = const PermissionDeniedException('nope');
    await expectLater(
      service.currentPosition(),
      throwsA(isA<LocationPermissionDeniedException>()),
    );
  });

  test('currentPosition maps disabled service to unavailable', () async {
    platform.currentPositionError = const LocationServiceDisabledException();
    await expectLater(
      service.currentPosition(),
      throwsA(isA<LocationUnavailableException>()),
    );
  });

  test('currentPosition maps unexpected failures to unavailable', () async {
    platform.currentPositionError = StateError('boom');
    await expectLater(
      service.currentPosition(),
      throwsA(isA<LocationUnavailableException>()),
    );
  });

  test('lastKnownPosition returns null when the platform has none', () async {
    platform.currentPosition = null;
    expect(await service.lastKnownPosition(), isNull);
  });

  test('lastKnownPosition maps a cached fix', () async {
    final geo = await service.lastKnownPosition();
    expect(geo, isNotNull);
    expect(geo!.latitude, 40.7128);
  });

  test('positionStream maps every event to a GeoPosition', () async {
    final received = <GeoPosition>[];
    final sub = service.positionStream().listen(received.add);
    platform.positionController.add(makePosition(latitude: 41.0));
    platform.positionController.add(makePosition(latitude: 42.0, longitude: 5.0));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(received, hasLength(2));
    expect(received[0].latitude, 41.0);
    expect(received[1].longitude, 5.0);
  });

  test('positionStream maps permission errors to app errors', () async {
    final errors = <Object>[];
    final sub = service
        .positionStream()
        .listen((_) {}, onError: (Object e, StackTrace st) => errors.add(e));
    platform.positionController.addError(const PermissionDeniedException('denied'));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(errors, hasLength(1));
    expect(errors.single, isA<LocationPermissionDeniedException>());
  });

  test('openAppSettings bubbles the platform result and failures to false',
      () async {
    expect(await service.openAppSettings(), isTrue);
    platform.openAppSettingsResult = false;
    expect(await service.openAppSettings(), isFalse);
  });
}