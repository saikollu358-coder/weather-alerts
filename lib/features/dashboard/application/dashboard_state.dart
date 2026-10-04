import '../../../domain/entities/alert_record.dart';
import '../../../domain/entities/current_location.dart';
import '../../../domain/entities/weather/weather_bundle.dart';
import '../../../services/weather_analysis/weather_analysis.dart';

/// High-level dashboard pipeline phases.
enum DashboardStatus {
  /// Resolving the initial position and data on startup.
  bootstrapping,

  /// No usable position yet: permission has not been granted, location
  /// services are off, or no fix has arrived.
  needsLocation,

  /// Weather (and downstream analysis) is loading.
  loading,

  /// The pipeline is fully wired: position -> weather -> analysis -> alerts.
  ready,

  /// The most recent load failed; [DashboardState.errorMessage] is set.
  error,
}

/// Immutable dashboard pipeline state consumed by widgets.
class DashboardState {
  const DashboardState({
    required this.status,
    this.location,
    this.bundle,
    this.analysis,
    this.activeAlerts = const [],
    this.errorMessage,
  });

  const DashboardState.bootstrapping() : this(status: DashboardStatus.bootstrapping);

  final DashboardStatus status;

  /// The device's current position, when known.
  final CurrentLocation? location;

  /// Most recently loaded weather, retained across refreshes.
  final WeatherBundle? bundle;

  /// Deterministic risk assessment of [bundle] (null before first load).
  final WeatherAnalysis? analysis;

  /// Current live alerts for [location], as persisted by the ingest step.
  final List<AlertRecord> activeAlerts;

  /// User-safe message for the most recent failure.
  final String? errorMessage;

  /// True once a position is known and data has been attempted.
  bool get hasLocation => location != null;

  /// Last successful data capture, for the mandatory "Last updated" UI.
  DateTime? get lastUpdatedAtUtc => bundle?.fetchedAtUtc;

  /// True once the current bundle has passed its freshness window.
  bool get isStale => bundle?.isStale() ?? false;

  bool get isReady => status == DashboardStatus.ready;

  DashboardState copyWith({
    DashboardStatus? status,
    CurrentLocation? location,
    WeatherBundle? bundle,
    WeatherAnalysis? analysis,
    List<AlertRecord>? activeAlerts,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DashboardState(
      status: status ?? this.status,
      location: location ?? this.location,
      bundle: bundle ?? this.bundle,
      analysis: analysis ?? this.analysis,
      activeAlerts: activeAlerts ?? this.activeAlerts,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() => 'DashboardState(${status.name}, '
      'location: ${location?.label}, alerts: ${activeAlerts.length})';
}