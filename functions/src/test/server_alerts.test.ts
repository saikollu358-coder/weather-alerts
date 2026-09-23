/**
 * Tests for the Phase 10 server-side alert pipeline.
 *
 * Covers contract identity, status transitions, Open-Meteo parsing and the
 * injection-driven orchestrator. Run with `npm test`.
 */
import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {
  type WeatherBundleJson,
  evaluateWeatherRisk,
} from '../weather_analysis/analyze';
import {RULES_VERSION} from '../weather_analysis/rules';
import {
  SERVER_ALERTS_RETENTION_MS,
  alertFingerprint,
  isActiveStatus,
  isValidCoordinate,
  isValidLocationKey,
  notificationKeyFor,
  parseMonitoredRegion,
  severityRank,
  type MonitoredRegion,
  type ServerAlertDocument,
} from '../server_alerts/contract';
import {parseWeatherBody, WeatherFetchError} from '../server_alerts/openmeteo';
import {evaluateLocation} from '../server_alerts/publisher';
import {runServerAlertGeneration} from '../server_alerts/pipeline';
import {
  validateOfficialWarning,
  type OfficialWarning,
} from '../server_alerts/official_warnings';

const NOW = new Date(Date.UTC(2026, 8, 6, 12, 30));

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

function region(overrides: Partial<MonitoredRegion> = {}): MonitoredRegion {
  return {
    docId: 'austin',
    name: 'Austin, TX',
    latitude: 30.2672,
    longitude: -97.7431,
    locationKey: '30.2672,-97.7431',
    enabled: true,
    ...overrides,
  };
}

function priorDoc(
  hazard: string,
  overrides: Partial<ServerAlertDocument> = {}
): ServerAlertDocument {
  const locationKey = (overrides.locationKey as string) ?? '30.2672,-97.7431';
  const fingerprint =
    (overrides.fingerprint as string) ??
    alertFingerprint(hazard, locationKey, NOW);
  return {
    fingerprint,
    notificationKey: notificationKeyFor(hazard, locationKey),
    hazard,
    severity: 'high',
    status: 'detected',
    title: 'High High wind',
    description: 'reason',
    reason: 'reason',
    locationKey,
    payload: {value: 82, unit: 'km/h', rulesVersion: RULES_VERSION},
    detectedAtUtc: '2026-09-06T12:00:00.000Z',
    updatedAtUtc: '2026-09-06T12:00:00.000Z',
    resolvedAtUtc: null,
    expiresAtUtc: '2026-09-13T12:00:00.000Z',
    acknowledged: false,
    source: 'server',
    riskLevel: 'high',
    overallSeverity: 'high',
    assessedAtUtc: '2026-09-06T12:00:00.000Z',
    ...overrides,
  };
}

