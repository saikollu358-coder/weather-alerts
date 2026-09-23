import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/location_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../domain/entities/geo_position.dart';
import '../../../domain/enums/location_permission.dart';
import '../../../domain/services/location_service.dart';
import '../../../services/location/location_service_providers.dart';
import 'location_providers.dart';
import 'location_state.dart';

/// Owns location monitoring: permission resolution and live GPS position.
///
/// Widgets never touch the location plugin; they watch
/// [locationControllerProvider] and call [start] / [requestPermission].
class LocationController extends Notifier<LocationState> {
  StreamSubscription<GeoPosition>? _subscription;

  final String _unexpectedMessage = 'Could not start location monitoring.';

  @override
  LocationState build() {
    ref.onDispose(() => _subscription?.cancel());
    return const LocationState.initial();
  }

  /// Begins monitoring: checks OS service + permission, then streams fixes.
  Future<void> start() async {
    final service = ref.read(locationServiceProvider);
    final logger = ref.read(appLoggerProvider);
    if (_subscription != null) return;

    try {
      if (!await service.isServiceEnabled()) {
        _set(const LocationState(
          status: LocationStatus.unavailable,
          errorMessage: 'Location services are turned off. Turn them on to '
              'check the weather at your position.',
        ));
        return;
      }
      switch (await service.permissionStatus()) {
        case LocationPermissionStatus.granted:
          await _listen(service);
        case LocationPermissionStatus.denied:
          _set(const LocationState(status: LocationStatus.waitingPermission));
        case LocationPermissionStatus.deniedForever:
          _set(const LocationState(
            status: LocationStatus.deniedForever,
            errorMessage: 'Location permission was denied permanently. Allow '
                'location access in Settings to get weather alerts.',
          ));
      }
    } on AppException catch (e) {
      _set(LocationState(status: LocationStatus.error, errorMessage: e.message));
    } catch (e) {
      logger.warning('LocationController', 'start failed: ${e.runtimeType}');
      _set(LocationState(status: LocationStatus.error, errorMessage: _unexpectedMessage));
    }
  }

  /// Asks the user for location permission (after a prior denial).
  Future<bool> requestPermission() async {
    final service = ref.read(locationServiceProvider);
    final logger = ref.read(appLoggerProvider);
    _unsubscribe();
    _set(const LocationState(status: LocationStatus.waitingPermission));
    try {
      final result = await service.requestPermission();
      if (result == LocationPermissionStatus.granted) {
        await _listen(service);
        return true;
      }
      if (result == LocationPermissionStatus.deniedForever) {
        _set(const LocationState(
          status: LocationStatus.deniedForever,
          errorMessage: 'Location permission was denied permanently. Allow '
              'location access in Settings.',
        ));
        return false;
      }
      _set(const LocationState(
        status: LocationStatus.denied,
        errorMessage: 'Location permission was denied.',
      ));
      return false;
    } on AppException catch (e) {
      _set(LocationState(status: LocationStatus.error, errorMessage: e.message));
      return false;
    } catch (e) {
      logger.warning(
          'LocationController', 'permission request failed: ${e.runtimeType}');
      _set(LocationState(status: LocationStatus.error, errorMessage: _unexpectedMessage));
      return false;
    }
  }

  /// Opens OS app settings (used from the deniedForever state).
  Future<void> openSettings() async {
    final service = ref.read(locationServiceProvider);
    try {
      await service.openAppSettings();
    } on AppException catch (e) {
      _set(LocationState(status: LocationStatus.error, errorMessage: e.message));
    }
  }

  /// Stops receiving updates and returns to the initial state.
  void stop() {
    _unsubscribe();
    _set(const LocationState.initial());
  }

  Future<void> _listen(LocationService service) async {
    final known = await service.lastKnownPosition();
    if (known != null) {
      _set(LocationState(status: LocationStatus.ready, position: known));
    } else {
      _set(const LocationState(status: LocationStatus.ready));
    }
    _subscription = service
        .positionStream()
        .listen(
          (position) => _set(
            LocationState(status: LocationStatus.ready, position: position),
          ),
          onError: (Object e, StackTrace st) {
            if (e is LocationPermissionDeniedException) {
              _set(const LocationState(
                status: LocationStatus.denied,
                errorMessage: 'Location permission was revoked.',
              ));
            } else {
              _set(LocationState(
                status: LocationStatus.error,
                errorMessage: e is AppException
                    ? e.message
                    : 'Location updates stopped unexpectedly.',
              ));
            }
          },
        );
  }

  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _set(LocationState next) {
    if (!ref.mounted) {
      _subscription?.cancel();
      _subscription = null;
      return;
    }
    state = next;
  }
}