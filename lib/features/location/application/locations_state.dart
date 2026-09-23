import '../../../domain/entities/monitored_location_record.dart';

/// High-level locations-tab phases.
enum LocationsStatus {
  /// Initial load in progress.
  loading,

  /// The list is populated from the repository.
  ready,

  /// The most recent load failed; [LocationsState.errorMessage] is set.
  error,
}

/// Immutable saved-locations state consumed by widgets.
class LocationsState {
  const LocationsState({
    required this.status,
    this.locations = const [],
    this.errorMessage,
  });

  const LocationsState.loading() : this(status: LocationsStatus.loading);

  final LocationsStatus status;

  /// Saved monitored locations, most recently used first.
  final List<MonitoredLocationRecord> locations;

  /// User-safe message for the most recent failure.
  final String? errorMessage;

  bool get isReady => status == LocationsStatus.ready;

  MonitoredLocationRecord? get primary {
    for (final record in locations) {
      if (record.isPrimary) return record;
    }
    return null;
  }

  @override
  String toString() =>
      'LocationsState(${status.name}, count: ${locations.length})';
}