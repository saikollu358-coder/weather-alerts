/**
 * Tests for the Phase 12 push notification router.
 */
import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {ServerAlertDocument} from '../server_alerts/contract';
import {RULES_VERSION} from '../weather_analysis/rules';
import {
  PUSH_COOLDOWN_MS,
  type DeliveryRecord,
  type DeviceDocument,
  type PushRouterDeps,
  routePushNotifications,
} from '../server_alerts/push_router';

const NOW = new Date(Date.UTC(2026, 8, 6, 12, 30));

function alertDoc(
  hazard: string,
  severity: 'minor' | 'moderate' | 'high' | 'severe' | 'none',
  status: ServerAlertDocument['status'],
  locationKey = '1.0,2.0'
): ServerAlertDocument {
  const fingerprint = `v${RULES_VERSION}:${hazard}:${locationKey}:${NOW.toISOString()}`;
  return {
    fingerprint,
    notificationKey: `notif:v${RULES_VERSION}:${hazard}:${locationKey}`,
    hazard,
    severity,
    status,
    title: `${severity} ${hazard}`,
    description: 'reason',
    reason: 'reason',
    locationKey,
    payload: {value: null, unit: null, rulesVersion: RULES_VERSION},
    detectedAtUtc: NOW.toISOString(),
    updatedAtUtc: NOW.toISOString(),
    resolvedAtUtc: null,
    expiresAtUtc: new Date(
      NOW.getTime() + 7 * 24 * 60 * 60 * 1000
    ).toISOString(),
    acknowledged: false,
    source: 'server',
    riskLevel: 'high',
    overallSeverity: severity,
    assessedAtUtc: NOW.toISOString(),
  };
}

function device(
  token: string,
  locationKeys: string[],
  uid = 'u1'
): DeviceDocument {
  return {
    token,
    deviceId: `device-${token}`,
    uid,
    locationKeys,
  };
}

interface TestContext {
  sentCount: number;
  sentTokens: string[][];
  sentPayloads: Record<string, string>[];
  deliveryRecords: Map<string, DeliveryRecord>;
  devicesByLocation: Map<string, DeviceDocument[]>;
}

function makeDeps(ctx: TestContext): PushRouterDeps {
  return {
    async findDevicesForLocation(locationKey) {
      return ctx.devicesByLocation.get(locationKey) ?? [];
    },
    async getDeliveryRecord(notificationKey) {
      return ctx.deliveryRecords.get(notificationKey) ?? null;
    },
    async setDeliveryRecord(notificationKey, record) {
      ctx.deliveryRecords.set(notificationKey, record);
    },
    async sendPush(tokens, notification, data) {
      ctx.sentCount += tokens.length;
      ctx.sentTokens.push(tokens);
      ctx.sentPayloads.push(data);
      return tokens.length;
    },
  };
}

function newCtx(): TestContext {
  return {
    sentCount: 0,
    sentTokens: [],
    sentPayloads: [],
    deliveryRecords: new Map(),
    devicesByLocation: new Map(),
  };
}

