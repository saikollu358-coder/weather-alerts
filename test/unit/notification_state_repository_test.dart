import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/datasources/local/local_database_io.dart';
import 'package:weather_alerts/data/repositories/notification_state_repository_impl.dart';

import '../helpers/test_database.dart';

void main() {
  late SqfliteDatabase db;
  late Directory dir;
  late NotificationStateRepositoryImpl repository;

  setUp(() async {
    final created = await createTestDatabase();
    db = created.$1;
    dir = created.$2;
    repository = NotificationStateRepositoryImpl(
      db: db,
      logger: AppLogger(enabled: false),
    );
  });

  tearDown(() async => teardownTestDatabase(db, dir));

  const fingerprint = 'fp-1';

  test('recordFor is null when nothing was notified', () async {
    expect(await repository.recordFor(fingerprint), isNull);
  });

  test('recordNotification creates and then increments the record',
      () async {
    final firstAt = DateTime.utc(2026, 1, 1, 8);
    await repository.recordNotification(fingerprint, at: firstAt);
    await repository.recordNotification(
      fingerprint,
      at: DateTime.utc(2026, 1, 1, 9),
    );

    final record = await repository.recordFor(fingerprint);
    expect(record, isNotNull);
    expect(record!.notificationCount, 2);
    expect(record.lastNotifiedAtUtc, DateTime.utc(2026, 1, 1, 9));
    expect(record.status, 'sent');
    // Single physical row.
    expect(await db.query('notification_state'), hasLength(1));
  });

  test('shouldNotify honors the cooldown window', () async {
    final now = DateTime.utc(2026, 1, 1, 12);
    expect(await repository.shouldNotify(fingerprint, Duration.zero, now: now),
        isTrue);

    await repository.recordNotification(
      fingerprint,
      at: now.subtract(const Duration(minutes: 5)),
    );
    final cooldown = const Duration(hours: 1);
    expect(
      await repository.shouldNotify(fingerprint, cooldown, now: now),
      isFalse,
    );

    // Past the cooldown -> allowed again.
    expect(
      await repository.shouldNotify(
        fingerprint,
        cooldown,
        now: now.add(const Duration(hours: 2)),
      ),
      isTrue,
    );
  });

  test('recent filters by last update time', () async {
    await repository.recordNotification(
      'old',
      at: DateTime.utc(2026, 1, 1, 8),
    );
    await repository.recordNotification(
      'new',
      at: DateTime.utc(2026, 1, 2, 8),
    );

    final recent =
        await repository.recent(DateTime.utc(2026, 1, 2));
    expect(recent.single.fingerprint, 'new');
  });

  test('purgeOlderThan removes stale delivery records', () async {
    await repository.recordNotification(
      'old',
      at: DateTime.utc(2026, 1, 1),
    );
    await repository.recordNotification(
      'new',
      at: DateTime.utc(2026, 1, 5),
    );

    await repository.purgeOlderThan(DateTime.utc(2026, 1, 2));
    expect(await repository.recordFor('old'), isNull);
    expect(await repository.recordFor('new'), isNotNull);
  });
}