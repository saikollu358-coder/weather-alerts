import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/alert_record.dart';
import '../../domain/entities/alert_status.dart';
import '../../domain/repositories/alert_history_repository.dart';
import '../datasources/local/database_schema.dart';
import '../datasources/local/local_database.dart';
import '../models/local_models.dart';

/// SQLite-backed [AlertHistoryRepository] with fingerprint deduplication.
class AlertHistoryRepositoryImpl implements AlertHistoryRepository {
  AlertHistoryRepositoryImpl({required this.db, this.logger});

  final LocalDatabase db;
  final AppLogger? logger;

  @override
  Future<void> upsertAlert(AlertRecord alert) async {
    await db.insert(
      LocalTables.alertHistory,
      LocalMappers.alertToRow(alert),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    logger?.debug('AlertHistoryRepository',
        'upserted ${alert.hazard}/${alert.severity} (${alert.status.name})');
  }

  @override
  Future<AlertRecord?> alertByFingerprint(String fingerprint) async {
    final rows = await db.query(
      LocalTables.alertHistory,
      where: '${LocalColumns.fingerprint} = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalMappers.alertFromRow(rows.first);
  }

  @override
  Future<List<AlertRecord>> alerts({
    AlertStatus? status,
    String? hazard,
    DateTime? since,
    int? limit,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (status != null) {
      conditions.add('${LocalColumns.status} = ?');
      args.add(status.name);
    }
    if (hazard != null) {
      conditions.add('${LocalColumns.hazard} = ?');
      args.add(hazard);
    }
    if (since != null) {
      conditions.add('${LocalColumns.detectedAtUtc} >= ?');
      args.add(since.toUtc().millisecondsSinceEpoch);
    }
    final where = conditions.isEmpty ? null : conditions.join(' AND ');
    final rows = await db.query(
      LocalTables.alertHistory,
      where: where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: '${LocalColumns.detectedAtUtc} DESC',
      limit: limit,
    );
    return rows.map(LocalMappers.alertFromRow).toList(growable: false);
  }

  @override
  Future<List<AlertRecord>> activeAlerts({int? limit}) async {
    final rows = await db.query(
      LocalTables.alertHistory,
      where: '${LocalColumns.status} != ? AND ${LocalColumns.status} != ?',
      whereArgs: [AlertStatus.resolved.name, AlertStatus.expired.name],
      orderBy: '${LocalColumns.detectedAtUtc} DESC',
      limit: limit,
    );
    return rows.map(LocalMappers.alertFromRow).toList(growable: false);
  }

  @override
  Future<void> updateStatus(String fingerprint, AlertStatus status) async {
    final existing = await alertByFingerprint(fingerprint);
    if (existing == null) return;
    final updated = existing.copyWith(
      status: status,
      updatedAtUtc: DateTime.now().toUtc(),
      resolvedAtUtc: status == AlertStatus.resolved ||
              status == AlertStatus.expired
          ? DateTime.now().toUtc()
          : null,
    );
    await upsertAlert(updated);
  }

  @override
  Future<void> markResolved(String fingerprint, {DateTime? at}) async {
    final existing = await alertByFingerprint(fingerprint);
    if (existing == null) return;
    final resolvedAt = (at ?? DateTime.now()).toUtc();
    await upsertAlert(
      existing.copyWith(
        status: AlertStatus.resolved,
        updatedAtUtc: resolvedAt,
        resolvedAtUtc: resolvedAt,
      ),
    );
  }

  @override
  Future<void> markAcknowledged(String fingerprint) async {
    final existing = await alertByFingerprint(fingerprint);
    if (existing == null) return;
    await upsertAlert(
      existing.copyWith(
        acknowledged: true,
        updatedAtUtc: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<int> purgeOlderThan(DateTime cutoff) async {
    final threshold = cutoff.toUtc().millisecondsSinceEpoch;
    return db.delete(
      LocalTables.alertHistory,
      where: '${LocalColumns.detectedAtUtc} < ?',
      whereArgs: [threshold],
    );
  }

  @override
  Future<void> clear() async {
    await db.delete(LocalTables.alertHistory);
  }
}