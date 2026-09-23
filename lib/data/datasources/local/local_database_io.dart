import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/storage_exception.dart';
import '../../../core/utils/logger.dart';
import 'database_schema.dart';
import 'local_database.dart';

/// sqflite-backed [LocalDatabase] for native platforms (Android/iOS/desktop).
///
/// This file is only compiled on targets where `dart:io` exists (see the
/// conditional import in `local_database_factory.dart`), so it may safely use
/// sqflite and the file system.
class SqfliteDatabase implements LocalDatabase {
  SqfliteDatabase({DatabaseFactory? factory, String? databasePath, this.logger})
      : _factory = factory ?? databaseFactory,
        path = databasePath;

  /// Default database file name inside the platform databases directory.
  static const String defaultDatabaseName = 'weather_alerts.db';

  final DatabaseFactory _factory;
  final String? path;
  final AppLogger? logger;

  Database? _database;
  Future<Database>? _opening;
  String? _resolvedPath;

  @override
  bool get isAvailable => true;

  @override
  String get databasePath => _resolvedPath ?? path ?? '';

  @override
  Future<void> ensureOpen() async {
    await _open();
  }

  /// Resolves the database handle, opening it on first use.
  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;
    final opening = _opening;
    if (opening != null) return opening;

    final future = _doOpen();
    _opening = future;
    try {
      final db = await future;
      _database = db;
      return db;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _doOpen() async {
    try {
      final dbPath = path ??
          _resolvedPath ??
          p.join(await _factory.getDatabasesPath(), defaultDatabaseName);
      if (dbPath != ':memory:') {
        await _ensureParentDirectory(File(dbPath).parent);
      }
      _resolvedPath = dbPath;
      logger?.debug('LocalDatabase', 'opening SQLite at $dbPath');
      final db = await _factory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: DatabaseSchema.schemaVersion,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: DatabaseSchema.onCreate,
          onUpgrade: DatabaseSchema.onUpgrade,
        ),
      );
      return db;
    } on AppException {
      rethrow;
    } catch (e) {
      logger?.error('LocalDatabase', 'open failed', e);
      throw DatabaseOpenException(cause: e);
    }
  }

  static Future<void> _ensureParentDirectory(Directory dir) async {
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } on FileSystemException {
      // Some platforms disallow pre-creating the databases dir; sqflite
      // surfaces a clearer error if the database genuinely cannot open.
    }
  }

  @override
  Future<T> transaction<T>(
      Future<T> Function(DatabaseOperations ops) action) async {
    final db = await _open();
    try {
      return await db.transaction((txn) => action(_Session(txn)));
    } on AppException {
      rethrow;
    } catch (e) {
      logger?.error('LocalDatabase', 'transaction failed', e);
      throw StorageWriteException(cause: e);
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    String? groupBy,
    String? having,
    int? limit,
    int? offset,
  }) async {
    final db = await _open();
    try {
      return await db.query(
        table,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        groupBy: groupBy,
        having: having,
        limit: limit,
        offset: offset,
      );
    } on AppException {
      rethrow;
    } catch (e) {
      logger?.error('LocalDatabase', 'query failed', e);
      throw StorageReadException(cause: e);
    }
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
  }) async {
    final db = await _open();
    try {
      return await db.insert(table, values, conflictAlgorithm: conflictAlgorithm);
    } on AppException {
      rethrow;
    } catch (e) {
      logger?.error('LocalDatabase', 'insert failed', e);
      throw StorageWriteException(cause: e);
    }
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await _open();
    try {
      return await db.update(table, values, where: where, whereArgs: whereArgs);
    } on AppException {
      rethrow;
    } catch (e) {
      logger?.error('LocalDatabase', 'update failed', e);
      throw StorageWriteException(cause: e);
    }
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await _open();
    try {
      return await db.delete(table, where: where, whereArgs: whereArgs);
    } on AppException {
      rethrow;
    } catch (e) {
      logger?.error('LocalDatabase', 'delete failed', e);
      throw StorageWriteException(cause: e);
    }
  }

  @override
  Future<bool> tableExists(String table) async {
    final db = await _open();
    try {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        [table],
      );
      return rows.isNotEmpty;
    } on AppException {
      rethrow;
    } catch (e) {
      logger?.error('LocalDatabase', 'table check failed', e);
      throw StorageReadException(cause: e);
    }
  }

  @override
  Future<void> close() async {
    final db = _database;
    _database = null;
    _opening = null;
    if (db != null) {
      await db.close();
    }
  }

  @override
  Future<void> deleteDatabase() async {
    await close();
    final dbPath = _resolvedPath ?? path;
    _resolvedPath = null;
    if (dbPath != null && dbPath.isNotEmpty && dbPath != ':memory:') {
      await _factory.deleteDatabase(dbPath);
    }
  }
}

/// sqflite executor adapter exposing the platform-agnostic operations surface
/// (works for both [Database] and [Transaction]).
class _Session implements DatabaseOperations {
  _Session(this._executor);

  final DatabaseExecutor _executor;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    String? groupBy,
    String? having,
    int? limit,
    int? offset,
  }) {
    return _executor.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      groupBy: groupBy,
      having: having,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
  }) {
    return _executor.insert(
      table,
      values,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    return _executor.update(table, values, where: where, whereArgs: whereArgs);
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    return _executor.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    return _executor.execute(sql, arguments);
  }
}

/// Creates the platform-local [LocalDatabase] (native: sqflite-backed).
LocalDatabase createLocalDatabase({String? databasePath}) =>
    SqfliteDatabase(databasePath: databasePath);