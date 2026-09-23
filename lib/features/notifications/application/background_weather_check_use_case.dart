import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../domain/entities/alert_record.dart';
import '../../../domain/entities/monitored_location_record.dart';
import '../../../domain/repositories/alert_history_repository.dart';
import '../../../domain/repositories/monitored_location_repository.dart';
import '../../../domain/repositories/notification_state_repository.dart';
import '../../../domain/repositories/preference_repository.dart';
import '../../../domain/services/notification_service.dart';
import '../../../domain/services/weather_service.dart';
import '../../../services/weather_analysis/weather_analysis.dart';
import '../../../services/weather_analysis/weather_hazard.dart';
import '../../../services/weather_analysis/weather_risk_evaluator.dart';
import '../../../services/weather_analysis/weather_severity.dart';
import '../../alerts/application/alert_ingest_use_case.dart';
import '../../alerts/application/alert_text.dart';
import 'notification_preferences.dart';

/// Result of one background weather check.
class BackgroundCheckResult {
  const BackgroundCheckResult({
    this.handled = false,
    this.notificationsSent = 0,
    this.activeHazardCount = 0,
  });

  /// True when a primary location was actually checked.
  final bool handled;

  /// Number of alert notifications delivered in this run.
  final int notificationsSent;

  /// Number of actionable hazards present in this run.
  final int activeHazardCount;

  @override
  String toString() =>
      'BackgroundCheckResult(handled: $handled, sent: '
      '$notificationsSent, hazards: $activeHazardCount)';
}

/// Runs the deterministic weather-risk pipeline once for the primary location
/// and notifies only when a hazard is new, has escalated, or has been silent
/// past the notification cooldown.
///
/// Used by the scheduled background task (workmanager). The engine,
/// repositories and ingest step are identical to the in-app pipeline, so the
/// alert path always stays rule-based and never depends on an LLM.
class BackgroundWeatherCheckUseCase {
  BackgroundWeatherCheckUseCase({
    required this.locations,
    required this.preferences,
    required this.weather,
    required this.evaluator,
    required this.alertHistory,
    required this.notificationState,
    required this.ingest,
    required this.notifier,
    required this.logger,
  });

  final MonitoredLocationRepository locations;
  final PreferenceRepository preferences;
  final WeatherService weather;
  final WeatherRiskEvaluator evaluator;
  final AlertHistoryRepository alertHistory;
  final NotificationStateRepository notificationState;
  final AlertIngestUseCase ingest;
  final NotificationService notifier;
  final AppLogger logger;

  /// Notification dedupe identity for an unchanged hazard+location pair.
  ///
  /// Deliberately excludes the UTC-hour bucket used by
  /// [WeatherRiskEvaluator.fingerprintFor], so an ongoing condition is
  /// suppressed for the full [AppConstants.alertNotificationCooldown].
  static String notificationKeyFor(
    WeatherHazard hazard,
    String locationKey,
    int rulesVersion,
  ) =>
      'notif:v$rulesVersion:${hazard.name}:$locationKey';

  /// Performs one check. Never throws: failures are logged and degrade to an
  /// empty result so a background task cannot crash the OS worker.
  Future<BackgroundCheckResult> check() async {
    try {
      if (!await _notificationsEnabled()) {
        return const BackgroundCheckResult();
      }
      final primary = await locations.primaryLocation();
      if (primary == null) {
        logger.debug(
          'BackgroundWeatherCheck',
          'no primary location configured; skipping check',
        );
        return const BackgroundCheckResult();
      }

      final bundle = await weather.load(
        locationKey: primary.locationKey,
        latitude: primary.latitude,
        longitude: primary.longitude,
      );
      final now = bundle.fetchedAtUtc;
      final analysis = evaluator.analyze(bundle, now: now);
      final previousActive = await alertHistory.activeAlerts();
      final findings = analysis.actionableFindings;

      var sent = 0;
      for (final finding in findings) {
        if (!(await _shouldNotify(
          finding,
          primary,
          analysis,
          previousActive,
        ))) {
          continue;
        }
        await _notify(finding, primary, analysis);
        sent++;
      }

      await ingest.ingest(analysis, locationKey: primary.locationKey);
      return BackgroundCheckResult(
        handled: true,
        notificationsSent: sent,
        activeHazardCount: findings.length,
      );
    } catch (e) {
      logger.warning(
        'BackgroundWeatherCheck',
        'check failed: ${e.runtimeType}',
      );
      return const BackgroundCheckResult();
    }
  }

  Future<bool> _notificationsEnabled() async {
    final raw = await preferences.read(NotificationPreferences.enabledKey);
    return NotificationPreferences.enabledFrom(raw);
  }

  Future<bool> _shouldNotify(
    HazardFinding finding,
    MonitoredLocationRecord location,
    WeatherAnalysis analysis,
    List<AlertRecord> previousActive,
  ) async {
    AlertRecord? active;
    for (final record in previousActive) {
      if (record.locationKey == location.locationKey &&
          record.hazard == finding.hazard.name) {
        active = record;
        break;
      }
    }

    if (active == null) return true;

    final currentSeverity =
        WeatherSeverity.tryParse(active.severity) ?? WeatherSeverity.none;
    if (currentSeverity.index < finding.severity.index) return true;

    final key = _notificationKey(finding, location, analysis);
    return notificationState.shouldNotify(
      key,
      AppConstants.alertNotificationCooldown,
      now: analysis.analyzedAtUtc,
    );
  }

  Future<void> _notify(
    HazardFinding finding,
    MonitoredLocationRecord location,
    WeatherAnalysis analysis,
  ) async {
    final key = _notificationKey(finding, location, analysis);
    final title =
        '${severityLabel(finding.severity)} ${hazardLabel(finding.hazard)} at '
        '${location.name}';
    final payload = jsonEncode({
      'fingerprint': evaluator.fingerprintFor(
        finding.hazard,
        location.locationKey,
        analysis.analyzedAtUtc,
      ),
      'notificationKey': key,
      'locationKey': location.locationKey,
      'hazard': finding.hazard.name,
      'severity': finding.severity.name,
      'rulesVersion': analysis.rulesVersion,
    });
    await notifier.showAlert(title: title, body: finding.reason, payload: payload);
    await notificationState.recordNotification(key, at: analysis.analyzedAtUtc);
  }

  String _notificationKey(
    HazardFinding finding,
    MonitoredLocationRecord location,
    WeatherAnalysis analysis,
  ) =>
      notificationKeyFor(
        finding.hazard,
        location.locationKey,
        analysis.rulesVersion,
      );
}