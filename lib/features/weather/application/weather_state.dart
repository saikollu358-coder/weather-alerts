import '../../../domain/entities/weather/weather_bundle.dart';

/// High-level weather loading phases.
enum WeatherStatus {
  /// Nothing loaded yet.
  idle,

  /// A load is in progress; [WeatherState.bundle] may hold the last good data.
  loading,

  /// The latest bundle is ready.
  ready,

  /// The most recent load failed; [WeatherState.errorMessage] is set.
  error,
}

/// Immutable weather state consumed by widgets.
class WeatherState {
  const WeatherState({
    required this.status,
    this.bundle,
    this.errorMessage,
  });

  const WeatherState.initial() : this(status: WeatherStatus.idle);

  final WeatherStatus status;

  /// Most recently loaded data, retained across refreshes.
  final WeatherBundle? bundle;

  /// User-safe message for the most recent failure.
  final String? errorMessage;

  bool get isReady => status == WeatherStatus.ready;

  /// True when the current bundle has passed its freshness window.
  bool get isStale => bundle?.isStale() ?? false;

  WeatherState copyWith({
    WeatherStatus? status,
    WeatherBundle? bundle,
    bool clearBundle = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WeatherState(
      status: status ?? this.status,
      bundle: clearBundle ? null : (bundle ?? this.bundle),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() => 'WeatherState($status)';
}