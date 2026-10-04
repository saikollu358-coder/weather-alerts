import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/domain/entities/alert_record.dart';
import 'package:weather_alerts/domain/entities/alert_status.dart';
import 'package:weather_alerts/domain/entities/notification_state_record.dart';
import 'package:weather_alerts/features/alerts/application/alert_ingest_use_case.dart';
import 'package:weather_alerts/features/notifications/application/background_weather_check_use_case.dart';
import 'package:weather_alerts/features/notifications/application/notification_preferences.dart';
import 'package:weather_alerts/services/weather_analysis/safety_rules.dart';
import 'package:weather_alerts/services/weather_analysis/weather_hazard.dart';
import 'package:weather_alerts/services/weather_analysis/weather_risk_evaluator.dart';
import 'package:weather_alerts/services/weather_analysis/weather_severity.dart';

import '../helpers/pipeline_fakes.dart';

void main() {
  final evaluator = const WeatherRiskEvaluator();
  final t0 = DateTime.utc(2026, 3, 10, 10);
  const locationKey = '1.0,2.0';

  BackgroundWeatherCheckUseCase buildUseCase({
    required FakeWeatherService weather,
    InMemoryCurrentLocation? currentLocation,
    InMemoryAlertHistory? history,
    InMemoryNotificationState? notificationState,
    InMemoryPreferences? preferences,
    required FakeNotificationService notifier,
  }) {
    final logger = AppLogger(enabled: false);
    final alerts = history ?? InMemoryAlertHistory();
    return BackgroundWeatherCheckUseCase(
      currentLocation: currentLocation ??
          InMemoryCurrentLocation(seed: sampleCurrentLocation()),
      preferences: preferences ?? InMemoryPreferences(),
      weather: weather,
      evaluator: evaluator,
      alertHistory: alerts,
      notificationState: notificationState ?? InMemoryNotificationState(),
      ingest: AlertIngestUseCase(
        alerts: alerts,
        evaluator: evaluator,
        logger: logger,
      ),
      notifier: notifier,
      logger: logger,
    );
  }

  group('BackgroundWeatherCheckUseCase', () {
    test('is a no-op when notifications are disabled', () async {
      final weather = FakeWeatherService(bundle: sampleBundle(atUtc: t0));
      final preferences = InMemoryPreferences()
        ..write(NotificationPreferences.enabledKey, 'false');
      final notifier = FakeNotificationService();
      final useCase = buildUseCase(
        weather: weather,
        preferences: preferences,
        notifier: notifier,
      );

      final result = await useCase.check();

      expect(result.handled, isFalse);
      expect(weather.calls, 0);
      expect(notifier.showCount, 0);
    });

    test('is a no-op when no position has been captured yet', () async {
      final weather = FakeWeatherService(bundle: sampleBundle(atUtc: t0));
      final currentLocation = InMemoryCurrentLocation();
      final notifier = FakeNotificationService();
      final useCase = buildUseCase(
        weather: weather,
        currentLocation: currentLocation,
        notifier: notifier,
      );

      final result = await useCase.check();

      expect(result.handled, isFalse);
      expect(weather.calls, 0);
      expect(notifier.showCount, 0);
    });

    test('does nothing when no hazard is actionable', () async {
      final weather = FakeWeatherService(bundle: sampleBundle(atUtc: t0));
      final notifier = FakeNotificationService();
      final history = InMemoryAlertHistory();
      final useCase = buildUseCase(
        weather: weather,
        history: history,
        notifier: notifier,
      );

      final result = await useCase.check();

      expect(result.handled, isTrue);
      expect(result.activeHazardCount, 0);
      expect(notifier.showCount, 0);
      expect(await history.activeAlerts(), isEmpty);
    });

    test('notifies once per actionable hazard on a fresh check', () async {
      final weather = FakeWeatherService(
        bundle: sampleBundle(atUtc: t0, hourly: [thunderHourlyPoint(t0)]),
      );
      final notifier = FakeNotificationService();
      final notificationState = InMemoryNotificationState();
      final useCase = buildUseCase(
        weather: weather,
        notificationState: notificationState,
        notifier: notifier,
      );

      final result = await useCase.check();

      expect(result.handled, isTrue);
      expect(result.notificationsSent, 2);
      expect(notifier.showCount, 2);

      final hazards = notifier.shown
          .map((s) => jsonDecode(s.payload) as Map<String, dynamic>)
          .map((p) => p['hazard'])
          .toSet();
      expect(hazards, containsAll(<String>{'thunderstorm', 'lightning'}));

      final stormKey = BackgroundWeatherCheckUseCase.notificationKeyFor(
        WeatherHazard.thunderstorm,
        locationKey,
        SafetyRules.version,
      );
      final record = await notificationState.recordFor(stormKey);
      expect(record, isNotNull);
      expect(record!.lastNotifiedAtUtc, t0);
      expect(notificationState.recordCount, 2);
    });

    test('suppresses identical hazards inside the cooldown window', () async {
      final weather = FakeWeatherService(
        bundle: sampleBundle(atUtc: t0, hourly: [thunderHourlyPoint(t0)]),
      );
      final notifier = FakeNotificationService();
      final notificationState = InMemoryNotificationState();
      final useCase = buildUseCase(
        weather: weather,
        notificationState: notificationState,
        notifier: notifier,
      );

      expect((await useCase.check()).notificationsSent, 2);
      final second = await useCase.check();

      expect(second.notificationsSent, 0);
      expect(notifier.showCount, 2);
      expect(notificationState.recordCount, 2);
    });

    test('notifies again once the cooldown has elapsed', () async {
      final weather = FakeWeatherService(
        bundle: sampleBundle(atUtc: t0, hourly: [thunderHourlyPoint(t0)]),
      );
      final notifier = FakeNotificationService();
      final notificationState = InMemoryNotificationState();
      final useCase = buildUseCase(
        weather: weather,
        notificationState: notificationState,
        notifier: notifier,
      );

      expect((await useCase.check()).notificationsSent, 2);

      final later = t0.add(const Duration(hours: 4));
      weather.bundle =
          sampleBundle(atUtc: later, hourly: [thunderHourlyPoint(later)]);

      final result = await useCase.check();

      expect(result.notificationsSent, 2);
      expect(notifier.showCount, 4);
    });

    test('bypasses the cooldown when severity escalates', () async {
      final hourBefore = t0.subtract(const Duration(hours: 1));
      final rainKey = BackgroundWeatherCheckUseCase.notificationKeyFor(
        WeatherHazard.rain,
        locationKey,
        SafetyRules.version,
      );
      final history = InMemoryAlertHistory(
        seed: [
          AlertRecord(
            fingerprint: evaluator.fingerprintFor(
              WeatherHazard.rain,
              locationKey,
              hourBefore,
            ),
            hazard: WeatherHazard.rain.name,
            severity: WeatherSeverity.moderate.name,
            status: AlertStatus.detected,
            title: 'Moderate Rain',
            description: 'Moderate rain expected now.',
            reason: 'Moderate rain expected now.',
            locationKey: locationKey,
            detectedAtUtc: hourBefore,
            updatedAtUtc: hourBefore,
          ),
        ],
      );
      final notificationState = InMemoryNotificationState(
        seed: {
          rainKey: NotificationStateRecord(
            fingerprint: rainKey,
            lastNotifiedAtUtc: t0.subtract(const Duration(minutes: 30)),
          ),
        },
      );
      final weather = FakeWeatherService(
        bundle: sampleBundle(atUtc: t0, weatherCode: 65),
      );
      final notifier = FakeNotificationService();
      final useCase = buildUseCase(
        weather: weather,
        history: history,
        notificationState: notificationState,
        notifier: notifier,
      );

      final result = await useCase.check();

      expect(result.notificationsSent, 1);
      expect(notifier.showCount, 1);
      final payload =
          jsonDecode(notifier.shown.single.payload) as Map<String, dynamic>;
      expect(payload['hazard'], WeatherHazard.rain.name);
      expect(payload['severity'], WeatherSeverity.high.name);
    });

    test('re-notifies a hazard that cleared and then re-detected', () async {
      final weather = FakeWeatherService(
        bundle: sampleBundle(atUtc: t0, hourly: [thunderHourlyPoint(t0)]),
      );
      final notifier = FakeNotificationService();
      final history = InMemoryAlertHistory();
      final useCase = buildUseCase(
        weather: weather,
        history: history,
        notifier: notifier,
      );

      expect((await useCase.check()).notificationsSent, 2);

      weather.bundle = sampleBundle(atUtc: t0);
      await useCase.check();
      expect(await history.activeAlerts(), isEmpty);

      weather.bundle =
          sampleBundle(atUtc: t0, hourly: [thunderHourlyPoint(t0)]);
      final result = await useCase.check();

      expect(result.notificationsSent, 2);
      expect(notifier.showCount, 4);
    });

    test('degrades gracefully when weather acquisition fails', () async {
      final weather = FakeWeatherService(error: Exception('boom'));
      final notifier = FakeNotificationService();
      final useCase = buildUseCase(
        weather: weather,
        notifier: notifier,
      );

      final result = await useCase.check();

      expect(result.handled, isFalse);
      expect(notifier.showCount, 0);
    });
  test('degrades gracefully when the stored position cannot be read',
        () async {
      final weather = FakeWeatherService(bundle: sampleBundle(atUtc: t0));
      final notifier = FakeNotificationService();
      final useCase = buildUseCase(
        weather: weather,
        currentLocation: InMemoryCurrentLocation()..failReads = true,
        notifier: notifier,
      );

      final result = await useCase.check();

      expect(result.handled, isFalse);
      expect(notifier.showCount, 0);
    });

    test('checks the stored position rather than a saved location', () async {
      final weather = FakeWeatherService(bundle: sampleBundle(atUtc: t0));
      final notifier = FakeNotificationService();
      final useCase = buildUseCase(
        weather: weather,
        currentLocation: InMemoryCurrentLocation(
          seed: sampleCurrentLocation(
            latitude: 51.5,
            longitude: -0.12,
            label: 'London, England, United Kingdom',
          ),
        ),
        notifier: notifier,
      );

      await useCase.check();

      expect(weather.lastLocationKey, '51.5,-0.12');
    });
  });
}