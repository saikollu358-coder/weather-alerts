import 'dart:convert';

import '../../domain/entities/alert_record.dart';
import '../../domain/entities/alert_status.dart';
import '../../domain/entities/cached_forecast_entry.dart';
import '../../domain/entities/cached_weather_entry.dart';
import '../../domain/entities/notification_state_record.dart';
import '../../domain/entities/user_preference.dart';
import '../datasources/local/database_schema.dart';

/// Row <-> entity mappers for every local SQLite table.
///
/// All timestamps are stored as UTC milliseconds since epoch integers;
/// payloads are stored as JSON strings.
abstract final class LocalMappers {
  LocalMappers._();

  static int _epochMs(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  static DateTime _fromEpochMs(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  static DateTime? _nullableDate(Object? value) =>
      value is int ? _fromEpochMs(value) : null;

  static String _json(Object? value) => jsonEncode(value);

  static Map<String, dynamic> _payload(String raw) =>
      (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));

  // -------------------------------------------------------------
  // cached_weather
  // -------------------------------------------------------------

  static Map<String, Object?> cachedWeatherToRow(CachedWeatherEntry entry) => {
        LocalColumns.locationKey: entry.locationKey,
        LocalColumns.payload: _json(entry.payload),
        LocalColumns.dataSource: entry.dataSource,
        LocalColumns.dataVersion: entry.dataVersion,
        LocalColumns.fetchedAtUtc: _epochMs(entry.fetchedAtUtc),
        LocalColumns.expiresAtUtc: entry.expiresAtUtc != null
            ? _epochMs(entry.expiresAtUtc!)
            : null,
      };

  static CachedWeatherEntry cachedWeatherFromRow(Map<String, Object?> row) =>
      CachedWeatherEntry(
        locationKey: row[LocalColumns.locationKey]! as String,
        payload: _payload(row[LocalColumns.payload]! as String),
        dataSource: row[LocalColumns.dataSource]! as String,
        dataVersion: row[LocalColumns.dataVersion]! as int,
        fetchedAtUtc: _fromEpochMs(row[LocalColumns.fetchedAtUtc]! as int),
        expiresAtUtc: _nullableDate(row[LocalColumns.expiresAtUtc]),
      );

  // -------------------------------------------------------------
  // cached_forecast
  // -------------------------------------------------------------

  static Map<String, Object?> cachedForecastToRow(CachedForecastEntry entry) => {
        LocalColumns.locationKey: entry.locationKey,
        LocalColumns.forecastType: entry.type.name,
        LocalColumns.payload: _json(entry.payload),
        LocalColumns.dataSource: entry.dataSource,
        LocalColumns.dataVersion: entry.dataVersion,
        LocalColumns.fetchedAtUtc: _epochMs(entry.fetchedAtUtc),
        LocalColumns.expiresAtUtc: entry.expiresAtUtc != null
            ? _epochMs(entry.expiresAtUtc!)
            : null,
      };

  static CachedForecastEntry cachedForecastFromRow(
          Map<String, Object?> row) =>
      CachedForecastEntry(
        locationKey: row[LocalColumns.locationKey]! as String,
        type: ForecastType.values.byName(row[LocalColumns.forecastType]! as String),
        payload: _payload(row[LocalColumns.payload]! as String),
        dataSource: row[LocalColumns.dataSource]! as String,
        dataVersion: row[LocalColumns.dataVersion]! as int,
        fetchedAtUtc: _fromEpochMs(row[LocalColumns.fetchedAtUtc]! as int),
        expiresAtUtc: _nullableDate(row[LocalColumns.expiresAtUtc]),
      );

  // -------------------------------------------------------------
  // alert_history
  // -------------------------------------------------------------

  static Map<String, Object?> alertToRow(AlertRecord alert) => {
        LocalColumns.fingerprint: alert.fingerprint,
        LocalColumns.hazard: alert.hazard,
        LocalColumns.severity: alert.severity,
        LocalColumns.status: alert.status.name,
        LocalColumns.title: alert.title,
        LocalColumns.description: alert.description,
        LocalColumns.reason: alert.reason,
        LocalColumns.payload: _json(alert.payload),
        LocalColumns.locationKey: alert.locationKey,
        LocalColumns.detectedAtUtc: _epochMs(alert.detectedAtUtc),
        LocalColumns.updatedAtUtc: _epochMs(alert.updatedAtUtc),
        LocalColumns.resolvedAtUtc:
            alert.resolvedAtUtc != null ? _epochMs(alert.resolvedAtUtc!) : null,
        LocalColumns.expiresAtUtc:
            alert.expiresAtUtc != null ? _epochMs(alert.expiresAtUtc!) : null,
        LocalColumns.acknowledged: alert.acknowledged ? 1 : 0,
      };

  static AlertRecord alertFromRow(Map<String, Object?> row) => AlertRecord(
        fingerprint: row[LocalColumns.fingerprint]! as String,
        hazard: row[LocalColumns.hazard]! as String,
        severity: row[LocalColumns.severity]! as String,
        status: AlertStatus.values.byName(row[LocalColumns.status]! as String),
        title: row[LocalColumns.title]! as String,
        description: row[LocalColumns.description]! as String,
        reason: row[LocalColumns.reason]! as String,
        locationKey: row[LocalColumns.locationKey]! as String,
        payload: _payload(row[LocalColumns.payload]! as String),
        detectedAtUtc: _fromEpochMs(row[LocalColumns.detectedAtUtc]! as int),
        updatedAtUtc: _fromEpochMs(row[LocalColumns.updatedAtUtc]! as int),
        resolvedAtUtc: _nullableDate(row[LocalColumns.resolvedAtUtc]),
        expiresAtUtc: _nullableDate(row[LocalColumns.expiresAtUtc]),
        acknowledged: (row[LocalColumns.acknowledged] as int) == 1,
      );

  // -------------------------------------------------------------
  // user_preferences
  // -------------------------------------------------------------

  static Map<String, Object?> preferenceToRow(UserPreference preference) => {
        LocalColumns.prefKey: preference.key,
        LocalColumns.prefValue: preference.value,
        LocalColumns.updatedAtUtc: _epochMs(preference.updatedAtUtc),
      };

  static UserPreference preferenceFromRow(Map<String, Object?> row) =>
      UserPreference(
        key: row[LocalColumns.prefKey]! as String,
        value: row[LocalColumns.prefValue]! as String,
        updatedAtUtc: _fromEpochMs(row[LocalColumns.updatedAtUtc]! as int),
      );

  // -------------------------------------------------------------
  // notification_state
  // -------------------------------------------------------------

  static Map<String, Object?> notificationStateToRow(
          NotificationStateRecord record) =>
      {
        LocalColumns.fingerprint: record.fingerprint,
        LocalColumns.lastNotifiedAtUtc: _epochMs(record.lastNotifiedAtUtc),
        LocalColumns.notificationCount: record.notificationCount,
        LocalColumns.status: record.status,
        LocalColumns.updatedAtUtc:
            _epochMs(record.updatedAtUtc ?? record.lastNotifiedAtUtc),
      };

  static NotificationStateRecord notificationStateFromRow(
          Map<String, Object?> row) =>
      NotificationStateRecord(
        fingerprint: row[LocalColumns.fingerprint]! as String,
        lastNotifiedAtUtc:
            _fromEpochMs(row[LocalColumns.lastNotifiedAtUtc]! as int),
        notificationCount: row[LocalColumns.notificationCount]! as int,
        status: row[LocalColumns.status]! as String,
        updatedAtUtc:
            _fromEpochMs(row[LocalColumns.updatedAtUtc]! as int),
      );
}