describe('routePushNotifications', () => {
  it('sends a push for a detected alert to matching devices', async () => {
    const ctx = newCtx();
    ctx.devicesByLocation.set('1.0,2.0', [
      device('tok-1', ['1.0,2.0']),
      device('tok-2', ['1.0,2.0', '3.0,4.0']),
    ]);
    const deps = makeDeps(ctx);

    const result = await routePushNotifications(
      [alertDoc('highWind', 'high', 'detected')],
      deps,
      NOW
    );

    assert.equal(result.alertsConsidered, 1);
    assert.equal(result.notificationsSent, 2);
    assert.equal(result.devicesReached, 2);
    assert.equal(result.cooldownSuppressed, 0);
    assert.deepEqual(ctx.sentTokens[0], ['tok-1', 'tok-2']);
    const payload = ctx.sentPayloads[0];
    assert.equal(payload['hazard'], 'highWind');
    assert.equal(payload['severity'], 'high');
    assert.equal(payload['status'], 'detected');
    assert.ok(payload['fingerprint']);
  });

  it('only delivers to devices matching the alert location', async () => {
    const ctx = newCtx();
    ctx.devicesByLocation.set('1.0,2.0', [device('tok-matching', ['1.0,2.0'])]);
    ctx.devicesByLocation.set('8.0,9.0', [device('tok-other', ['8.0,9.0'])]);
    const deps = makeDeps(ctx);

    await routePushNotifications(
      [alertDoc('rain', 'moderate', 'escalated')],
      deps,
      NOW
    );

    assert.equal(ctx.sentTokens.length, 1);
    assert.deepEqual(ctx.sentTokens[0], ['tok-matching']);
  });

  it('applies the server-side cooldown for duplicate notification keys', async () => {
    const ctx = newCtx();
    ctx.devicesByLocation.set('1.0,2.0', [device('tok-1', ['1.0,2.0'])]);
    ctx.deliveryRecords.set('notif:v1:highWind:1.0,2.0', {
      notificationKey: 'notif:v1:highWind:1.0,2.0',
      lastDeliveredAtUtc: new Date(NOW.getTime() - 1000).toISOString(),
      deliveryCount: 1,
    });
    const deps = makeDeps(ctx);

    const result = await routePushNotifications(
      [alertDoc('highWind', 'high', 'detected')],
      deps,
      NOW
    );

    assert.equal(result.cooldownSuppressed, 1);
    assert.equal(ctx.sentCount, 0);
  });

  it('delivers again once the cooldown has elapsed', async () => {
    const ctx = newCtx();
    ctx.devicesByLocation.set('1.0,2.0', [device('tok-1', ['1.0,2.0'])]);
    ctx.deliveryRecords.set('notif:v1:highWind:1.0,2.0', {
      notificationKey: 'notif:v1:highWind:1.0,2.0',
      lastDeliveredAtUtc: new Date(
        NOW.getTime() - PUSH_COOLDOWN_MS - 1000
      ).toISOString(),
      deliveryCount: 1,
    });
    const deps = makeDeps(ctx);

    const result = await routePushNotifications(
      [alertDoc('highWind', 'high', 'escalated')],
      deps,
      NOW
    );

    assert.equal(result.notificationsSent, 1);
    assert.equal(
      ctx.deliveryRecords.get('notif:v1:highWind:1.0,2.0')?.deliveryCount,
      2
    );
  });

  it('never pushes resolved or expired alerts', async () => {
    const ctx = newCtx();
    ctx.devicesByLocation.set('1.0,2.0', [device('tok-1', ['1.0,2.0'])]);
    const deps = makeDeps(ctx);

    const result = await routePushNotifications(
      [
        alertDoc('highWind', 'high', 'resolved'),
        alertDoc('rain', 'high', 'expired'),
      ],
      deps,
      NOW
    );

    assert.equal(result.alertsConsidered, 0);
    assert.equal(ctx.sentCount, 0);
  });

  it('deduplicates multiple alerts sharing a notification key in one batch', async () => {
    const ctx = newCtx();
    ctx.devicesByLocation.set('1.0,2.0', [device('tok-1', ['1.0,2.0'])]);
    const deps = makeDeps(ctx);

    // Two different fingerprints (different hour buckets) sharing the key.
    const a = alertDoc('highWind', 'high', 'detected');
    const b = {...alertDoc('highWind', 'high', 'detected')};
    b.fingerprint =
      'v1:highWind:1.0,2.0:' + new Date(Date.UTC(2026, 8, 6, 13)).toISOString();

    const result = await routePushNotifications([a, b], deps, NOW);

    assert.equal(result.alertsConsidered, 2);
    assert.equal(ctx.sentTokens.length, 1);
    assert.equal(result.notificationsSent, 1);
  });

  it('is robust when sendPush throws', async () => {
    const ctx = newCtx();
    ctx.devicesByLocation.set('1.0,2.0', [device('tok-1', ['1.0,2.0'])]);
    const deps = makeDeps(ctx);
    deps.sendPush = async () => {
      throw new Error('fcm failed');
    };

    const result = await routePushNotifications(
      [alertDoc('rain', 'moderate', 'detected')],
      deps,
      NOW
    );

    assert.equal(result.notificationsSent, 0);
  });
});
