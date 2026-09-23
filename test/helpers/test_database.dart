import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weather_alerts/data/datasources/local/local_database_io.dart';

/// Opens a throwaway SQLite database backed by FFI for unit tests.
///
/// Returns a record of the database and its temporary directory; tear down
/// with [teardownTestDatabase].
Future<(SqfliteDatabase, Directory)> createTestDatabase() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('weather_alerts_test_');
  final path =
      '${dir.path}${Platform.pathSeparator}weather_alerts_test.db';
  final db = SqfliteDatabase(factory: databaseFactoryFfi, databasePath: path);
  await db.ensureOpen();
  return (db, dir);
}

/// Closes and deletes the database plus its temporary directory.
Future<void> teardownTestDatabase(
  SqfliteDatabase db,
  Directory dir,
) async {
  await db.deleteDatabase();
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}