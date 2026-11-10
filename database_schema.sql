-- ============================================================================
-- Weather Alerts - local SQLite schema + sample records
-- ----------------------------------------------------------------------------
-- Database file : weather_alerts.db
-- Schema version: 3 (see lib/data/datasources/local/database_schema.dart)
-- Engine        : SQLite 3
--
-- Timestamps are stored as UTC milliseconds since epoch (INTEGER).
-- JSON columns (payload / pref_value) hold JSON encoded as TEXT.
--
-- This is a standalone schema + seed script. It DROPS and recreates the
-- current tables, so run it only against a scratch/dev database, never
-- against a device database that holds real data.
-- ============================================================================

PRAGMA foreign_keys = ON;
PRAGMA user_version = 3;

-- ----------------------------------------------------------------------------
-- Schema (current v3)
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS notification_state;
DROP TABLE IF EXISTS user_preferences;
DROP TABLE IF EXISTS alert_history;
DROP TABLE IF EXISTS cached_forecast;
DROP TABLE IF EXISTS cached_weather;

-- Current weather snapshot per location.
CREATE TABLE cached_weather (
  location_key    TEXT    NOT NULL PRIMARY KEY,
  payload         TEXT    NOT NULL,
  data_source     TEXT    NOT NULL,
  data_version    INTEGER NOT NULL DEFAULT 1,
  fetched_at_utc  INTEGER NOT NULL,
  expires_at_utc  INTEGER
);

-- Hourly/daily forecast slices per location.
CREATE TABLE cached_forecast (
  location_key    TEXT    NOT NULL,
  forecast_type   TEXT    NOT NULL,
  payload         TEXT    NOT NULL,
  data_source     TEXT    NOT NULL,
  data_version    INTEGER NOT NULL DEFAULT 1,
  fetched_at_utc  INTEGER NOT NULL,
  expires_at_utc  INTEGER,
  PRIMARY KEY (location_key, forecast_type)
);

-- Every detected/served alert, including resolved and expired rows used for
-- deduplication and escalation tracking.
CREATE TABLE alert_history (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  fingerprint     TEXT    NOT NULL UNIQUE,
  hazard          TEXT    NOT NULL,
  severity        TEXT    NOT NULL,
  status          TEXT    NOT NULL,
  title           TEXT    NOT NULL,
  description     TEXT    NOT NULL,
  reason          TEXT    NOT NULL,
  payload         TEXT    NOT NULL DEFAULT '{}',
  location_key    TEXT    NOT NULL,
  detected_at_utc INTEGER NOT NULL,
  updated_at_utc  INTEGER NOT NULL,
  resolved_at_utc INTEGER,
  expires_at_utc  INTEGER,
  acknowledged    INTEGER NOT NULL DEFAULT 0
);

-- Simple key/value settings, including `device_id` and `last_known_location`.
CREATE TABLE user_preferences (
  pref_key        TEXT    NOT NULL PRIMARY KEY,
  pref_value      TEXT    NOT NULL,
  updated_at_utc  INTEGER NOT NULL
);

-- Notification delivery tracking (count, cooldown).
CREATE TABLE notification_state (
  fingerprint          TEXT    NOT NULL PRIMARY KEY,
  last_notified_at_utc INTEGER NOT NULL,
  notification_count   INTEGER NOT NULL DEFAULT 1,
  status               TEXT    NOT NULL DEFAULT 'sent',
  updated_at_utc       INTEGER NOT NULL
);

CREATE INDEX idx_cached_forecast_fetched ON cached_forecast(fetched_at_utc);
CREATE INDEX idx_alert_history_status    ON alert_history(status);
CREATE INDEX idx_alert_history_detected  ON alert_history(detected_at_utc);
CREATE INDEX idx_notification_updated    ON notification_state(updated_at_utc);

-- ----------------------------------------------------------------------------
-- Sample records
-- ----------------------------------------------------------------------------

-- Location used by every sample row below (Pune, Maharashtra, India).
-- location_key format is "<latitude>,<longitude>" (4 dp, see GeoPosition).

-- Current weather (fetched 2026-11-10T06:00:00Z, expires 06:30Z).
INSERT INTO cached_weather (
  location_key, payload, data_source, data_version,
  fetched_at_utc, expires_at_utc
) VALUES (
  '18.5204,73.8567',
  '{"time":"2026-11-10T06:00:00.000Z","temperature_2m":31.4,"relative_humidity_2m":68,"apparent_temperature":36.1,"is_day":true,"precipitation":0.0,"weather_code":2,"wind_speed_10m":14.8,"wind_direction_10m":225,"wind_gusts_10m":38.2}',
  'open-meteo', 1,
  1794290400000, 1794292200000
);

-- Hourly forecast (fetched 2026-11-10T06:00:00Z, expires 09:00Z).
INSERT INTO cached_forecast (
  location_key, forecast_type, payload, data_source, data_version,
  fetched_at_utc, expires_at_utc
) VALUES (
  '18.5204,73.8567',
  'hourly',
  '{"points":[{"time":"2026-11-10T07:00:00.000Z","temperature_2m":31.9,"precipitation_probability":10,"weather_code":2,"wind_speed_10m":16.2},{"time":"2026-11-10T08:00:00.000Z","temperature_2m":32.3,"precipitation_probability":35,"weather_code":95,"wind_speed_10m":24.6},{"time":"2026-11-10T09:00:00.000Z","temperature_2m":31.1,"precipitation_probability":80,"weather_code":95,"wind_speed_10m":41.0}]}',
  'open-meteo', 1,
  1794290400000, 1794301200000
);

