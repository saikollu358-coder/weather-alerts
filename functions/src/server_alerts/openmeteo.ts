/**
 * Open-Meteo client for the server-side alert pipeline (Phase 10).
 *
 * Mirrors `OpenMeteoWeatherService` (lib/services/weather/
 * open_meteo_weather_service.dart): same base URL, same request parameters,
 * and the same parallel-array -> point-object conversion that
 * `HourlyForecastPoint.listFromOpenMeteo` / `DailyForecastPoint.listFromOpenMeteo`
 * perform on the client. The output is a `WeatherBundleJson` that
 * `evaluateWeatherRisk` consumes verbatim.
 */

import type {
  CurrentWeatherJson,
  DailyForecastPointJson,
  HourlyForecastPointJson,
  WeatherBundleJson,
} from '../weather_analysis/analyze';

/** Source identifier written to produced bundles (mirrors the client). */
export const DATA_SOURCE = 'open-meteo';

const DEFAULT_BASE_URL = 'https://api.open-meteo.com/v1';

/** Freshness window for current conditions (mirrors the client). */
const CURRENT_MAX_AGE_MS = 30 * 60 * 1000;

const CURRENT_PARAMS =
  'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,' +
  'precipitation,weather_code,wind_speed_10m,wind_direction_10m,' +
  'wind_gusts_10m';
const HOURLY_PARAMS =
  'temperature_2m,precipitation_probability,weather_code,wind_speed_10m';
const DAILY_PARAMS =
  'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,' +
  'precipitation_probability_max';

/** Raised for any network or malformed-payload failure. */
export class WeatherFetchError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'WeatherFetchError';
  }
}

export interface FetchWeatherOptions {
  /** Overrides the default deployment URL (tests). */
  baseUrl?: string;
  timeoutMs?: number;
}

function resolveBaseUrl(options: FetchWeatherOptions): string {
  const configured =
    options.baseUrl ??
    process.env['OPEN_METEO_API_BASE_URL'] ??
    DEFAULT_BASE_URL;
  return configured.replace(/\/+$/, '');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function stringList(value: unknown): (string | null)[] {
  if (!Array.isArray(value)) return [];
  return value.map(item => (typeof item === 'string' ? item : null));
}

function numberList(value: unknown): (number | null)[] {
  if (!Array.isArray(value)) return [];
  return value.map(item => (typeof item === 'number' ? item : null));
}

function stringAt(items: (string | null)[], index: number): string | null {
  return items[index] ?? null;
}

function numberAt(items: (number | null)[], index: number): number | null {
  return items[index] ?? null;
}

function pairCount(a: unknown[], b: unknown[]): number {
  return a.length < b.length ? a.length : b.length;
}

function parseHourly(body: Record<string, unknown>): HourlyForecastPointJson[] {
  const times = stringList(body['time']);
  const temperatures = numberList(body['temperature_2m']);
  const probabilities = numberList(body['precipitation_probability']);
  const codes = numberList(body['weather_code']);
  const winds = numberList(body['wind_speed_10m']);
  const count = pairCount(times, temperatures);
  const points: HourlyForecastPointJson[] = [];
  for (let i = 0; i < count; i++) {
    points.push({
      time: stringAt(times, i) ?? '',
      temperature_2m: numberAt(temperatures, i) ?? 0,
      precipitation_probability: numberAt(probabilities, i),
      weather_code: numberAt(codes, i) ?? 0,
      wind_speed_10m: numberAt(winds, i) ?? 0,
    });
  }
  return points;
}

function parseDaily(body: Record<string, unknown>): DailyForecastPointJson[] {
  const times = stringList(body['time']);
  const codes = numberList(body['weather_code']);
  const maxes = numberList(body['temperature_2m_max']);
  const mins = numberList(body['temperature_2m_min']);
  const precip = numberList(body['precipitation_sum']);
  const precipProbs = numberList(body['precipitation_probability_max']);
  const days: DailyForecastPointJson[] = [];
  for (let i = 0; i < times.length; i++) {
    days.push({
      time: stringAt(times, i) ?? '',
      weather_code: numberAt(codes, i) ?? 0,
      temperature_2m_max: numberAt(maxes, i) ?? 0,
      temperature_2m_min: numberAt(mins, i) ?? 0,
      precipitation_sum: numberAt(precip, i) ?? 0,
      precipitation_probability_max: numberAt(precipProbs, i),
    });
  }
  return days;
}

/**
 * Converts a raw Open-Meteo `/forecast` payload into a [WeatherBundleJson].
 * Pure and deterministic — throws [WeatherFetchError] when blocks are missing
 * or empty, mirroring the client's `_fetchAndCache` validation.
 */
export function parseWeatherBody(
  body: unknown,
  locationKey: string,
  fetchedAt: Date
): WeatherBundleJson {
  if (!isRecord(body)) throw new WeatherFetchError('malformed payload');
  const current = body['current'];
  const hourlyBody = body['hourly'];
  const dailyBody = body['daily'];
  if (!isRecord(current) || !isRecord(hourlyBody) || !isRecord(dailyBody)) {
    throw new WeatherFetchError('malformed payload');
  }
  const hourly = parseHourly(hourlyBody);
  const daily = parseDaily(dailyBody);
  if (hourly.length === 0 || daily.length === 0) {
    throw new WeatherFetchError('malformed payload');
  }
  const fetchedAtUtc = fetchedAt.toISOString();
  return {
    locationKey,
    current: current as unknown as CurrentWeatherJson,
    hourly,
    daily,
    fetchedAtUtc,
    expiresAtUtc: new Date(
      fetchedAt.getTime() + CURRENT_MAX_AGE_MS
    ).toISOString(),
    dataSource: DATA_SOURCE,
  };
}

/**
 * Fetches the Open-Meteo `/forecast` bundle for [region]. Circular no secret or
 * user data: Open-Meteo is public and unauthenticated, so nothing sensitive is
 * ever logged or forwarded.
 */
export async function fetchWeatherBundle(
  region: {latitude: number; longitude: number; locationKey: string},
  options: FetchWeatherOptions = {}
): Promise<WeatherBundleJson> {
  const baseUrl = resolveBaseUrl(options);
  const params = new URLSearchParams({
    latitude: String(region.latitude),
    longitude: String(region.longitude),
    current: CURRENT_PARAMS,
    hourly: HOURLY_PARAMS,
    daily: DAILY_PARAMS,
    timezone: 'UTC',
    forecast_days: '7',
  });
  const url = `${baseUrl}/forecast?${params.toString()}`;
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    options.timeoutMs ?? 20000
  );
  let response: Response;
  try {
    response = await fetch(url, {signal: controller.signal});
  } catch (error) {
    throw new WeatherFetchError(`weather request failed: ${String(error)}`);
  } finally {
    clearTimeout(timer);
  }
  if (!response.ok) {
    throw new WeatherFetchError(`unexpected HTTP ${response.status}`);
  }
  const body: unknown = await response.json().catch(() => {
    throw new WeatherFetchError('invalid JSON response');
  });
  return parseWeatherBody(body, region.locationKey, new Date());
}
