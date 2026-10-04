import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weather_alerts/core/errors/storage_exception.dart';
import 'package:weather_alerts/data/datasources/local/database_schema.dart';
import 'package:weather_alerts/data/datasources/local/local_database.dart';
import 'package:weather_alerts/data/datasources/local/local_database_factory.dart';
import 'package:weather_alerts/data/datasources/local/local_database_io.dart';
import 'package:weather_alerts/data/datasources/local/local_database_unavailable.dart';

import '../helpers/test_database.dart';

void main() {
  group('DatabaseSchema', () {
    test('current schema version is 3 with incremental migrations', () {
      expect(DatabaseSchema.schemaVersion, 3);
      expect(DatabaseSchema.baseSchemaVersion, 1);
      expect(DatabaseSchema.v2Statements, isNotEmpty);
      expect(DatabaseSchema.v3Statements, isNotEmpty);
    });
  });

  group('SqfliteDatabase', () {
    late SqfliteDatabase db;
    late Directory dir;

    setUp(() async {
      final created = await createTestDatabase();
      db = created.$1;
      dir = created.$2;
    });
    tearDown(() async => teardownTestDatabase(db, dir));

    test('creates all expected tables', () async {
      for (final table in [
        LocalTables.cachedWeather,
        LocalTables.cachedForecast,
        LocalTables.alertHistory,
        LocalTables.userPreferences,
        LocalTables.notificationState,
      ]) {
        expect(await db.tableExists(table), isTrue, reason: table);
      }
    });

    test('does not create the retired cloud sync or saved location tables',
        () async {
      expect(await db.tableExists(LocalTables.syncState), isFalse);
      expect(await db.tableExists(LocalTables.monitoredLocations), isFalse);
    });

    test('ensureOpen is idempotent and reopens after close', () async {
      await db.ensureOpen();
      await db.ensureOpen();
      await db.close();
      // Reopening after close must succeed.
      await db.ensureOpen();
      expect(db.isAvailable, isTrue);
    });

    test('deleteDatabase removes the database file', () async {
      final path = db.databasePath;
      expect(File(path).existsSync(), isTrue);
      await db.deleteDatabase();
      expect(File(path).existsSync(), isFalse);
    });

    test('transaction rolls back when the body throws', () async {
      await db.insert('user_preferences', {
        'pref_key': 'a',
        'pref_value': '1',
        'updated_at_utc': 0,
      });
      // The body error is surfaced as a user-safe storage error, and the
      // transaction must be rolled back so 'b' never persists.
      await expectLater(
        db.transaction((ops) async {
          await ops.insert('user_preferences', {
            'pref_key': 'b',
            'pref_value': '2',
            'updated_at_utc': 0,
          });
          throw StateError('boom');
        }),
        throwsA(isA<StorageWriteException>()),
      );
      // 'b' must not have been committed.
      final row = (await db.query(
        'user_preferences',
        where: 'pref_key = ?',
        whereArgs: ['b'],
      ));
      expect(row, isEmpty);
    });

    test(
      'migrates a v1 database to the current schema, preserving data',
      () async {
        sqfliteFfiInit();
        final dir = await Directory.systemTemp.createTemp(
          'weather_alerts_mig_',
        );
        final path = p.join(dir.path, 'migration.db');
        final v1 = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) => DatabaseSchema.onCreateV1(db, 1),
          ),
        );
        await v1.execute(
          'INSERT INTO user_preferences(pref_key, pref_value, updated_at_utc) '
          'VALUES (?, ?, ?)',
          ['theme', 'dark', 0],
        );
        await v1.close();

        final migrated = SqfliteDatabase(
          factory: databaseFactoryFfi,
          databasePath: path,
        );
        await migrated.ensureOpen();

        // The v1 -> v2 -> v3 chain ran: the v2 tables landed and were then
        // dropped again by v3, since cloud sync and saved places are gone.
        expect(await migrated.tableExists(LocalTables.syncState), isFalse);
        expect(await migrated.tableExists(LocalTables.monitoredLocations), isFalse);
        // Existing v1 data survived the migration.
        final rows = await migrated.query(
          LocalTables.userPreferences,
          where: 'pref_key = ?',
          whereArgs: ['theme'],
        );
        expect(rows, hasLength(1));
        expect(rows.first['pref_value'], 'dark');

        await migrated.deleteDatabase();
        await dir.delete(recursive: true);
      },
    );
  });

  group('UnavailableLocalDatabase (web fallback)', () {
    test('keeps a browser-safe in-memory database usable', () async {
      final db = const UnavailableLocalDatabase();
      await db.ensureOpen();
      expect(db.isAvailable, isTrue);
      expect(db.databasePath, isNotEmpty);

      final id = await db.insert('user_preferences', {
        'pref_key': 'theme',
        'pref_value': 'dark',
        'updated_at_utc': 42,
      });
      final rows = await db.query(
        'user_preferences',
        where: 'pref_key = ?',
        whereArgs: ['theme'],
      );

      expect(id, greaterThan(0));
      expect(rows, hasLength(1));
      expect(rows.first['pref_value'], 'dark');
    });

    test(
      'platform factory returns a working database on this (IO) host',
      () async {
        databaseFactory = databaseFactoryFfi;
        final db = createPlatformLocalDatabase();
        addTearDown(() => db.deleteDatabase());
        expect(db, isA<LocalDatabase>());
        await db.ensureOpen();
        expect(db.isAvailable, isTrue);
      },
    );
  });
}
