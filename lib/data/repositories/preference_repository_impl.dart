import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/user_preference.dart';
import '../../domain/repositories/preference_repository.dart';
import '../datasources/local/database_schema.dart';
import '../datasources/local/local_database.dart';
import '../models/local_models.dart';

/// SQLite-backed [PreferenceRepository].
class PreferenceRepositoryImpl implements PreferenceRepository {
  PreferenceRepositoryImpl({required this.db, this.logger});

  final LocalDatabase db;
  final AppLogger? logger;

  @override
  Future<String?> read(String key) async {
    final preference = await get(key);
    return preference?.value;
  }

  @override
  Future<UserPreference?> get(String key) async {
    final rows = await db.query(
      LocalTables.userPreferences,
      where: '${LocalColumns.prefKey} = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalMappers.preferenceFromRow(rows.first);
  }

  @override
  Future<void> write(String key, String value) async {
    await db.insert(
      LocalTables.userPreferences,
      LocalMappers.preferenceToRow(
        UserPreference(key: key, value: value, updatedAtUtc: DateTime.now().toUtc()),
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String key) async {
    await db.delete(
      LocalTables.userPreferences,
      where: '${LocalColumns.prefKey} = ?',
      whereArgs: [key],
    );
  }

  @override
  Future<List<UserPreference>> all() async {
    final rows = await db.query(
      LocalTables.userPreferences,
      orderBy: '${LocalColumns.prefKey} ASC',
    );
    return rows.map(LocalMappers.preferenceFromRow).toList(growable: false);
  }
}