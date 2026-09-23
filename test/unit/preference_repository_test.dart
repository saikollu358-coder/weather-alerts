import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/datasources/local/local_database_io.dart';
import 'package:weather_alerts/data/repositories/preference_repository_impl.dart';

import '../helpers/test_database.dart';

void main() {
  late SqfliteDatabase db;
  late Directory dir;
  late PreferenceRepositoryImpl repository;

  setUp(() async {
    final created = await createTestDatabase();
    db = created.$1;
    dir = created.$2;
    repository = PreferenceRepositoryImpl(
      db: db,
      logger: AppLogger(enabled: false),
    );
  });

  tearDown(() async => teardownTestDatabase(db, dir));

  test('read returns null when unset', () async {
    expect(await repository.read('missing'), isNull);
    expect(await repository.get('missing'), isNull);
  });

  test('write then read round-trips values', () async {
    await repository.write('temperature_unit', 'celsius');
    expect(await repository.read('temperature_unit'), 'celsius');

    final record = await repository.get('temperature_unit');
    expect(record!.key, 'temperature_unit');
    expect(record.value, 'celsius');
    expect(record.updatedAtUtc, isNotNull);
  });

  test('overwrite updates the value and bumps updatedAtUtc', () async {
    await repository.write('theme', 'light');
    final first = await repository.get('theme');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await repository.write('theme', 'dark');

    final second = await repository.get('theme');
    expect(second!.value, 'dark');
    expect(
      second.updatedAtUtc.isAfter(first!.updatedAtUtc),
      isTrue,
    );
    // Single physical row.
    expect(await db.query('user_preferences'), hasLength(1));
  });

  test('delete removes the preference', () async {
    await repository.write('key', 'value');
    await repository.delete('key');
    expect(await repository.read('key'), isNull);
  });

  test('all returns every preference sorted by key', () async {
    await repository.write('z', '1');
    await repository.write('a', '2');
    await repository.write('m', '3');

    final all = await repository.all();
    expect(all.map((p) => p.key).toList(), ['a', 'm', 'z']);
  });
}