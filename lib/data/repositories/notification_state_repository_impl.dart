import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/notification_state_record.dart';
import '../../domain/repositories/notification_state_repository.dart';
import '../datasources/local/database_schema.dart';
import '../datasources/local/local_database.dart';
import '../models/local_models.dart';

/// SQLite-backed [NotificationStateRepository].
class NotificationStateRepositoryImpl implements NotificationStateRepository {
  NotificationStateRepositoryImpl({required this.db, this.logger});

  final LocalDatabase db;
  final AppLogger? logger;

  @override
  Future<NotificationStateRecord?> recordFor(String fingerprint) async {
    final rows = await db.query(
      LocalTables.notificationState,
      where: '${LocalColumns.fingerprint} = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalMappers.notificationStateFromRow(rows.first);
  }

  @override
  Future<void> recordNotification(
    String fingerprint, {
    DateTime? at,
    String status = 'sent',
  }) async {
    final now = (at ?? DateTime.now()).toUtc();
    final existing = await recordFor(fingerprint);
    final count = (existing?.notificationCount ?? 0) + 1;
    await db.insert(
      LocalTables.notificationState,
      LocalMappers.notificationStateToRow(
        NotificationStateRecord(
          fingerprint: fingerprint,
          lastNotifiedAtUtc: now,
          notificationCount: count,
          status: status,
          updatedAtUtc: now,
        ),
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> shouldNotify(
    String fingerprint,
    Duration cooldown, {
    DateTime? now,
  }) async {
    final existing = await recordFor(fingerprint);
    if (existing == null) return true;
    final cutoff = (now ?? DateTime.now())
        .toUtc()
        .subtract(cooldown);
    return existing.lastNotifiedAtUtc.isBefore(cutoff);
  }

  @override
  Future<List<NotificationStateRecord>> recent(DateTime since) async {
    final rows = await db.query(
      LocalTables.notificationState,
      where: '${LocalColumns.updatedAtUtc} >= ?',
      whereArgs: [since.toUtc().millisecondsSinceEpoch],
      orderBy: '${LocalColumns.updatedAtUtc} DESC',
    );
    return rows.map(LocalMappers.notificationStateFromRow).toList(growable: false);
  }

  @override
  Future<void> purgeOlderThan(DateTime cutoff) async {
    await db.delete(
      LocalTables.notificationState,
      where: '${LocalColumns.updatedAtUtc} < ?',
      whereArgs: [cutoff.toUtc().millisecondsSinceEpoch],
    );
  }
}