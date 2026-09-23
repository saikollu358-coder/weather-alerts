import '../../core/utils/logger.dart';
import '../../domain/entities/monitored_location_record.dart';
import '../../domain/repositories/monitored_location_repository.dart';
import '../datasources/local/database_schema.dart';
import '../datasources/local/local_database.dart';
import '../models/local_models.dart';

/// SQLite-backed [MonitoredLocationRepository].
class MonitoredLocationRepositoryImpl implements MonitoredLocationRepository {
  MonitoredLocationRepositoryImpl({required this.db, this.logger});

  final LocalDatabase db;
  final AppLogger? logger;

  @override
  Future<List<MonitoredLocationRecord>> allLocations() async {
    final rows = await db.query(
      LocalTables.monitoredLocations,
      orderBy:
          '${LocalColumns.lastUsedAtUtc} IS NULL, ${LocalColumns.lastUsedAtUtc} DESC, ${LocalColumns.id} DESC',
    );
    return rows.map(LocalMappers.locationFromRow).toList(growable: false);
  }

  @override
  Future<MonitoredLocationRecord?> locationById(int id) async {
    final rows = await db.query(
      LocalTables.monitoredLocations,
      where: '${LocalColumns.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalMappers.locationFromRow(rows.first);
  }

  @override
  Future<MonitoredLocationRecord?> byCoordinates(
    double latitude,
    double longitude,
  ) async {
    final rows = await db.query(
      LocalTables.monitoredLocations,
      where: '${LocalColumns.latitude} = ? AND ${LocalColumns.longitude} = ?',
      whereArgs: [latitude, longitude],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalMappers.locationFromRow(rows.first);
  }

  @override
  Future<int> addLocation(MonitoredLocationRecord record) async {
    return db.insert(
      LocalTables.monitoredLocations,
      LocalMappers.locationToRow(record),
    );
  }

  @override
  Future<void> updateLocation(MonitoredLocationRecord record) async {
    final id = record.id;
    if (id == null) {
      throw ArgumentError('Cannot update a location without an id.');
    }
    final values = LocalMappers.locationToRow(record)..remove(LocalColumns.id);
    await db.update(
      LocalTables.monitoredLocations,
      values,
      where: '${LocalColumns.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> removeLocation(int id) async {
    await db.delete(
      LocalTables.monitoredLocations,
      where: '${LocalColumns.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> setMonitored(int id, {required bool monitored}) async {
    await db.update(
      LocalTables.monitoredLocations,
      {
        LocalColumns.isMonitored: monitored ? 1 : 0,
        LocalColumns.updatedAtUtc: DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: '${LocalColumns.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> setPrimary(int id) async {
    await db.transaction((ops) async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      // Only one primary location may exist at a time.
      await ops.update(LocalTables.monitoredLocations, {
        LocalColumns.isPrimary: 0,
        LocalColumns.updatedAtUtc: now,
      });
      await ops.update(
        LocalTables.monitoredLocations,
        {
          LocalColumns.isPrimary: 1,
          LocalColumns.isMonitored: 1,
          LocalColumns.updatedAtUtc: now,
          LocalColumns.lastUsedAtUtc: now,
        },
        where: '${LocalColumns.id} = ?',
        whereArgs: [id],
      );
    });
    logger?.debug('MonitoredLocationRepository', 'primary location set to #$id');
  }

  @override
  Future<MonitoredLocationRecord?> primaryLocation() async {
    final rows = await db.query(
      LocalTables.monitoredLocations,
      where: '${LocalColumns.isPrimary} = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : LocalMappers.locationFromRow(rows.first);
  }

  @override
  Future<MonitoredLocationRecord?> monitoredLocation() async {
    final rows = await db.query(
      LocalTables.monitoredLocations,
      where: '${LocalColumns.isMonitored} = 1',
      orderBy: '${LocalColumns.lastUsedAtUtc} DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : LocalMappers.locationFromRow(rows.first);
  }

  @override
  Future<void> touchLastUsed(int id, {DateTime? at}) async {
    await db.update(
      LocalTables.monitoredLocations,
      {
        LocalColumns.lastUsedAtUtc:
            (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
        LocalColumns.updatedAtUtc: DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: '${LocalColumns.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> clear() async {
    await db.delete(LocalTables.monitoredLocations);
  }
}