import 'package:sqflite_common/sqlite_api.dart';

/// Platform-agnostic operations exposed by the local SQLite database.
///
/// A valid implementation is bound to a concrete (live or transactional)
/// connection and allows repositories to run statements inside a transaction
/// without depending on a specific SQLite package.
abstract interface class DatabaseOperations {
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
  });

  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
  });

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<void> execute(String sql, [List<Object?>? arguments]);
}

/// The local SQLite database abstraction used by every local repository.
///
/// On native platforms the implementation uses sqflite. On web (where
/// SQLite is not available without a WASM/worker build) the implementation is
/// a graceful no-op that reports a user-safe error, mirroring the optional
/// Firebase degradation pattern.
abstract interface class LocalDatabase {
  /// Resolved database file path (empty on platforms without SQLite).
  String get databasePath;

  /// True when the database can be opened on this platform.
  bool get isAvailable;

  /// Opens (and migrates) the database; idempotent and safe to call
  /// repeatedly. Throws [AppException] subclasses on failure.
  Future<void> ensureOpen();

  /// Runs [action] atomically on a scoped set of operations.
  Future<T> transaction<T>(Future<T> Function(DatabaseOperations ops) action);

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
  });

  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
  });

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<bool> tableExists(String table);

  /// Closes the database (subsequent calls reopen it).
  Future<void> close();

  /// Closes and deletes the database file and all stored data.
  Future<void> deleteDatabase();
}