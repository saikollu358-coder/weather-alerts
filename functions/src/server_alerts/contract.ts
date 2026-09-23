/**
 * Document contracts for the server-side alert pipeline (Phase 10).
 *
 * Mirrors the mobile `AlertRecord` (lib/domain/entities/alert_record.dart), the
 * ingest transitions in `AlertIngestUseCase`, the Phase 8 fingerprint
 * (`WeatherRiskEvaluator.fingerprintFor`) and the Phase 9 notification key
 * (`BackgroundWeatherCheckUseCase.notificationKeyFor`) so that server and
 * client agree on every identity byte-for-byte.
 *
 * Collections written by this pipeline (`server_alerts`,
 * `public`, `official_warnings`) are read-only for clients:
 * see `firestore.rules`.
 */

import {RULES_VERSION} from '../weather_analysis/rules';

/** Retention window in ms — mirrors `AppConstants.alertRetention` (7 days). */
export const SERVER_ALERTS_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;

/** Human labels for the phase 9 notification key prefix. */
export const NOTIFICATION_KEY_PREFIX = 'notif';

/** Marker that a document was produced by the server pipeline. */
export const DOC_SOURCE_ID = 'server';

export type AlertStatus = 'detected' | 'escalated' | 'resolved' | 'expired';

/** Severity vocabulary as emitted by the analysis engine (lowercase). */
export type SeverityId = 'none' | 'minor' | 'moderate' | 'high' | 'severe';

const SEVERITY_RANK: Record<SeverityId, number> = {
  none: 0,
  minor: 1,
  moderate: 2,
  high: 3,
  severe: 4,
};

const SEVERITY_LABEL: Record<SeverityId, string> = {
  none: 'None',
  minor: 'Minor',
  moderate: 'Moderate',
  high: 'High',
  severe: 'Severe',
};

const HAZARD_LABEL: Record<string, string> = {
  thunderstorm: 'Thunderstorm',
  rain: 'Rain',
  flooding: 'Flooding',
  snow: 'Snow',
  ice: 'Ice',
  heat: 'Heat',
  cold: 'Cold',
  fog: 'Fog',
  highWind: 'High wind',
  uvExposure: 'UV exposure',
  airQuality: 'Air quality',
  hail: 'Hail',
  lightning: 'Lightning',
  drought: 'Drought',
};

/**
 * Document stored under `server_alerts/<fingerprint>`.
 *
 * Field names mirror the mobile `AlertRecord` plus server-only metadata
 * (`source`, `riskLevel`, `overallSeverity`, `assessedAtUtc`). The document
 * **id equals `fingerprint`**, which encodes the UTC hour bucket, so the same
 * hazard at the same location is upserted at most once per hour.
 */
export interface ServerAlertDocument {
  fingerprint: string;
  notificationKey: string;
  hazard: string;
  severity: SeverityId;
  status: AlertStatus;
  title: string;
  description: string;
  reason: string;
  locationKey: string;
  payload: {
    value?: number | null;
    unit?: string | null;
    rulesVersion: number;
  };
  detectedAtUtc: string;
  updatedAtUtc: string;
  resolvedAtUtc?: string | null;
  expiresAtUtc: string;
  acknowledged: boolean;
  source: string;
  riskLevel: string;
  overallSeverity: SeverityId;
  assessedAtUtc: string;
}

/**
 * A monitored region registered by operators under
 * `public/<regionId>` (public read-only reference data).
 */
export interface MonitoredRegion {
  docId: string;
  name: string;
  latitude: number;
  longitude: number;
  /** `lat,lng` — matches the mobile `locationKey` format. */
  locationKey: string;
  enabled: boolean;
}

/** Severity ordering used to detect escalation (mirrors enum index). */
export function severityRank(severity: string): number {
  return SEVERITY_RANK[severity as SeverityId] ?? Number.NEGATIVE_INFINITY;
}

/** True when the severity is above `none` (mirrors `HazardFinding.isActionable`). */
export function isActionableSeverity(severity: string): boolean {
  return severityRank(severity) > 0;
}

/** Display label for a severity, e.g. `Moderate`. */
export function severityLabel(severity: string): string {
  return SEVERITY_LABEL[severity as SeverityId] ?? severity;
}

/** Display label for a hazard, e.g. `High wind`. */
export function hazardLabel(hazard: string): string {
  return HAZARD_LABEL[hazard] ?? hazard;
}

/**
 * Anchor fingerprint for a hazard at a location.
 *
 * Mirrors `WeatherRiskEvaluator.fingerprintFor`: anchored to the UTC hour of
 * the assessment, format `v{rulesVersion}:{hazard}:{locationKey}:{hourBucket}`.
 * The hour bucket is the ISO-8601 UTC string of the bucketed time.
 */
export function alertFingerprint(
  hazard: string,
  locationKey: string,
  analyzedAtUtc: Date
): string {
  const utc = Date.UTC(
    analyzedAtUtc.getUTCFullYear(),
    analyzedAtUtc.getUTCMonth(),
    analyzedAtUtc.getUTCDate(),
    analyzedAtUtc.getUTCHours()
  );
  const hourBucket = new Date(utc).toISOString();
  return `v${RULES_VERSION}:${hazard}:${locationKey}:${hourBucket}`;
}

/**
 * Notification key advertised on server-generated alerts.
 *
 * Mirrors `BackgroundWeatherCheckUseCase.notificationKeyFor`:
 * `notif:v{rulesVersion}:{hazard}:{locationKey}` — deliberately WITHOUT the
 * hour bucket so the client can run its Phase 9 cooldown logic on it.
 */
export function notificationKeyFor(
  hazard: string,
  locationKey: string
): string {
  return `${NOTIFICATION_KEY_PREFIX}:v${RULES_VERSION}:${hazard}:${locationKey}`;
}

/** True when a status is still in effect (mirrors `AlertRecord.isActive`). */
export function isActiveStatus(status: AlertStatus): boolean {
  return status !== 'resolved' && status !== 'expired';
}

/** Rejects garbage coordinates (lat in [-90,90], lng in [-180,180]). */
export function isValidCoordinate(lat: number, lng: number): boolean {
  return (
    Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180
  );
}

/** Rejects malformed `lat,lng` location keys. */
export function isValidLocationKey(key: string): boolean {
  return /^-?\d+(\.\d+)?,-?\d+(\.\d+)?$/.test(key);
}

/**
 * Parses a `public/<regionId>` document into a [MonitoredRegion], or
 * returns null when the document is not a valid region entry.
 */
export function parseMonitoredRegion(
  data: Record<string, unknown>,
  docId: string
): MonitoredRegion | null {
  if (typeof data['name'] !== 'string' || data['name'].length === 0) {
    return null;
  }
  const latitude = data['latitude'];
  const longitude = data['longitude'];
  if (typeof latitude !== 'number' || typeof longitude !== 'number') {
    return null;
  }
  if (!isValidCoordinate(latitude, longitude)) return null;
  const locationKey =
    typeof data['locationKey'] === 'string' ? data['locationKey'] : '';
  if (locationKey.length === 0) {
    if (!isValidLocationKey(`${latitude},${longitude}`)) return null;
  } else if (!isValidLocationKey(locationKey)) {
    return null;
  }
  return {
    docId,
    name: data['name'],
    latitude,
    longitude,
    locationKey:
      locationKey.length > 0 ? locationKey : `${latitude},${longitude}`,
    enabled: data['enabled'] !== false,
  };
}
