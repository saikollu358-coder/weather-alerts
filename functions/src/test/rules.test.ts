/**
 * Parity tests for the Phase 8 rules port.
 *
 * Mirrors the mobile tests in `test/unit/weather_risk_evaluator_test.dart`.
 * Run with `npm test` (needs `npm install` first).
 */
import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {
  evaluateWeatherRisk,
  type WeatherBundleJson,
} from '../weather_analysis/analyze';
import {
  COLD_THRESHOLDS,
  FLOODING_THRESHOLDS,
  HEAT_THRESHOLDS,
  RULES_VERSION,
  SNOW_THRESHOLDS,
  WIND_GUST_THRESHOLDS,
  WIND_SUSTAINED_THRESHOLDS,
  WeatherSeverity,
  severityForValue,
} from '../weather_analysis/rules';
import {
  carriesHail,
  hazardsFor,
  isConvective,
} from '../weather_analysis/wmo_codes';

const NOW = new Date(Date.UTC(2026, 8, 6, 12));

function bundle(overrides: Partial<WeatherBundleJson> = {}): WeatherBundleJson {
  return {
    locationKey: '1.0,2.0',
    current: {
      time: '2026-09-06T12:00',
      temperature_2m: 15,
      apparent_temperature: 15,
      weather_code: 1,
      wind_speed_10m: 5,
    },
    hourly: [],
    daily: [],
    fetchedAtUtc: '2026-09-06T12:00',
    expiresAtUtc: '2026-09-06T13:00',
    ...overrides,
  };
}

function finding(
  analysis: ReturnType<typeof evaluateWeatherRisk>,
  hazard: string
) {
  const result = analysis.findings.find(f => f.hazard === hazard);
  assert.ok(result, `expected a '${hazard}' finding`);
  return result;
}

describe('safety rules parity', () => {
  it('keeps the rule version in lock-step with the mobile app', () => {
    assert.equal(RULES_VERSION, 1);
  });

  it('matches wind gust breakpoints', () => {
    assert.equal(
      severityForValue(WIND_GUST_THRESHOLDS, 39),
      WeatherSeverity.NONE
    );
    assert.equal(
      severityForValue(WIND_GUST_THRESHOLDS, 40),
      WeatherSeverity.MINOR
    );
    assert.equal(
      severityForValue(WIND_GUST_THRESHOLDS, 75),
      WeatherSeverity.HIGH
    );
    assert.equal(
      severityForValue(WIND_GUST_THRESHOLDS, 90),
      WeatherSeverity.SEVERE
    );
  });

  it('matches sustained wind, heat, cold, flood and snow breakpoints', () => {
    assert.equal(
      severityForValue(WIND_SUSTAINED_THRESHOLDS, 45),
      WeatherSeverity.MODERATE
    );
    assert.equal(severityForValue(HEAT_THRESHOLDS, 40), WeatherSeverity.SEVERE);
    assert.equal(severityForValue(COLD_THRESHOLDS, -12), WeatherSeverity.HIGH);
    assert.equal(
      severityForValue(FLOODING_THRESHOLDS, 70),
      WeatherSeverity.HIGH
    );
    assert.equal(
      severityForValue(SNOW_THRESHOLDS, 12),
      WeatherSeverity.MODERATE
    );
  });
});

describe('wmo code parity', () => {
  it('maps freezing rain to ice and rain', () => {
    const hazards = hazardsFor(67);
    assert.ok(hazards.includes('ice'));
    assert.ok(hazards.includes('rain'));
  });

  it('recognises convective and hail codes', () => {
    assert.ok(isConvective(96));
    assert.ok(carriesHail(99));
    assert.equal(carriesHail(95), false);
  });
});

describe('evaluateWeatherRisk', () => {
  it('returns low risk with no findings on a calm clear day', () => {
    const analysis = evaluateWeatherRisk(bundle(), {now: NOW});
    assert.equal(analysis.riskLevel, 'low');
    assert.equal(analysis.overallSeverity, WeatherSeverity.NONE);
    assert.equal(analysis.findings.length, 0);
  });

  it('classifies 82 km/h gusts as high wind', () => {
    const analysis = evaluateWeatherRisk(
      bundle({
        current: {
          time: '2026-09-06T12:00',
          temperature_2m: 15,
          apparent_temperature: 15,
          weather_code: 1,
          wind_speed_10m: 35,
          wind_gusts_10m: 82,
        },
      }),
      {now: NOW}
    );
    assert.equal(finding(analysis, 'highWind').severity, WeatherSeverity.HIGH);
    assert.equal(analysis.riskLevel, 'high');
  });

  it('flags a heat wave as critical', () => {
    const analysis = evaluateWeatherRisk(
      bundle({
        current: {
          time: '2026-09-06T12:00',
          temperature_2m: 38,
          apparent_temperature: 40,
          weather_code: 1,
          wind_speed_10m: 5,
        },
      }),
      {now: NOW}
    );
    assert.equal(finding(analysis, 'heat').severity, WeatherSeverity.SEVERE);
    assert.equal(analysis.riskLevel, 'critical');
  });

  it('flags snow on a cold day', () => {
    const analysis = evaluateWeatherRisk(
      bundle({
        current: {
          time: '2026-09-06T12:00',
          temperature_2m: -2,
          apparent_temperature: -5,
          weather_code: 71,
          wind_speed_10m: 10,
        },
        daily: [
          {
            time: '2026-09-07',
            weather_code: 71,
            temperature_2m_max: -2,
            temperature_2m_min: -9,
            precipitation_sum: 12,
          },
        ],
      }),
      {now: NOW}
    );
    assert.equal(finding(analysis, 'snow').severity, WeatherSeverity.MODERATE);
  });

  it('detects convective hazards from code 99', () => {
    const analysis = evaluateWeatherRisk(
      bundle({
        current: {
          time: '2026-09-06T12:00',
          temperature_2m: 15,
          apparent_temperature: 15,
          weather_code: 99,
          wind_speed_10m: 5,
        },
      }),
      {now: NOW}
    );
    finding(analysis, 'thunderstorm');
    finding(analysis, 'lightning');
    finding(analysis, 'hail');
  });
});
