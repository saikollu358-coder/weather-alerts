/**
 * Weather-safety rule set — VERBATIM port of
 * `lib/services/weather_analysis/safety_rules.dart` (Phase 8).
 *
 * The mobile app and the cloud functions must stay in lock-step: every
 * threshold change must bump `RULES_VERSION` in BOTH copies.
 *
 * This is an application-internal assessment, never a substitute for official
 * hazardous-weather warnings.
 */

export enum WeatherSeverity {
  NONE = 'none',
  MINOR = 'minor',
  MODERATE = 'moderate',
  HIGH = 'high',
  SEVERE = 'severe',
}

export const RULES_VERSION = 1;
export const RULES_VERSION_DATE = '2026-09-06';

/** Ordered severity ranking (higher index = worse). */
const SEVERITY_RANK: Record<WeatherSeverity, number> = {
  [WeatherSeverity.NONE]: 0,
  [WeatherSeverity.MINOR]: 1,
  [WeatherSeverity.MODERATE]: 2,
  [WeatherSeverity.HIGH]: 3,
  [WeatherSeverity.SEVERE]: 4,
};

/** Numeric breakpoints for one hazard metric, mirroring WeatherThresholds. */
export interface WeatherThresholds {
  minor: number;
  moderate: number;
  high: number;
  severe: number;
  /** When true the value must be >= the breakpoint; otherwise <=. */
  exceed?: boolean;
}

export function severityForValue(
  thresholds: WeatherThresholds,
  value: number
): WeatherSeverity {
  if (thresholds.exceed === false) {
    if (value <= thresholds.severe) return WeatherSeverity.SEVERE;
    if (value <= thresholds.high) return WeatherSeverity.HIGH;
    if (value <= thresholds.moderate) return WeatherSeverity.MODERATE;
    if (value <= thresholds.minor) return WeatherSeverity.MINOR;
    return WeatherSeverity.NONE;
  }
  if (value >= thresholds.severe) return WeatherSeverity.SEVERE;
  if (value >= thresholds.high) return WeatherSeverity.HIGH;
  if (value >= thresholds.moderate) return WeatherSeverity.MODERATE;
  if (value >= thresholds.minor) return WeatherSeverity.MINOR;
  return WeatherSeverity.NONE;
}

/** Mirrors SafetyRules.windGust (km/h peak gusts). */
export const WIND_GUST_THRESHOLDS: WeatherThresholds = {
  minor: 40,
  moderate: 60,
  high: 75,
  severe: 90,
};

/** Mirrors SafetyRules.windSustained (km/h sustained). */
export const WIND_SUSTAINED_THRESHOLDS: WeatherThresholds = {
  minor: 30,
  moderate: 45,
  high: 60,
  severe: 75,
};

/** Mirrors SafetyRules.heat (°C, worse of air/apparent). */
export const HEAT_THRESHOLDS: WeatherThresholds = {
  minor: 30,
  moderate: 33,
  high: 36,
  severe: 40,
};

/** Mirrors SafetyRules.cold (°C, worse of air/apparent). */
export const COLD_THRESHOLDS: WeatherThresholds = {
  minor: 0,
  moderate: -5,
  high: -10,
  severe: -18,
  exceed: false,
};

/** Mirrors SafetyRules.flooding (mm per rolling 24 h). */
export const FLOODING_THRESHOLDS: WeatherThresholds = {
  minor: 20,
  moderate: 40,
  high: 60,
  severe: 100,
};

/** Mirrors SafetyRules.snow (mm water-equivalent in 24 h). */
export const SNOW_THRESHOLDS: WeatherThresholds = {
  minor: 5,
  moderate: 10,
  high: 20,
  severe: 35,
};

export function maxSeverity(
  a: WeatherSeverity,
  b: WeatherSeverity
): WeatherSeverity {
  return SEVERITY_RANK[a] >= SEVERITY_RANK[b] ? a : b;
}
