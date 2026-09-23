import '../enums/location_permission.dart';
import '../entities/geo_position.dart';

/// Device location boundary (GPS).
///
/// Implementations wrap the platform location plugin; the interface stays
/// free of plugin types so the domain and UI depend only on app types.
abstract interface class LocationService {
  /// Whether the device location services are enabled at the OS level.
  Future<bool> isServiceEnabled();

  /// Current location authorization status.
  Future<LocationPermissionStatus> permissionStatus();

  /// Prompts the user for location permission (no-op when already decided).
  Future<LocationPermissionStatus> requestPermission();

  /// Opens the OS app-settings screen. Returns false when unsupported.
  Future<bool> openAppSettings();

  /// One-shot high-accuracy fix within [timeout].
  Future<GeoPosition> currentPosition({
    Duration timeout = const Duration(seconds: 30),
  });

  /// The most recent cached fix, when the platform has one.
  Future<GeoPosition?> lastKnownPosition();

  /// Continuous position updates honoring [distanceFilter] (meters).
  Stream<GeoPosition> positionStream({
    Duration? timeLimit,
    double distanceFilter = 0,
  });
}