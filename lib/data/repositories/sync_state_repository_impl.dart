import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/sync_state_record.dart';
import '../../domain/repositories/sync_state_repository.dart';
import '../datasources/local/database_schema.dart';
import '../datasources/local/local_database.dart';
import '../models/local_models.dart';

/// SQLite-backed [SyncStateRepository].
class SyncStateRepositoryImpl implements SyncStateRepository {
  SyncStateRepositoryImpl({required this.db, this.logger});

  final LocalDatabase db;
  final AppLogger? logger;

  DateTime get _now => DateTime.now().toUtc();

  @override
  Future<SyncStateRecord?> stateFor(String syncKey) async {
    final rows = await db.query(
      LocalTables.syncState,
      where: '${LocalColumns.syncKey} = ?',
      whereArgs: [syncKey],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalMappers.syncStateFromRow(rows.first);
  }

  Future<void> _upsert(SyncStateRecord record) async {
    await db.insert(
      LocalTables.syncState,
      LocalMappers.syncStateToRow(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> recordAttempt(String syncKey, {String? value}) async {
    final existing = await stateFor(syncKey);
    await _upsert(
      (existing ?? SyncStateRecord(syncKey: syncKey, lastAttemptAtUtc: _now))
          .copyWith(
        value: value,
        lastAttemptAtUtc: _now,
        status: SyncStatus.pending,
      ),
    );
  }

  @override
  Future<void> recordSuccess(String syncKey, {String? value, DateTime? at}) async {
    final successAt = (at ?? DateTime.now()).toUtc();
    final existing = await stateFor(syncKey);
    await _upsert(
      (existing ?? SyncStateRecord(syncKey: syncKey, lastAttemptAtUtc: successAt))
          .copyWith(
        value: value,
        lastAttemptAtUtc: successAt,
        lastSuccessAtUtc: successAt,
        status: SyncStatus.success,
      ),
    );
  }

  @override
  Future<void> recordFailure(String syncKey, {String? value}) async {
    final existing = await stateFor(syncKey);
    await _upsert(
      (existing ?? SyncStateRecord(syncKey: syncKey, lastAttemptAtUtc: _now))
          .copyWith(
        value: value,
        lastAttemptAtUtc: _now,
        status: SyncStatus.failure,
      ),
    );
  }

  @override
  Future<List<SyncStateRecord>> all() async {
    final rows = await db.query(
      LocalTables.syncState,
      orderBy: '${LocalColumns.lastAttemptUtc} DESC',
    );
    return rows.map(LocalMappers.syncStateFromRow).toList(growable: false);
  }
}