-- Daily forecast (fetched 2026-11-10T06:00:00Z, expires 09:00Z).
INSERT INTO cached_forecast (
  location_key, forecast_type, payload, data_source, data_version,
  fetched_at_utc, expires_at_utc
) VALUES (
  '18.5204,73.8567',
  'daily',
  '{"points":[{"time":"2026-11-10T00:00:00.000Z","weather_code":95,"temperature_2m_max":33.0,"temperature_2m_min":22.4,"precipitation_sum":18.6,"precipitation_probability_max":80},{"time":"2026-11-11T00:00:00.000Z","weather_code":61,"temperature_2m_max":30.2,"temperature_2m_min":21.8,"precipitation_sum":9.4,"precipitation_probability_max":60},{"time":"2026-11-12T00:00:00.000Z","weather_code":3,"temperature_2m_max":31.6,"temperature_2m_min":21.1,"precipitation_sum":0.0,"precipitation_probability_max":20}]}',
  'open-meteo', 1,
  1794290400000, 1794301200000
);

-- Alert 1: active thunderstorm, detected 2026-11-10T08:00:00Z.
INSERT INTO alert_history (
  fingerprint, hazard, severity, status, title, description, reason,
  payload, location_key, detected_at_utc, updated_at_utc,
  resolved_at_utc, expires_at_utc, acknowledged
) VALUES (
  'v1:thunderstorm:18.5204,73.8567:2026-11-10T08:00:00.000Z',
  'thunderstorm', 'high', 'detected',
  'High Thunderstorm',
  'Thunderstorm activity expected within 24 h.',
  'Thunderstorm activity expected within 24 h.',
  '{"value":null,"unit":null,"rulesVersion":1}',
  '18.5204,73.8567',
  1794297600000, 1794297600000,
  NULL, 1794902400000, 0
);

-- Alert 2: active high wind, escalated after a stronger gust reading.
INSERT INTO alert_history (
  fingerprint, hazard, severity, status, title, description, reason,
  payload, location_key, detected_at_utc, updated_at_utc,
  resolved_at_utc, expires_at_utc, acknowledged
) VALUES (
  'v1:highWind:18.5204,73.8567:2026-11-10T08:00:00.000Z',
  'highWind', 'high', 'escalated',
  'High High wind',
  'Peak wind gusts of 82 km/h expected within 24 h.',
  'Peak wind gusts of 82 km/h expected within 24 h.',
  '{"value":82.0,"unit":"km/h","rulesVersion":1}',
  '18.5204,73.8567',
  1794297600000, 1794296700000,
  NULL, 1794902400000, 1
);

-- Alert 3: resolved rain alert from the previous day.
INSERT INTO alert_history (
  fingerprint, hazard, severity, status, title, description, reason,
  payload, location_key, detected_at_utc, updated_at_utc,
  resolved_at_utc, expires_at_utc, acknowledged
) VALUES (
  'v1:rain:18.5204,73.8567:2026-11-09T17:00:00.000Z',
  'rain', 'moderate', 'resolved',
  'Moderate Rain',
  'Moderate rain expected now.',
  'Moderate rain expected now.',
  '{"value":null,"unit":null,"rulesVersion":1}',
  '18.5204,73.8567',
  1794245400000, 1794250800000,
  1794250800000, 1794850200000, 1
);

-- Notification delivery state for the two active alerts.
INSERT INTO notification_state (
  fingerprint, last_notified_at_utc, notification_count, status, updated_at_utc
) VALUES (
  'v1:thunderstorm:18.5204,73.8567:2026-11-10T08:00:00.000Z',
  1794290100000, 2, 'sent', 1794290100000
);

INSERT INTO notification_state (
  fingerprint, last_notified_at_utc, notification_count, status, updated_at_utc
) VALUES (
  'v1:highWind:18.5204,73.8567:2026-11-10T08:00:00.000Z',
  1794290100000, 1, 'sent', 1794290100000
);

-- Device-scoped preferences (never uploaded to Firestore).
INSERT INTO user_preferences (pref_key, pref_value, updated_at_utc) VALUES
  ('device_id',
   '9f2c1b7e-4a63-4f0d-9a51-2c8e7b6d1f34',
   1794290100000),
  ('last_known_location',
   '{"latitude":18.5204,"longitude":73.8567,"accuracy":12.5,"altitude":560.0,"speed":0.0,"fixTimestampUtc":"2026-11-10T05:55:00.000Z","label":"Pune, Maharashtra","capturedAtUtc":"2026-11-10T05:55:00.000Z"}',
   1794290100000),
  ('notifications_enabled',
   'true',
   1794290100000),
  ('notification_prompt_dismissed',
   'true',
   1794290100000);

-- ----------------------------------------------------------------------------
-- End of file
-- ----------------------------------------------------------------------------
