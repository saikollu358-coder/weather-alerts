/// Where a monitored location came from.
enum MonitoredLocationSource { gps, manual }

/// A user-monitored location persisted locally.
class MonitoredLocationRecord {
  const MonitoredLocationRecord({
    this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.source = MonitoredLocationSource.gps,
    this.isMonitored = false,
    this.isPrimary = false,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.lastUsedAtUtc,
  });

  /// Auto-increment database id; null before first persistence.
  final int? id;

  final String name;
  final double latitude;
  final double longitude;

  /// GPS accuracy in meters, when known.
  final double? accuracy;

  final MonitoredLocationSource source;

  /// Whether this location is currently being monitored.
  final bool isMonitored;

  /// Whether this location is the primary/monitored default.
  final bool isPrimary;

  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  /// Last time this location was selected for monitoring.
  final DateTime? lastUsedAtUtc;

  /// Stable key matching the persisted `location_key` format used by the
  /// weather cache and alerts (`lat,lng`).
  String get locationKey => '$latitude,$longitude';

  MonitoredLocationRecord copyWith({
    int? id,
    bool clearId = false,
    String? name,
    double? latitude,
    double? longitude,
    double? accuracy,
    bool clearAccuracy = false,
    MonitoredLocationSource? source,
    bool? isMonitored,
    bool? isPrimary,
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
    DateTime? lastUsedAtUtc,
    bool clearLastUsed = false,
  }) {
    return MonitoredLocationRecord(
      id: clearId ? null : (id ?? this.id),
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: clearAccuracy ? null : (accuracy ?? this.accuracy),
      source: source ?? this.source,
      isMonitored: isMonitored ?? this.isMonitored,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      lastUsedAtUtc: clearLastUsed ? null : (lastUsedAtUtc ?? this.lastUsedAtUtc),
    );
  }

  @override
  String toString() =>
      'MonitoredLocationRecord($name, $latitude, $longitude, primary: $isPrimary)';
}