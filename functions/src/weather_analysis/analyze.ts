/**
 * Deterministic rule-based risk evaluation — VERBATIM port of
 * `lib/services/weather_analysis/weather_risk_evaluator.dart` (Phase 8).
 *
 * Pure: no I/O, no randomness. Consumes a `WeatherBundle`-shaped JSON payload
 * and yields the same analysis the mobile engine would produce.
 */

import {
  COLD_THRESHOLDS,
  FLOODING_THRESHOLDS,
  HEAT_THRESHOLDS,
  RULES_VERSION,
  SNOW_THRESHOLDS,
  WIND_GUST_THRESHOLDS,
  WIND_SUSTAINED_THRESHOLDS,
  WeatherSeverity,
  maxSeverity,
  severityForValue,
} from './rules';
import {
  carriesHail,
  freezingCodeSeverity,
  fogCodeSeverity,
  isConvective,
  rainCodeSeverity,
  snowCodeSeverity,
} from './wmo_codes';

export interface CurrentWeatherJson {
  time?: string;
  temperature_2m?: number;
  relative_humidity_2m?: number | null;
  apparent_temperature?: number;
  precipitation?: number;
  weather_code?: number;
  is_day?: number | boolean;
  wind_speed_10m?: number;
  wind_direction_10m?: number | null;
  wind_gusts_10m?: number | null;
}

export interface HourlyForecastPointJson {
  time?: string;
  temperature_2m?: number;
  precipitation_probability?: number | null;
  weather_code?: number;
  wind_speed_10m?: number;
}

export interface DailyForecastPointJson {
  time?: string;
  weather_code?: number;
  temperature_2m_max?: number;
  temperature_2m_min?: number;
  precipitation_sum?: number;
  precipitation_probability_max?: number | null;
}

export interface WeatherBundleJson {
  locationKey: string;
  current: CurrentWeatherJson;
  hourly?: HourlyForecastPointJson[];
  daily?: DailyForecastPointJson[];
  fetchedAtUtc?: string;
  expiresAtUtc?: string;
  dataSource?: string;
}

export interface HazardFindingJson {
  hazard: string;
  severity: string;
  reason: string;
  value?: number | null;
  unit?: string | null;
}

export interface WeatherAnalysisJson {
  riskLevel: string;
  overallSeverity: string;
  findings: HazardFindingJson[];
  rulesVersion: number;
  analyzedAtUtc: string;
}

const SEVERITY_RANK: Record<WeatherSeverity, number> = {
  [WeatherSeverity.NONE]: 0,
  [WeatherSeverity.MINOR]: 1,
  [WeatherSeverity.MODERATE]: 2,
  [WeatherSeverity.HIGH]: 3,
  [WeatherSeverity.SEVERE]: 4,
};

const DEFAULT_WINDOW_HOURS = 24;
const DEFAULT_ACCUMULATION_HOURS = 72;

interface RiskInput {
  peakGustKmh: number | null;
  peakSustainedWindKmh: number | null;
  maxTemperatureC: number;
  minTemperatureC: number;
  maxApparentTemperatureC: number;
  minApparentTemperatureC: number;
  maxDailyPrecipMm: number;
  maxDailySnowMm: number;
  currentWeatherCode: number;
  upcomingWeatherCodes: number[];
  currentHourlyPrecipMm: number;
}

function toUtc(dateString: string | undefined): number {
  return Date.parse((dateString ?? '').replace(' ', 'T')) || Date.now();
}

function buildInput(
  bundle: WeatherBundleJson,
  nowMs: number,
  windowHours: number,
  accumulationHours: number
): RiskInput {
  const current = bundle.current;
  const hourly = bundle.hourly ?? [];
  const daily = bundle.daily ?? [];

  const windowEnd = nowMs + windowHours * 60 * 60 * 1000;
  const accumulationEnd = nowMs + accumulationHours * 60 * 60 * 1000;

  let peakGust: number | null = current.wind_gusts_10m ?? null;
  let peakSustained: number | null =
    typeof current.wind_speed_10m === 'number' && current.wind_speed_10m > 0
      ? current.wind_speed_10m
      : null;
  let maxTemp = current.temperature_2m ?? 0;
  let minTemp = current.temperature_2m ?? 0;
  const maxApparent = current.apparent_temperature ?? maxTemp;
  const minApparent = current.apparent_temperature ?? minTemp;
  const upcomingWeatherCodes: number[] = [];

  for (const point of hourly) {
    const t = toUtc(point.time);
    if (!(t > nowMs)) continue;
    if (t > windowEnd) break;
    upcomingWeatherCodes.push(point.weather_code ?? 0);
    const wind = point.wind_speed_10m ?? 0;
    if (wind > (peakGust ?? 0)) peakGust = wind;
    if (wind > (peakSustained ?? 0)) peakSustained = wind;
    const temp = point.temperature_2m ?? 0;
    if (temp > maxTemp) maxTemp = temp;
    if (temp < minTemp) minTemp = temp;
  }

  let maxDailyPrecip = current.precipitation ?? 0;
  let maxDailySnow = 0;
  for (const day of daily) {
    const dayEnd = toUtc(day.time) + 24 * 60 * 60 * 1000;
    if (!(dayEnd > nowMs)) continue;
    if (toUtc(day.time) > accumulationEnd) break;
    const precip = day.precipitation_sum ?? 0;
    if (precip > maxDailyPrecip) maxDailyPrecip = precip;
    const max = day.temperature_2m_max ?? 0;
    const min = day.temperature_2m_min ?? 0;
    if (max <= 2 && min <= 2 && precip > maxDailySnow) maxDailySnow = precip;
    if (max > maxTemp) maxTemp = max;
    if (min < minTemp) minTemp = min;
  }

  return {
    peakGustKmh: typeof peakGust === 'number' && peakGust > 0 ? peakGust : null,
    peakSustainedWindKmh:
      typeof peakSustained === 'number' && peakSustained > 0
        ? peakSustained
        : null,
    maxTemperatureC: maxTemp,
    minTemperatureC: minTemp,
    maxApparentTemperatureC:
      maxApparent > current.temperature_2m! ? maxApparent : maxTemp,
    minApparentTemperatureC:
      minApparent < current.temperature_2m! ? minApparent : minTemp,
    maxDailyPrecipMm: maxDailyPrecip,
    maxDailySnowMm: maxDailySnow,
    currentWeatherCode: current.weather_code ?? 0,
    upcomingWeatherCodes,
    currentHourlyPrecipMm: current.precipitation ?? 0,
  };
}

