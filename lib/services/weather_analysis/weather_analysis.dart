import 'risk_level.dart';
import 'weather_hazard.dart';
import 'weather_severity.dart';

/// A single detected hazard inside a [WeatherAnalysis].
///
/// The finding is deterministic — identical inputs and rules yield identical
/// findings — and carries enough structure for Phase 7 to build an
/// [AlertRecord] (hazard/severity as canonical strings, reason, and a numeric
/// value/unit for the payload).
class HazardFinding {
  const HazardFinding({
    required this.hazard,
    required this.severity,
    required this.reason,
    this.value,
    this.unit,
  });

  final WeatherHazard hazard;
  final WeatherSeverity severity;

  /// Human-readable, deterministic justification, e.g.
  /// "Peak gusts of 82 km/h expected in the next 24 h".
  final String reason;

  /// The metric that breached the threshold, when applicable.
  final double? value;

  /// Display unit for [value] (e.g. `km/h`, `°C`, `mm`).
  final String? unit;

  /// True when this hazard is worth surfacing to the user.
  bool get isActionable => severity != WeatherSeverity.none;

  /// Canonical storage string (matches `AlertRecord.hazard`).
  String get canonicalHazard => hazard.name;

  /// Canonical storage string (matches `AlertRecord.severity`).
  String get canonicalSeverity => severity.name;

  @override
  String toString() => 'HazardFinding(${hazard.name}, ${severity.name})';
}

/// The complete, rule-based risk assessment for one location.
class WeatherAnalysis {
  const WeatherAnalysis({
    required this.riskLevel,
    required this.overallSeverity,
    required this.findings,
    required this.rulesVersion,
    required this.analyzedAtUtc,
  });

  /// Aggregate risk for the location, derived from [overallSeverity].
  final RiskLevel riskLevel;

  /// Highest individual hazard severity contributing to [riskLevel].
  final WeatherSeverity overallSeverity;

  /// All hazards detected, in a stable (hazard-declaration) order.
  final List<HazardFinding> findings;

  /// [SafetyRules.version] that produced this analysis.
  final int rulesVersion;

  /// UTC instant the analysis was produced.
  final DateTime analyzedAtUtc;

  /// Actionable hazards only (severity above none).
  List<HazardFinding> get actionableFindings =>
      findings.where((f) => f.isActionable).toList();

  /// True when at least one hazard is active.
  bool get hasActiveHazards => findings.any((f) => f.isActionable);

  /// Retains the highest severity between two values.
  static WeatherSeverity maxSeverity(
    WeatherSeverity a,
    WeatherSeverity b,
  ) =>
      a.index >= b.index ? a : b;
}