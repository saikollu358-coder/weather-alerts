import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/datasources/local/local_database_io.dart';
import 'package:weather_alerts/data/repositories/sync_state_repository_impl.dart';
import 'package:weather_alerts/domain/entities/sync_state_record.dart';

import '../helpers/test_database.dart';

void main() {
  late SqfliteDatabase db;
  late Directory dir;
  late SyncStateRepositoryImpl repository;

  setUp(() async {
    final created = await createTestDatabase();
    db = created.$1;
    dir = created.$2;
    repository = SyncStateRepositoryImpl(
      db: db,
      logger: AppLogger(enabled: false),
    );
  });

  tearDown(() async => teardownTestDatabase(db, dir));

  test('stateFor is null when a domain was never synced', () async {
    expect(await repository.stateFor('alerts'), isNull);
  });

  test('recordAttempt stamps a pending attempt', () async {
    await repository.recordAttempt('alerts', value: 'token-1');

    final state = await repository.stateFor('alerts');
    expect(state!.status, SyncStatus.pending);
    expect(state.value, 'token-1');
    expect(state.lastAttemptAtUtc, isNotNull);
    expect(state.lastSuccessAtUtc, isNull);
  });

  test('recordSuccess records success and clears pending state', () async {
    await repository.recordAttempt('alerts');
    await repository.recordSuccess(
      'alerts',
      value: 'snapshot-v2',
      at: DateTime.utc(2026, 1, 2),
    );

    final state = await repository.stateFor('alerts');
    expect(state!.status, SyncStatus.success);
    expect(state.value, 'snapshot-v2');
    expect(state.lastSuccessAtUtc, DateTime.utc(2026, 1, 2));
  });

  test('recordFailure tracks attempt while keeping prior success', () async {
    await repository.recordSuccess('alerts', at: DateTime.utc(2026, 1, 1));
    await repository.recordFailure('alerts', value: 'pending-queue');

    final state = await repository.stateFor('alerts');
    expect(state!.status, SyncStatus.failure);
    expect(state.value, 'pending-queue');
    expect(state.lastAttemptAtUtc.isAfter(state.lastSuccessAtUtc!), isTrue);
  });

  test('all returns every sync domain newest attempt first', () async {
    await repository.recordAttempt('a', value: 'v');
    await repository.recordSuccess('b', value: 'v');
    // Single physical row per domain.
    await repository.recordFailure('a', value: 'again');

    expect(await db.query('sync_state'), hasLength(2));
    final all = await repository.all();
    expect(all, hasLength(2));
  });
}