function windSeverity(input: RiskInput): WeatherSeverity {
  let severity = WeatherSeverity.NONE;
  if (input.peakGustKmh !== null) {
    severity = maxSeverity(
      severity,
      severityForValue(WIND_GUST_THRESHOLDS, input.peakGustKmh)
    );
  }
  if (input.peakSustainedWindKmh !== null) {
    severity = maxSeverity(
      severity,
      severityForValue(WIND_SUSTAINED_THRESHOLDS, input.peakSustainedWindKmh)
    );
  }
  return severity;
}

function heatSeverity(input: RiskInput): WeatherSeverity {
  const peak = Math.max(input.maxTemperatureC, input.maxApparentTemperatureC);
  return severityForValue(HEAT_THRESHOLDS, peak);
}

function coldSeverity(input: RiskInput): WeatherSeverity {
  const trough = Math.min(input.minTemperatureC, input.minApparentTemperatureC);
  return severityForValue(COLD_THRESHOLDS, trough);
}

function buildFindings(
  input: RiskInput,
  windowHours: number,
  accumulationHours: number
): HazardFindingJson[] {
  const findings: HazardFindingJson[] = [];

  const wind = windSeverity(input);
  if (wind !== WeatherSeverity.NONE) {
    const gust = input.peakGustKmh !== null;
    const value = input.peakGustKmh ?? input.peakSustainedWindKmh;
    findings.push({
      hazard: 'highWind',
      severity: wind,
      reason: `Peak wind ${gust ? 'gusts' : 'speeds'} of ${fmt(value)} km/h expected within ${windowHours} h.`,
      value,
      unit: 'km/h',
    });
  }

  const heat = heatSeverity(input);
  if (heat !== WeatherSeverity.NONE) {
    findings.push({
      hazard: 'heat',
      severity: heat,
      reason: `Temperatures peaking at ${fmt(input.maxTemperatureC)}°C (${fmt(input.maxApparentTemperatureC)}°C apparent) within ${windowHours} h.`,
      value: input.maxApparentTemperatureC,
      unit: '°C',
    });
  }

  const cold = coldSeverity(input);
  if (cold !== WeatherSeverity.NONE) {
    findings.push({
      hazard: 'cold',
      severity: cold,
      reason: `Temperatures dropping to ${fmt(input.minTemperatureC)}°C (${fmt(input.minApparentTemperatureC)}°C apparent) within ${windowHours} h.`,
      value: input.minApparentTemperatureC,
      unit: '°C',
    });
  }

  const rainFromCode = rainCodeSeverity(input.currentWeatherCode);
  let upcomingRain = WeatherSeverity.NONE;
  for (const code of input.upcomingWeatherCodes) {
    upcomingRain = maxSeverity(
      upcomingRain,
      rainCodeSeverity(code) as WeatherSeverity
    );
  }
  const rain = maxSeverity(rainFromCode as WeatherSeverity, upcomingRain);
  if (rain !== WeatherSeverity.NONE) {
    const now =
      SEVERITY_RANK[rainFromCode as WeatherSeverity] >=
      SEVERITY_RANK[upcomingRain];
    const where = now ? 'now' : `in the next ${windowHours} h`;
    const label =
      rain === WeatherSeverity.MINOR
        ? 'Light'
        : rain === WeatherSeverity.MODERATE
          ? 'Moderate'
          : 'Heavy';
    findings.push({
      hazard: 'rain',
      severity: rain,
      reason: `${label} rain expected ${where}.`,
    });
  }

  const flood = severityForValue(FLOODING_THRESHOLDS, input.maxDailyPrecipMm);
  if (flood !== WeatherSeverity.NONE) {
    findings.push({
      hazard: 'flooding',
      severity: flood,
      reason: `Up to ${fmt(input.maxDailyPrecipMm)} mm of rain in a single day within ${accumulationHours} h.`,
      value: input.maxDailyPrecipMm,
      unit: 'mm',
    });
  }

  const snowFromCode = snowCodeSeverity(
    input.currentWeatherCode
  ) as WeatherSeverity;
  let upcomingSnow = WeatherSeverity.NONE;
  for (const code of input.upcomingWeatherCodes) {
    upcomingSnow = maxSeverity(
      upcomingSnow,
      snowCodeSeverity(code) as WeatherSeverity
    );
  }
  const snowCode = maxSeverity(snowFromCode, upcomingSnow);
  const snowAccumulation = severityForValue(
    SNOW_THRESHOLDS,
    input.maxDailySnowMm
  );
  const snow = maxSeverity(snowCode, snowAccumulation);
  if (snow !== WeatherSeverity.NONE) {
    const cm = (input.maxDailySnowMm / 10).toFixed(1);
    findings.push({
      hazard: 'snow',
      severity: snow,
      reason: `Snowfall of up to ${fmt(input.maxDailySnowMm)} mm water-equivalent (~${cm} cm) expected within ${accumulationHours} h.`,
      value: input.maxDailySnowMm,
      unit: 'mm',
    });
  }

  if (input.maxTemperatureC <= 2) {
    let freezes = freezingCodeSeverity(
      input.currentWeatherCode
    ) as WeatherSeverity;
    for (const code of input.upcomingWeatherCodes) {
      freezes = maxSeverity(
        freezes,
        freezingCodeSeverity(code) as WeatherSeverity
      );
    }
    if (freezes !== WeatherSeverity.NONE) {
      findings.push({
        hazard: 'ice',
        severity: freezes,
        reason:
          'Freezing precipitation expected with temperatures at or below 2°C — surfaces are likely slick.',
        value: input.maxTemperatureC,
        unit: '°C',
      });
    }
  }

  let fog = fogCodeSeverity(input.currentWeatherCode) as WeatherSeverity;
  for (const code of input.upcomingWeatherCodes) {
    fog = maxSeverity(fog, fogCodeSeverity(code) as WeatherSeverity);
  }
  if (fog !== WeatherSeverity.NONE) {
    findings.push({
      hazard: 'fog',
      severity: fog,
      reason:
        fog === WeatherSeverity.HIGH
          ? 'Dense freezing-rime fog expected — visibility severely reduced.'
          : 'Fog expected — reduced visibility possible.',
    });
  }

  const allCodes = [input.currentWeatherCode, ...input.upcomingWeatherCodes];
  const hasThunder = allCodes.some(isConvective);
  const hasLightning = allCodes.some(isConvective);
  const hasHail = allCodes.some(carriesHail);
  if (hasThunder) {
    findings.push({
      hazard: 'thunderstorm',
      severity: WeatherSeverity.HIGH,
      reason: `Thunderstorm activity expected within ${windowHours} h.`,
    });
  }
  if (hasLightning) {
    findings.push({
      hazard: 'lightning',
      severity: WeatherSeverity.HIGH,
      reason: `Lightning risk expected within ${windowHours} h.`,
    });
  }
  if (hasHail) {
    findings.push({
      hazard: 'hail',
      severity: WeatherSeverity.HIGH,
      reason: `Thunderstorms with hail expected within ${windowHours} h.`,
    });
  }

  return findings;
}

