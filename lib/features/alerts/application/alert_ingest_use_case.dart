import '../../../core/constants/app_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../domain/entities/alert_record.dart';
import '../../../domain/entities/alert_status.dart';
import '../../../domain/repositories/alert_history_repository.dart';
import '../../../services/weather_analysis/weather_analysis.dart';
import '../../../services/weather_analysis/weather_hazard.dart';
import '../../../services/weather_analysis/weather_risk_evaluator.dart';
import '../../../services/weather_analysis/weather_severity.dart';
import 'alert_text.dart';

/// Converts a [WeatherAnalysis] into persisted, deduplicated alerts.
///
/// Deterministic pipeline step of the Phase 7 dashboard:
///   analysis -> AlertRecord (deduped by fingerprint) -> repository.
///
/// The same fingerprint is reused while the hazard stays active, so repeated
/// evaluations never re-create the same alert. When a previously active hazard
/// is no longer present in the latest analysis, its alert is marked resolved.
class AlertIngestUseCase {
  AlertIngestUseCase({
    required this.alerts,
    required this.evaluator,
    required this.logger,
  });

  final AlertHistoryRepository alerts;
  final WeatherRiskEvaluator evaluator;
  final AppLogger logger;

  /// Persists alerts for all actionable findings in [analysis] at
  /// [locationKey] and returns the still-active alerts for that location.
  Future<List<AlertRecord>> ingest(
    WeatherAnalysis analysis, {
    required String locationKey,
  }) async {
    final now = analysis.analyzedAtUtc;
    final actionable =
        analysis.findings.where((finding) => finding.isActionable).toList();
    final activeHazards = <WeatherHazard>{};

    for (final finding in actionable) {
      activeHazards.add(finding.hazard);
      await _upsertFinding(analysis, finding, locationKey, now);
    }

    await _resolveClearedHazards(activeHazards, locationKey, now);

    final remaining = await alerts.activeAlerts();
    logger.debug(
      'AlertIngestUseCase',
      '$locationKey: ${remaining.length} active after ingest',
    );
    return remaining.where((a) => a.locationKey == locationKey).toList();
  }

  Future<void> _upsertFinding(
    WeatherAnalysis analysis,
    HazardFinding finding,
    String locationKey,
    DateTime now,
  ) async {
    final fingerprint =
        evaluator.fingerprintFor(finding.hazard, locationKey, now);
    final existing = await alerts.alertByFingerprint(fingerprint);

    final isFresh = existing == null || !existing.isActive;
    final severityGrew = existing != null &&
        (WeatherSeverity.tryParse(existing.severity)?.index ?? 0) <
            finding.severity.index;
    final status = isFresh
        ? AlertStatus.detected
        : severityGrew
            ? AlertStatus.escalated
            : existing.status;

    await alerts.upsertAlert(
      AlertRecord(
        fingerprint: fingerprint,
        hazard: finding.hazard.name,
        severity: finding.severity.name,
        status: status,
        title: '${severityLabel(finding.severity)} '
            '${hazardLabel(finding.hazard)}',
        description: finding.reason,
        reason: finding.reason,
        locationKey: locationKey,
        payload: {
          'value': finding.value,
          'unit': finding.unit,
          'rulesVersion': analysis.rulesVersion,
        },
        detectedAtUtc: existing?.detectedAtUtc ?? now,
        updatedAtUtc: now,
        expiresAtUtc: now.add(AppConstants.alertRetention),
        acknowledged: existing?.acknowledged ?? false,
      ),
    );
  }

  Future<void> _resolveClearedHazards(
    Set<WeatherHazard> activeHazards,
    String locationKey,
    DateTime now,
  ) async {
    final active = await alerts.activeAlerts();
    for (final record in active) {
      if (record.locationKey != locationKey) continue;
      final hazard = WeatherHazard.tryParse(record.hazard);
      if (hazard == null || activeHazards.contains(hazard)) continue;
      await alerts.markResolved(record.fingerprint, at: now);
      logger.debug(
        'AlertIngestUseCase',
        'resolved ${record.hazard} at $locationKey',
      );
    }
  }
}