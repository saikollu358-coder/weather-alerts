import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/datasources/local/local_database_io.dart';
import 'package:weather_alerts/data/repositories/alert_history_repository_impl.dart';
import 'package:weather_alerts/domain/entities/alert_record.dart';
import 'package:weather_alerts/domain/entities/alert_status.dart';

import '../helpers/test_database.dart';

void main() {
  late SqfliteDatabase db;
  late Directory dir;
  late AlertHistoryRepositoryImpl repository;

  setUp(() async {
    final created = await createTestDatabase();
    db = created.$1;
    dir = created.$2;
    repository = AlertHistoryRepositoryImpl(
      db: db,
      logger: AppLogger(enabled: false),
    );
  });

  tearDown(() async => teardownTestDatabase(db, dir));

  AlertRecord record({
    String fingerprint = 'fp-1',
    String hazard = 'Thunderstorm',
    String severity = 'SEVERE',
    AlertStatus status = AlertStatus.active,
    String location = '10,10',
    DateTime? detected,
    DateTime? resolved,
  }) =>
      AlertRecord(
        fingerprint: fingerprint,
        hazard: hazard,
        severity: severity,
        status: status,
        title: 'Severe thunderstorm',
        description: 'Dangerous hail risk.',
        reason: 'Strong updraft indicators.',
        locationKey: location,
        payload: const {
          'wind_gust': 96,
        },
        detectedAtUtc: detected ?? DateTime.utc(2026, 1, 1, 8),
        updatedAtUtc: DateTime.utc(2026, 1, 1, 8, 5),
        resolvedAtUtc: resolved,
      );

  test('inserts a new alert and reads it back by fingerprint', () async {
    await repository.upsertAlert(record());

    final loaded = await repository.alertByFingerprint('fp-1');
    expect(loaded, isNotNull);
    expect(loaded!.hazard, 'Thunderstorm');
    expect(loaded.severity, 'SEVERE');
    expect(loaded.status, AlertStatus.active);
    expect(loaded.locationKey, '10,10');
    expect(loaded.payload, {'wind_gust': 96});
  });

  test('upserting the same fingerprint deduplicates to a single alert',
      () async {
    await repository.upsertAlert(record());
    await repository.upsertAlert(
      record(
        severity: 'EXTREME',
        status: AlertStatus.escalated,
      ),
    );

    expect(await db.query('alert_history'), hasLength(1));
    final loaded = await repository.alertByFingerprint('fp-1');
    expect(loaded!.severity, 'EXTREME');
    expect(loaded.status, AlertStatus.escalated);
  });

  test('activeAlerts excludes resolved and expired alerts', () async {
    await repository.upsertAlert(record(fingerprint: 'active'));
    await repository.upsertAlert(
      record(
        fingerprint: 'resolved',
        status: AlertStatus.resolved,
        resolved: DateTime.utc(2026, 1, 1, 9),
      ),
    );
    await repository.upsertAlert(
      record(fingerprint: 'expired', status: AlertStatus.expired),
    );

    final active = await repository.activeAlerts();
    expect(active.map((a) => a.fingerprint), ['active']);
  });

  test('updateStatus transitions state and stamps resolution time', () async {
    await repository.upsertAlert(record());
    await repository.updateStatus('fp-1', AlertStatus.resolved);

    final loaded = await repository.alertByFingerprint('fp-1');
    expect(loaded!.status, AlertStatus.resolved);
    expect(loaded.resolvedAtUtc, isNotNull);
    expect(loaded.updatedAtUtc.isAfter(loaded.detectedAtUtc), isTrue);
  });

  test('markResolved and markAcknowledged persist flags', () async {
    await repository.upsertAlert(record());
    await repository.markResolved(
      'fp-1',
      at: DateTime.utc(2026, 1, 2),
    );
    await repository.markAcknowledged('fp-1');

    final loaded = await repository.alertByFingerprint('fp-1');
    expect(loaded!.status, AlertStatus.resolved);
    expect(loaded.resolvedAtUtc, DateTime.utc(2026, 1, 2));
    expect(loaded.acknowledged, isTrue);
  });

  test('alerts supports status, hazard, since, order and limit filters',
      () async {
    await repository.upsertAlert(record(fingerprint: 'a'));
    await repository.upsertAlert(
      record(
        fingerprint: 'b',
        hazard: 'High UV',
        severity: 'MODERATE',
        detected: DateTime.utc(2026, 1, 1, 9),
      ),
    );
    await repository.upsertAlert(
      record(
        fingerprint: 'c',
        status: AlertStatus.resolved,
        detected: DateTime.utc(2026, 1, 1, 10),
      ),
    );

    final resolved =
        await repository.alerts(status: AlertStatus.resolved);
    expect(resolved.single.fingerprint, 'c');

    final uv = await repository.alerts(hazard: 'High UV');
    expect(uv.single.fingerprint, 'b');

    final since = await repository.alerts(
      since: DateTime.utc(2026, 1, 1, 9, 1),
    );
    expect(since.map((a) => a.fingerprint).toList(), ['c']);

    final limited = await repository.alerts(limit: 2);
    expect(limited, hasLength(2));
    // Newest first.
    expect(limited.first.fingerprint, 'c');
  });

  test('purgeOlderThan removes only old alerts and reports the count',
      () async {
    await repository.upsertAlert(record(fingerprint: 'old'));
    await repository.upsertAlert(
      record(
        fingerprint: 'new',
        detected: DateTime.utc(2026, 1, 5),
      ),
    );

    final removed = await repository.purgeOlderThan(DateTime.utc(2026, 1, 2));
    expect(removed, 1);
    expect(await repository.alertByFingerprint('old'), isNull);
    expect(await repository.alertByFingerprint('new'), isNotNull);
  });

  test('clear wipes the whole alert history', () async {
    await repository.upsertAlert(record());
    await repository.clear();
    expect(await repository.activeAlerts(), isEmpty);
    expect(await db.query('alert_history'), isEmpty);
  });
}