function riskLevelFromSeverity(severity: WeatherSeverity): string {
  if (severity === WeatherSeverity.SEVERE) return 'critical';
  if (severity === WeatherSeverity.HIGH) return 'high';
  if (severity === WeatherSeverity.MODERATE) return 'moderate';
  return 'low';
}

function fmt(value: number | null | undefined): string {
  if (value === null || value === undefined) return '--';
  const tenth = Math.round((value as number) * 10) / 10;
  const text = tenth.toFixed(1);
  return text.endsWith('.0') ? text.slice(0, -2) : text;
}

/**
 * Evaluates a `WeatherBundle`-shaped payload and returns the same analysis the
 * mobile app produces for the current rule version.
 */
export function evaluateWeatherRisk(
  bundle: WeatherBundleJson,
  options: {
    now?: Date;
    windowHours?: number;
    accumulationHours?: number;
  } = {}
): WeatherAnalysisJson {
  const nowMs = options.now?.getTime() ?? Date.now();
  const windowHours = options.windowHours ?? DEFAULT_WINDOW_HOURS;
  const accumulationHours =
    options.accumulationHours ?? DEFAULT_ACCUMULATION_HOURS;
  const input = buildInput(bundle, nowMs, windowHours, accumulationHours);
  const findings = buildFindings(input, windowHours, accumulationHours);

  let overall = WeatherSeverity.NONE;
  for (const finding of findings) {
    overall = maxSeverity(overall, finding.severity as WeatherSeverity);
  }

  return {
    riskLevel: riskLevelFromSeverity(overall),
    overallSeverity: overall,
    findings,
    rulesVersion: RULES_VERSION,
    analyzedAtUtc: new Date(nowMs).toISOString(),
  };
}
