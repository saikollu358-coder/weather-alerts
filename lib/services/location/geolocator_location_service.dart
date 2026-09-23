import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/location_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/geo_position.dart';
import '../../domain/enums/location_permission.dart';
import '../../domain/services/location_service.dart';

/// [LocationService] backed by the `geolocator` plugin.
///
/// The [GeolocatorPlatform] is injectable so unit tests can replace it with a
/// fake without touching platform channels.
class GeolocatorLocationService implements LocationService {
  GeolocatorLocationService({required this.logger, GeolocatorPlatform? platform})
      : _platform = platform ?? GeolocatorPlatform.instance;

  final AppLogger logger;
  final GeolocatorPlatform _platform;

  @override
  Future<bool> isServiceEnabled() async {
    try {
      return await _platform.isLocationServiceEnabled();
    } on AppException {
      rethrow;
    } catch (e) {
      throw LocationUnavailableException(cause: e);
    }
  }

  @override
  Future<LocationPermissionStatus> permissionStatus() =>
      _resolve(() => _platform.checkPermission());

  @override
  Future<LocationPermissionStatus> requestPermission() =>
      _resolve(() => _platform.requestPermission());

  Future<LocationPermissionStatus> _resolve(
    Future<LocationPermission> Function() request,
  ) async {
    try {
      return _mapPermission(await request());
    } on AppException {
      rethrow;
    } catch (e) {
      logger.warning('GeolocatorLocationService',
          'permission check failed: ${e.runtimeType}');
      throw LocationUnavailableException(cause: e);
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await _platform.openAppSettings();
    } on AppException {
      rethrow;
    } catch (e) {
      logger.warning(
          'GeolocatorLocationService', 'openAppSettings failed: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<GeoPosition> currentPosition({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final position = await _platform
          .getCurrentPosition(
            locationSettings: LocationSettings(
accuracy: LocationAccuracy.high,
              timeLimit: timeout,
            ),
          )
          .timeout(timeout);
      return _toPosition(position);
    } on AppException {
      rethrow;
    } on PermissionDeniedException catch (e) {
      logger.warning('GeolocatorLocationService', 'permission denied');
      throw LocationPermissionDeniedException(cause: e);
    } on LocationServiceDisabledException catch (e) {
      logger.warning('GeolocatorLocationService', 'service disabled');
      throw LocationUnavailableException(cause: e);
    } catch (e) {
      logger.warning(
          'GeolocatorLocationService', 'current position failed: ${e.runtimeType}');
      throw LocationUnavailableException(cause: e);
    }
  }

  @override
  Future<GeoPosition?> lastKnownPosition() async {
    try {
      final position = await _platform.getLastKnownPosition();
      return position == null ? null : _toPosition(position);
    } on AppException {
      rethrow;
    } catch (e) {
      logger.warning(
          'GeolocatorLocationService', 'last known position failed: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Stream<GeoPosition> positionStream({
    Duration? timeLimit,
    double distanceFilter = 0,
  }) {
    return _platform
        .getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: timeLimit,
            distanceFilter: distanceFilter.round(),
          ),
        )
        .transform(
          StreamTransformer.fromHandlers(
            handleData: (Position position, EventSink<GeoPosition> sink) =>
                sink.add(_toPosition(position)),
            handleError: (Object error, StackTrace stack, EventSink<GeoPosition> sink) {
              sink.addError(_toAppError(error), stack);
            },
          ),
        );
  }

  Object _toAppError(Object error) {
    if (error is AppException) return error;
    if (error is PermissionDeniedException) {
      return const LocationPermissionDeniedException();
    }
    return LocationUnavailableException(cause: error);
  }

  static LocationPermissionStatus _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationPermissionStatus.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.denied;
    }
  }

  static GeoPosition _toPosition(Position position) => GeoPosition(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        timestamp: position.timestamp,
      );
}