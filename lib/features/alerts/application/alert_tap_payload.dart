import 'dart:convert';

/// The parsed contents of a weather-alert notification payload.
///
/// Payloads are produced in two places and must stay in sync with both:
///
/// * `BackgroundWeatherCheckUseCase._notify` encodes a JSON object into
///   [NotificationService.showAlert]'s `payload`.
/// * `functions/src/server_alerts/push_router.ts` sends the same keys as an FCM
///   `data` message (all values are strings there).
///
/// Parsing is deliberately lenient: a tap is a navigation hint, never a safety
/// decision, so a malformed or partial payload degrades to "no alert id" instead
/// of throwing. Nothing here decides whether a condition is hazardous — that is
/// the deterministic engine's job.
class AlertTapPayload {
  const AlertTapPayload({
    this.fingerprint,
    this.hazard,
    this.severity,
    this.locationKey,
  });

  /// Canonical alert identity (`WeatherRiskEvaluator.fingerprintFor`). Null when
  /// the payload did not carry a usable id.
  final String? fingerprint;

  /// Canonical hazard name, e.g. `Thunderstorm`.
  final String? hazard;

  /// Canonical severity name, e.g. `SEVERE`.
  final String? severity;

  /// Geographic area the alert applies to.
  final String? locationKey;

  /// True when the payload identifies a specific alert.
  bool get hasAlert => fingerprint != null && fingerprint!.isNotEmpty;

  /// Parses the JSON string carried by a local-notification tap.
  ///
  /// Returns null when [raw] is blank or not a JSON object.
  static AlertTapPayload? tryParseJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    return fromMap(decoded);
  }

  /// Builds a payload from an FCM `data` map (or any decoded JSON object).
  ///
  /// Values are coerced to strings because FCM data messages are string-only,
  /// while the JSON path may already hold ints.
  static AlertTapPayload fromMap(Map<Object?, Object?> data) {
    return AlertTapPayload(
      fingerprint: _string(data['fingerprint']),
      hazard: _string(data['hazard']),
      severity: _string(data['severity']),
      locationKey: _string(data['locationKey']),
    );
  }

  /// Coerces a payload value to a trimmed, non-empty string.
  ///
  /// Trimming matters for the fingerprint: a whitespace-padded id would not
  /// match the stored record and the tap would silently do nothing.
  static String? _string(Object? value) {
    if (value == null) return null;
    final text = (value is String ? value : value.toString()).trim();
    return text.isEmpty ? null : text;
  }

  @override
  String toString() =>
      'AlertTapPayload($fingerprint, $hazard/$severity, $locationKey)';
}