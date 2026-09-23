import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/cached_forecast_entry.dart';
import '../../domain/entities/cached_weather_entry.dart';
import '../../domain/repositories/weather_cache_repository.dart';
import '../datasources/local/database_schema.dart';
import '../datasources/local/local_database.dart';
import '../models/local_models.dart';

/// SQLite-backed [WeatherCacheRepository].
class WeatherCacheRepositoryImpl implements WeatherCacheRepository {
  WeatherCacheRepositoryImpl({required this.db, this.logger});

  final LocalDatabase db;
  final AppLogger? logger;

  @override
  Future<void> saveCurrentWeather(CachedWeatherEntry entry) async {
    await db.insert(
      LocalTables.cachedWeather,
      LocalMappers.cachedWeatherToRow(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<CachedWeatherEntry?> currentWeather(String locationKey) async {
    final rows = await db.query(
      LocalTables.cachedWeather,
      where: '${LocalColumns.locationKey} = ?',
      whereArgs: [locationKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalMappers.cachedWeatherFromRow(rows.first);
  }

  @override
  Future<bool> hasFreshCurrentWeather(
    String locationKey,
    Duration maxAge, {
    DateTime? at,
  }) async {
    final entry = await currentWeather(locationKey);
    if (entry == null) return false;
    final now = (at ?? DateTime.now()).toUtc();
    if (entry.expiresAtUtc != null) return !entry.isStale(now: now);
    return now.difference(entry.fetchedAtUtc.toUtc()) <= maxAge;
  }

  @override
  Future<void> saveForecast(CachedForecastEntry entry) async {
    await db.insert(
      LocalTables.cachedForecast,
      LocalMappers.cachedForecastToRow(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<CachedForecastEntry?> forecast(
    String locationKey,
    ForecastType type,
  ) async {
    final rows = await db.query(
      LocalTables.cachedForecast,
      where: '${LocalColumns.locationKey} = ? AND ${LocalColumns.forecastType} = ?',
      whereArgs: [locationKey, type.name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalMappers.cachedForecastFromRow(rows.first);
  }

  @override
  Future<bool> hasFreshForecast(
    String locationKey,
    ForecastType type,
    Duration maxAge, {
    DateTime? at,
  }) async {
    final entry = await forecast(locationKey, type);
    if (entry == null) return false;
    final now = (at ?? DateTime.now()).toUtc();
    if (entry.expiresAtUtc != null) return !entry.isStale(now: now);
    return now.difference(entry.fetchedAtUtc.toUtc()) <= maxAge;
  }

  @override
  Future<void> deleteLocation(String locationKey) async {
    await db.transaction((ops) async {
      await ops.delete(
        LocalTables.cachedWeather,
        where: '${LocalColumns.locationKey} = ?',
        whereArgs: [locationKey],
      );
      await ops.delete(
        LocalTables.cachedForecast,
        where: '${LocalColumns.locationKey} = ?',
        whereArgs: [locationKey],
      );
    });
  }

  @override
  Future<void> clear() async {
    await db.transaction((ops) async {
      await ops.delete(LocalTables.cachedWeather);
      await ops.delete(LocalTables.cachedForecast);
    });
    logger?.debug('WeatherCacheRepository', 'cleared weather + forecast cache');
  }
}