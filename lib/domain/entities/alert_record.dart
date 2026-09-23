import 'alert_status.dart';

/// A persisted alert record in local history.
///
/// Hazard and severity are stored as canonical strings so the storage layer
/// stays decoupled from the analysis-engine enums (Phase 8:
/// `lib/services/weather_analysis/weather_hazard.dart` and `weather_severity.dart`).
class AlertRecord {
  const AlertRecord({
    required this.fingerprint,
    required this.hazard,
    required this.severity,
    required this.status,
    required this.title,
    required this.description,
    required this.reason,
    required this.locationKey,
    this.payload = const {},
    required this.detectedAtUtc,
    required this.updatedAtUtc,
    this.resolvedAtUtc,
    this.expiresAtUtc,
    this.acknowledged = false,
  });

  /// Deterministic alert identity used for deduplication/cooldown.
  final String fingerprint;

  /// Canonical hazard identifier, e.g. `Thunderstorm`.
  final String hazard;

  /// Canonical severity identifier, e.g. `SEVERE`.
  final String severity;

  /// Lifecycle state.
  final AlertStatus status;

  final String title;
  final String description;
  final String reason;

  /// Geographic area the alert applies to.
  final String locationKey;

  /// Supporting measurements and structured details (opaque to storage).
  final Map<String, dynamic> payload;

  /// Detection time (always UTC).
  final DateTime detectedAtUtc;

  /// Last state change (always UTC).
  final DateTime updatedAtUtc;

  /// When the alert was resolved/expired, when known.
  final DateTime? resolvedAtUtc;

  /// When the alert should be considered expired.
  final DateTime? expiresAtUtc;

  /// Whether the user has acknowledged the alert.
  final bool acknowledged;

  AlertRecord copyWith({
    AlertStatus? status,
    String? severity,
    String? title,
    String? description,
    String? reason,
    Map<String, dynamic>? payload,
    DateTime? updatedAtUtc,
    DateTime? resolvedAtUtc,
    bool? acknowledged,
  }) {
    return AlertRecord(
      fingerprint: fingerprint,
      hazard: hazard,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      title: title ?? this.title,
      description: description ?? this.description,
      reason: reason ?? this.reason,
      locationKey: locationKey,
      payload: payload ?? this.payload,
      detectedAtUtc: detectedAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      resolvedAtUtc: resolvedAtUtc ?? this.resolvedAtUtc,
      expiresAtUtc: expiresAtUtc,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }

  bool get isActive => status != AlertStatus.resolved && status != AlertStatus.expired;

  @override
  String toString() => 'AlertRecord($hazard/$severity/$status, $fingerprint)';
}