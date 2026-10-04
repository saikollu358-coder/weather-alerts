import 'geo_position.dart';

/// The device's own position plus a resolved label.
///
/// This is the app's only location concept: there are no user-saved or
/// user-selected places. The label is a reverse-geocoded place name when one
/// could be resolved, and a coordinate string otherwise, so it is never empty.
class CurrentLocation {
  const CurrentLocation({
    required this.position,
    required this.label,
    required this.capturedAtUtc,
  });

  /// The GPS fix this location was derived from.
  final GeoPosition position;

  /// Human-readable place name, or a coordinate fallback.
  final String label;

  /// When the fix was captured (UTC).
  final DateTime capturedAtUtc;

  double get latitude => position.latitude;

  double get longitude => position.longitude;

  /// Stable key matching the weather cache and alert `location_key` format.
  String get locationKey => position.locationKey;

  /// Whether the label came from a reverse geocoder rather than the
  /// coordinate fallback.
  bool get hasResolvedName => !_looksLikeCoordinates;

  bool get _looksLikeCoordinates => _coordinatePattern.hasMatch(label);

  /// Builds a location whose label is the coordinate fallback, used whenever
  /// reverse geocoding is unavailable.
  ///
  /// Coordinates are quantized to [coordinatePrecision] decimal places. GPS
  /// accuracy is typically 5-50 m while one unit at 4 dp is roughly 11 m, so
  /// this stays within measurement noise — but it also means the coordinate the
  /// user sees, the coordinate the weather request uses, the cache key and the
  /// push-routing key are all the same value instead of drifting on every
  /// jittered fix.
  factory CurrentLocation.fromPosition(
    GeoPosition position, {
    String? label,
    DateTime? capturedAtUtc,
  }) {
    final snapped = GeoPosition(
      latitude: _round(position.latitude),
      longitude: _round(position.longitude),
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      timestamp: position.timestamp,
    );
    final resolved = label?.trim();
    return CurrentLocation(
      position: snapped,
      label: (resolved != null && resolved.isNotEmpty)
          ? resolved
          : coordinateLabel(snapped),
      capturedAtUtc: capturedAtUtc ?? position.timestamp,
    );
  }

  /// Decimal places retained for a snapped coordinate.
  static const int coordinatePrecision = 4;

  static double _round(double value) =>
      (value * _precisionFactor).roundToDouble() / _precisionFactor;

  static final double _precisionFactor =
      _pow10(coordinatePrecision);

  static double _pow10(int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  /// Coordinate fallback label, e.g. `18.149, 83.371`.
  static String coordinateLabel(GeoPosition position) =>
      '${position.latitude.toStringAsFixed(3)}, '
      '${position.longitude.toStringAsFixed(3)}';

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (position.accuracy != null) 'accuracy': position.accuracy,
        if (position.altitude != null) 'altitude': position.altitude,
        if (position.speed != null) 'speed': position.speed,
        'fixTimestampUtc': position.timestamp.toIso8601String(),
        'label': label,
        'capturedAtUtc': capturedAtUtc.toIso8601String(),
      };

  /// Rebuilds a location from [toJson], or null when the payload is absent or
  /// unusable (a corrupt entry must never crash a background task).
  static CurrentLocation? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final lat = (json['latitude'] as num?)?.toDouble();
    final lng = (json['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final fixAt = DateTime.tryParse(json['fixTimestampUtc'] as String? ?? '');
    final capturedAt = DateTime.tryParse(json['capturedAtUtc'] as String? ?? '');
    final fallbackTime = capturedAt ?? DateTime.now().toUtc();

    return CurrentLocation.fromPosition(
      GeoPosition(
        latitude: lat,
        longitude: lng,
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        altitude: (json['altitude'] as num?)?.toDouble(),
        speed: (json['speed'] as num?)?.toDouble(),
        timestamp: fixAt ?? fallbackTime,
      ),
      label: json['label'] as String?,
      capturedAtUtc: capturedAt ?? fallbackTime,
    );
  }

  @override
  String toString() => 'CurrentLocation($label, $latitude, $longitude)';
}

/// Matches a `12.345, 67.890` style coordinate label.
final RegExp _coordinatePattern = RegExp(r'^-?\d+\.\d+,\s*-?\d+\.\d+$');