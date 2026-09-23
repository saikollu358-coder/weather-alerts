/// A GPS position resolved by the device.
class GeoPosition {
  const GeoPosition({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in meters, when reported by the platform.
  final double? accuracy;

  /// Altitude above mean sea level in meters, when reported.
  final double? altitude;

  /// Ground speed in meters per second, when reported.
  final double? speed;

  /// When the fix was produced (UTC).
  final DateTime timestamp;

  /// Whether the coordinates are within valid geographic bounds.
  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Stable key matching the persisted `location_key` format used by the
  /// weather cache and monitored locations.
  String get locationKey => '$latitude,$longitude';

  @override
  String toString() => 'GeoPosition($latitude, $longitude)';
}