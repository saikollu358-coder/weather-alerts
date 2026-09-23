import '../../../domain/entities/alert_record.dart';
import '../../../domain/entities/monitored_location_record.dart';
import '../../../domain/entities/weather/weather_bundle.dart';
import '../../../services/weather_analysis/weather_analysis.dart';

/// High-level dashboard pipeline phases.
enum DashboardStatus {
  /// Resolving the initial location and data on startup.
  bootstrapping,

  /// No saved locations and no accepted GPS fix yet — show the add-location
  /// flow before the pipeline can run.
  needsLocation,

  /// Weather (and downstream analysis) is loading.
  loading,

  /// The pipeline is fully wired: location -> weather -> analysis -> alerts.
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

  /// The currently selected monitored location, when known.
  final MonitoredLocationRecord? location;

  /// Most recently loaded weather, retained across refreshes.
  final WeatherBundle? bundle;

  /// Deterministic risk assessment of [bundle] (null before first load).
  final WeatherAnalysis? analysis;

  /// Current live alerts for [location], as persisted by the ingest step.
  final List<AlertRecord> activeAlerts;

  /// User-safe message for the most recent failure.
  final String? errorMessage;

  /// True once a location is selected and data has been attempted.
  bool get hasLocation => location != null;

  /// Last successful data capture, for the mandatory "Last updated" UI.
  DateTime? get lastUpdatedAtUtc => bundle?.fetchedAtUtc;

  /// True once the current bundle has passed its freshness window.
  bool get isStale => bundle?.isStale() ?? false;

  bool get isReady => status == DashboardStatus.ready;

  DashboardState copyWith({
    DashboardStatus? status,
    MonitoredLocationRecord? location,
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
      'location: ${location?.name}, alerts: ${activeAlerts.length})';
}