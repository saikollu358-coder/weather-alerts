import '../../../domain/entities/alert_record.dart';

/// High-level alert-listing phases.
enum AlertsStatus {
  /// Initial load in progress.
  loading,

  /// The lists are populated from the local repository.
  ready,

  /// The most recent load failed; [AlertsState.errorMessage] is set.
  error,
}

/// Immutable alert-listing state consumed by widgets.
class AlertsState {
  const AlertsState({
    required this.status,
    this.active = const [],
    this.history = const [],
    this.errorMessage,
  });

  const AlertsState.loading() : this(status: AlertsStatus.loading);

  final AlertsStatus status;

  /// Currently live alerts, newest first.
  final List<AlertRecord> active;

  /// Resolved/expired alerts, most recently updated first.
  final List<AlertRecord> history;

  /// User-safe message for the most recent failure.
  final String? errorMessage;

  bool get isReady => status == AlertsStatus.ready;

  @override
  String toString() => 'AlertsState(active: ${active.length}, '
      'history: ${history.length})';
}