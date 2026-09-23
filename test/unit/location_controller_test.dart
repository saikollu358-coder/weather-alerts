import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/errors/location_exception.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/domain/entities/geo_position.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
import 'package:weather_alerts/domain/services/location_service.dart';
import 'package:weather_alerts/features/location/application/location_providers.dart';
import 'package:weather_alerts/features/location/application/location_state.dart';
import 'package:weather_alerts/services/location/location_service_providers.dart';

class FakeLocationService implements LocationService {
  bool serviceEnabled = true;
  LocationPermissionStatus permission = LocationPermissionStatus.granted;
  GeoPosition? lastKnown;
  bool openAppSettingsResult = true;
  final positionController = StreamController<GeoPosition>.broadcast();

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> permissionStatus() async => permission;

  @override
  Future<LocationPermissionStatus> requestPermission() async => permission;

  @override
  Future<bool> openAppSettings() async => openAppSettingsResult;

  @override
  Future<GeoPosition> currentPosition({
    Duration timeout = const Duration(seconds: 30),
  }) async =>
      lastKnown ??
      GeoPosition(
        latitude: 42.0,
        longitude: -71.0,
        timestamp: DateTime.utc(2026, 1, 1),
      );

  @override
  Future<GeoPosition?> lastKnownPosition() async => lastKnown;

  @override
  Stream<GeoPosition> positionStream({
    Duration? timeLimit,
    double distanceFilter = 0,
  }) =>
      positionController.stream;
}

GeoPosition pos(double latitude) => GeoPosition(
      latitude: latitude,
      longitude: 10.0,
      timestamp: DateTime.utc(2026, 1, 1),
    );

void main() {
  late FakeLocationService fake;
  late ProviderContainer container;

  setUp(() {
    fake = FakeLocationService();
    container = ProviderContainer(
      overrides: [
        appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
        locationServiceProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(fake.positionController.close);
  });

  LocationState state() => container.read(locationControllerProvider);

  Future<void> settle() => pumpEventQueue();

  test('starts in the unknown state', () {
    expect(state().status, LocationStatus.unknown);
  });

  test('start with granted permission publishes the last known fix', () async {
    fake.lastKnown = pos(48.85);

    await container.read(locationControllerProvider.notifier).start();
    await settle();

    expect(state().status, LocationStatus.ready);
    expect(state().position!.latitude, 48.85);
  });

  test('start streams live position updates into the state', () async {
    await container.read(locationControllerProvider.notifier).start();
    await settle();

    fake.positionController.add(pos(51.5));

    await settle();
    expect(state().status, LocationStatus.ready);
    expect(state().position!.latitude, 51.5);
  });

  test('start reports unavailable when OS location services are off', () async {
    fake.serviceEnabled = false;

    await container.read(locationControllerProvider.notifier).start();
    await settle();

    expect(state().status, LocationStatus.unavailable);
  });

  test('start with denied permission waits for a prompt', () async {
    fake.permission = LocationPermissionStatus.denied;

    await container.read(locationControllerProvider.notifier).start();
    await settle();

    expect(state().status, LocationStatus.waitingPermission);
  });

  test('start with deniedForever guidance asks for settings', () async {
    fake.permission = LocationPermissionStatus.deniedForever;

    await container.read(locationControllerProvider.notifier).start();
    await settle();

    expect(state().status, LocationStatus.deniedForever);
    expect(state().errorMessage, isNotNull);
  });

  test('requestPermission grants and starts monitoring', () async {
    fake.permission = LocationPermissionStatus.denied;
    await container.read(locationControllerProvider.notifier).start();
    await settle();
    expect(state().status, LocationStatus.waitingPermission);

    fake.permission = LocationPermissionStatus.granted;
    final granted =
        await container.read(locationControllerProvider.notifier).requestPermission();
    await settle();

    expect(granted, isTrue);
    expect(state().status, LocationStatus.ready);
  });

  test('requestPermission stays denied when the user declines', () async {
    fake.permission = LocationPermissionStatus.denied;
    final granted =
        await container.read(locationControllerProvider.notifier).requestPermission();
    await settle();

    expect(granted, isFalse);
    expect(state().status, LocationStatus.denied);
  });

  test('requestPermission reports deniedForever', () async {
    fake.permission = LocationPermissionStatus.deniedForever;
    final granted =
        await container.read(locationControllerProvider.notifier).requestPermission();
    await settle();

    expect(granted, isFalse);
    expect(state().status, LocationStatus.deniedForever);
  });

  test('a permission revocation on the stream marks denied', () async {
    await container.read(locationControllerProvider.notifier).start();
    await settle();

    fake.positionController
        .addError(const LocationPermissionDeniedException(), StackTrace.empty);
    await settle();

    expect(state().status, LocationStatus.denied);
    expect(state().errorMessage, isNotNull);
  });

  test('stop cancels monitoring and resets to initial', () async {
    await container.read(locationControllerProvider.notifier).start();
    await settle();
    expect(state().status, LocationStatus.ready);

    container.read(locationControllerProvider.notifier).stop();
    await settle();

    expect(state().status, LocationStatus.unknown);
  });
}