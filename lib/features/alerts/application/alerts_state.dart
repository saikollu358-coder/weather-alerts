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
    this.errorMessage,
  });

  const AlertsState.loading() : this(status: AlertsStatus.loading);

  final AlertsStatus status;

  /// Currently live alerts, newest first.
  ///
  /// This is the whole list: resolved and expired alerts are still recorded
  /// locally for deduplication, but they are never shown. The alerts tab
  /// answers "what is happening now", not "what happened last month".
  final List<AlertRecord> active;

  /// User-safe message for the most recent failure.
  final String? errorMessage;

  bool get isReady => status == AlertsStatus.ready;

  /// True when at least one hazard needs the user's attention right now.
  bool get hasActive => active.isNotEmpty;

  @override
  String toString() => 'AlertsState(active: ${active.length})';
}