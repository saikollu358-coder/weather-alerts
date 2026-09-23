import '../../../domain/entities/geo_position.dart';

/// High-level location monitoring phases.
enum LocationStatus {
  /// Startup; nothing checked yet.
  unknown,

  /// Waiting for the user to answer the permission prompt.
  waitingPermission,

  /// Permission denied (can be re-prompted).
  denied,

  /// Permission permanently denied; the user must use system settings.
  deniedForever,

  /// Permission granted and position updates are flowing.
  ready,

  /// OS location services are switched off (or the hardware is unavailable).
  unavailable,

  /// A transient failure; [LocationState.errorMessage] is set.
  error,
}

/// Immutable location state consumed by widgets.
class LocationState {
  const LocationState({
    required this.status,
    this.position,
    this.errorMessage,
  });

  const LocationState.initial() : this(status: LocationStatus.unknown);

  final LocationStatus status;

  /// Most recent fix, when available.
  final GeoPosition? position;

  /// User-safe message for the most recent failure.
  final String? errorMessage;

  bool get isReady => status == LocationStatus.ready;

  bool get isResolvableByUser =>
      status == LocationStatus.denied ||
      status == LocationStatus.deniedForever ||
      status == LocationStatus.waitingPermission;

  LocationState copyWith({
    LocationStatus? status,
    GeoPosition? position,
    bool clearPosition = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LocationState(
      status: status ?? this.status,
      position: clearPosition ? null : (position ?? this.position),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() => 'LocationState($status)';
}