/** High-gust analysis for the test region — always yields a highWind finding. */
function windyAnalysis() {
  return evaluateWeatherRisk(
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
}

function benignAnalysis() {
  return evaluateWeatherRisk(bundle(), {now: NOW});
}

describe('contract identity', () => {
  it('keeps the rule version aligned with the mobile app', () => {
    assert.equal(RULES_VERSION, 1);
  });

  it('anchors fingerprints to the UTC hour bucket (mobile format)', () => {
    const f1 = alertFingerprint('highWind', '1.0,2.0', NOW);
    assert.equal(f1, 'v1:highWind:1.0,2.0:2026-09-06T12:00:00.000Z');
    const nextHour = new Date(Date.UTC(2026, 8, 6, 13, 5));
    assert.notEqual(alertFingerprint('highWind', '1.0,2.0', nextHour), f1);
  });

  it('uses the phase 9 notification key without an hour bucket', () => {
    assert.equal(
      notificationKeyFor('highWind', '1.0,2.0'),
      'notif:v1:highWind:1.0,2.0'
    );
  });

  it('ranks severities and active statuses like the client', () => {
    assert.equal(severityRank('none'), 0);
    assert.equal(severityRank('severe'), 4);
    assert.ok(severityRank('unknown') < 0);
    assert.equal(isActiveStatus('detected'), true);
    assert.equal(isActiveStatus('resolved'), false);
    assert.equal(isActiveStatus('expired'), false);
  });

  it('validates coordinates and location keys', () => {
    assert.equal(isValidCoordinate(30.2, -97.7), true);
    assert.equal(isValidCoordinate(91, 0), false);
    assert.equal(isValidLocationKey('30.2672,-97.7431'), true);
    assert.equal(isValidLocationKey('30.2672'), false);
    assert.equal(isValidLocationKey('lat,lng'), false);
  });

  it('parses valid region documents and rejects malformed ones', () => {
    const good = parseMonitoredRegion(
      {
        name: 'Austin',
        latitude: 30.2672,
        longitude: -97.7431,
        locationKey: '30.2672,-97.7431',
        enabled: true,
      },
      'austin'
    );
    assert.ok(good);
    assert.equal(good.enabled, true);
    assert.equal(
      parseMonitoredRegion({name: 'Bad', latitude: 95, longitude: 0}, 'bad'),
      null
    );
    assert.equal(
      parseMonitoredRegion(
        {name: 'Bad', latitude: 30, longitude: -97, locationKey: 'nope'},
        'bad'
      ),
      null
    );
  });
});

describe('evaluateLocation', () => {
  it('publishes a fresh detected alert for actionable findings', () => {
    const drafts = evaluateLocation(windyAnalysis(), region(), [], NOW);
    const highWind = drafts.filter(d => d.doc.hazard === 'highWind');
    assert.equal(highWind.length, 1);
    const draft = highWind[0];
    assert.equal(draft.doc.status, 'detected');
    assert.equal(draft.doc.title, 'High High wind');
    assert.equal(draft.doc.payload.value, 82);
    assert.equal(draft.id, draft.doc.fingerprint);
    assert.equal(draft.doc.assessedAtUtc, NOW.toISOString());
    assert.equal(
      draft.doc.expiresAtUtc,
      new Date(NOW.getTime() + SERVER_ALERTS_RETENTION_MS).toISOString()
    );
  });

  it('keeps the status when severities are unchanged', () => {
    const prior = [priorDoc('highWind')];
    const drafts = evaluateLocation(windyAnalysis(), region(), prior, NOW);
    const highWind = drafts.filter(d => d.doc.hazard === 'highWind');
    assert.equal(highWind.length, 1);
    assert.equal(highWind[0].doc.status, 'detected');
  });

  it('escalates when the severity grows for an active alert', () => {
    const prior = [
      priorDoc('highWind', {
        fingerprint: alertFingerprint('highWind', '30.2672,-97.7431', NOW),
        severity: 'minor',
      }),
    ];
    const drafts = evaluateLocation(windyAnalysis(), region(), prior, NOW);
    const highWind = drafts.filter(d => d.doc.hazard === 'highWind');
    assert.equal(highWind.length, 1);
    assert.equal(highWind[0].doc.status, 'escalated');
    assert.equal(highWind[0].doc.severity, 'high');
  });

  it('resolves previously-active hazards that have cleared', () => {
    const prior = [priorDoc('highWind')];
    const drafts = evaluateLocation(benignAnalysis(), region(), prior, NOW);
    const resolved = drafts.filter(d => d.doc.status === 'resolved');
    assert.equal(resolved.length, 1);
    assert.equal(resolved[0].doc.hazard, 'highWind');
    assert.equal(resolved[0].doc.fingerprint, prior[0].fingerprint);
    assert.equal(resolved[0].doc.resolvedAtUtc, NOW.toISOString());
  });

  it('publishes nothing for a benign analysis with no prior alerts', () => {
    const drafts = evaluateLocation(benignAnalysis(), region(), [], NOW);
    assert.equal(drafts.length, 0);
  });
});

describe('parseWeatherBody', () => {
  it('converts parallel arrays into point-object lists', () => {
    const body = {
      current: {
        time: '2026-09-06T12:00',
        temperature_2m: 15,
        weather_code: 1,
        wind_speed_10m: 5,
      },
      hourly: {
        time: ['2026-09-06T13:00', '2026-09-06T14:00'],
        temperature_2m: [16, 17],
        weather_code: [61, 80],
        wind_speed_10m: [20, 25],
        precipitation_probability: [40, null],
      },
      daily: {
        time: ['2026-09-07', '2026-09-08'],
        weather_code: [2, 3],
        temperature_2m_max: [22, 21],
        temperature_2m_min: [10, 11],
        precipitation_sum: [3, 0],
        precipitation_probability_max: [60, 20],
      },
    };
    const parsed = parseWeatherBody(body, '1.0,2.0', NOW);
    assert.equal(parsed.locationKey, '1.0,2.0');
    assert.equal(parsed.hourly?.length, 2);
    assert.equal(parsed.hourly?.[0].weather_code, 61);
    assert.equal(parsed.hourly?.[0].precipitation_probability, 40);
    assert.equal(parsed.hourly?.[1].precipitation_probability, null);
    assert.equal(parsed.daily?.[1].precipitation_sum, 0);
    assert.equal(parsed.dataSource, 'open-meteo');
    assert.equal(parsed.fetchedAtUtc, NOW.toISOString());
  });

  it('throws when required blocks are missing', () => {
    assert.throws(
      () => parseWeatherBody({hourly: {}, daily: {}}, 'k', NOW),
      WeatherFetchError
    );
  });
});

describe('runServerAlertGeneration', () => {
  function deps(regions: MonitoredRegion[], fetchFails: boolean[] = []) {
    let call = 0;
    const written: {id: string; doc: ServerAlertDocument}[] = [];
    return {
      written,
      fetchCells: fetchFails,
      dep: {
        listRegions: async () => regions,
        fetchBundle: async (_region: MonitoredRegion) => {
          const fails = fetchFails[call] ?? false;
          call++;
          if (fails) throw new WeatherFetchError('boom');
          return bundle({
            locationKey: _region.locationKey,
            current: {
              time: '2026-09-06T12:00',
              temperature_2m: 15,
              apparent_temperature: 15,
              weather_code: 1,
              wind_speed_10m: 35,
              wind_gusts_10m: 82,
            },
          });
        },
        loadPriorAlerts: async (locationKey: string) => {
          if (locationKey === '1.0,2.0')
            return [
              priorDoc('highWind', {
                locationKey: '1.0,2.0',
                fingerprint: alertFingerprint('highWind', '1.0,2.0', NOW),
              }),
            ];
          return [];
        },
        writeAlert: async (id: string, doc: ServerAlertDocument) => {
          written.push({id, doc});
        },
        pruneExpired: async () => {
          return 0;
        },
      } as const,
    };
  }

  it('evaluates regions and writes alert documents', async () => {
    const regions = [
      region({docId: 'a', locationKey: '1.0,2.0', latitude: 1, longitude: 2}),
      region({docId: 'b', locationKey: '3.0,4.0', latitude: 3, longitude: 4}),
    ];
    const {dep, written} = deps(regions);
    const result = await runServerAlertGeneration(dep, {now: NOW});
    assert.equal(result.regionsScanned, 2);
    assert.equal(result.regionsEvaluated, 2);
    assert.ok(result.alertsWritten >= 2);
    assert.ok(written.length >= 2);
    assert.ok(written.some(w => w.doc.hazard === 'highWind'));
  });

  it('skips a region whose weather cannot be fetched without resolving it', async () => {
    const regions = [
      region({
        docId: 'ok',
        locationKey: '1.0,2.0',
        latitude: 1,
        longitude: 2,
      }),
      region({
        docId: 'bad',
        locationKey: '3.0,4.0',
        latitude: 3,
        longitude: 4,
      }),
    ];
    const {dep} = deps(regions, [false, true]);
    const result = await runServerAlertGeneration(dep, {now: NOW});
    assert.equal(result.regionsEvaluated, 1);
  });

  it('ignores invalid-region documents', async () => {
    const regions = [
      region({docId: 'bad', latitude: 95, longitude: 0}),
      region({
        docId: 'ok',
        locationKey: '1.0,2.0',
        latitude: 1,
        longitude: 2,
      }),
    ];
    const {dep} = deps(regions);
    const result = await runServerAlertGeneration(dep, {now: NOW});
    assert.equal(result.regionsEvaluated, 1);
  });
});

describe('official warnings', () => {
  const valid: OfficialWarning = {
    id: 'flash-flood-2026-09-06',
    title: 'Flash Flood Warning',
    body: 'Heavy rain is expected.',
    category: 'flood',
    severity: 'high',
    source: 'National Weather Service',
    issuedAtUtc: '2026-09-06T10:00:00.000Z',
    effectiveFromUtc: '2026-09-06T10:00:00.000Z',
    effectiveUntilUtc: '2026-09-06T18:00:00.000Z',
    locationKey: '30.2672,-97.7431',
    locationName: 'Austin, TX',
  };

  it('accepts a well-formed warning', () => {
    assert.equal(validateOfficialWarning(valid), true);
  });

  it('rejects malformed warnings', () => {
    assert.equal(
      validateOfficialWarning({...valid, severity: 'catastrophic'}),
      false
    );
    assert.equal(
      validateOfficialWarning({...valid, effectiveUntilUtc: 'not-a-date'}),
      false
    );
    assert.equal(
      validateOfficialWarning({
        ...valid,
        effectiveUntilUtc: '2026-09-05T18:00:00.000Z',
      }),
      false
    );
    assert.equal(
      validateOfficialWarning({...valid, locationKey: '30.2672'}),
      false
    );
    assert.equal(validateOfficialWarning(null), false);
  });
});
