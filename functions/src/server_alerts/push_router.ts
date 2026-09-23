/**
 * Push notification routing (Phase 12).
 *
 * After the server-side alert pipeline (Phase 10) writes or updates alert
 * documents, this module resolves which device tokens should receive an FCM
 * push and delivers them. The cooldown mirrors the client-side
 * `AppConstants.alertNotificationCooldown` (3 hours), enforced server-side
 * via `notification_deliveries` to prevent duplicate pushes even when the
 * client background task fires in parallel.
 *
 * Pure with injected data-access for unit testing; the real Firestore +
 * FCM wiring is in `triggers.ts`.
 */

import type {ServerAlertDocument} from './contract';
import {DOC_SOURCE_ID, isActiveStatus} from './contract';

/** Cooldown between pushes for the same notification key (3 hours). */
export const PUSH_COOLDOWN_MS = 3 * 60 * 60 * 1000;

/** Collection that tracks per-notificationKey push delivery timestamps. */
export const NOTIFICATION_DELIVERIES_COLLECTION = 'notification_deliveries';

/** Collection that stores device tokens under each user. */
export const DEVICES_SUBCOLLECTION = 'devices';
export const USERS_COLLECTION = 'users';

/**
 * A device document from `users/{uid}/devices/{deviceId}`.
 *
 * The client writes this via `DeviceTokenFirestoreRepository` (Phase 12 Dart).
 * The `locationKeys` array is the join key: only devices whose `locationKeys`
 * includes the alert's `locationKey` receive the push.
 */
export interface DeviceDocument {
  token: string;
  deviceId: string;
  uid: string;
  locationKeys: string[];
  platform?: string;
  createdAtUtc?: number;
  updatedAtUtc?: number;
}

/** Delivery record used to enforce the cooldown. */
export interface DeliveryRecord {
  notificationKey: string;
  lastDeliveredAtUtc: string;
  deliveryCount: number;
}

/** Injectable data-access surface for the push router. */
export interface PushRouterDeps {
  /**
   * Finds all device documents whose `locationKeys` array contains
   * [locationKey]. Called once per unique locationKey in the batch.
   */
  findDevicesForLocation(locationKey: string): Promise<DeviceDocument[]>;

  /** Reads the delivery record for a notification key, or null. */
  getDeliveryRecord(notificationKey: string): Promise<DeliveryRecord | null>;

  /** Persists (upserts) a delivery record. */
  setDeliveryRecord(
    notificationKey: string,
    record: DeliveryRecord
  ): Promise<void>;

  /** Sends an FCM push to one or more tokens. Returns the number of sends. */
  sendPush(
    tokens: string[],
    notification: {title: string; body: string},
    data: Record<string, string>
  ): Promise<number>;
}

export interface PushRouterResult {
  alertsConsidered: number;
  notificationsSent: number;
  devicesReached: number;
  cooldownSuppressed: number;
}

const silentLogger = {
  debug() {},
  warning() {},
};

export interface PushRouterLogger {
  debug(tag: string, message: string): void;
  warning(tag: string, message: string): void;
}

/**
 * Routes push notifications for a batch of alert documents.
 *
 * Only `detected` and `escalated` alerts trigger pushes; `resolved` and
 * `expired` alerts are silently skipped (the client handles local cleanup).
 *
 * For each actionable alert:
 * 1. Check the server-side cooldown via `notification_deliveries`.
 * 2. If cooled down, find all device tokens whose `locationKeys` match.
 * 3. Send a multicast FCM push with the alert payload.
 * 4. Record the delivery timestamp.
 */
export async function routePushNotifications(
  alerts: ServerAlertDocument[],
  deps: PushRouterDeps,
  now: Date,
  logger: PushRouterLogger = silentLogger
): Promise<PushRouterResult> {
  let considered = 0;
  let sent = 0;
  let reached = 0;
  let suppressed = 0;

  // Only push for newly-detected or escalated alerts.
  const actionable = alerts.filter(
    a =>
      a.source === DOC_SOURCE_ID &&
      (a.status === 'detected' || a.status === 'escalated') &&
      isActiveStatus(a.status)
  );

  // Deduplicate by notificationKey to avoid duplicate pushes for the same
  // hazard+location pair (the pipeline may produce multiple documents with
  // different fingerprints but the same notificationKey within a batch).
  const seen = new Set<string>();

  for (const alert of actionable) {
    considered++;
    const nKey = alert.notificationKey;
    if (seen.has(nKey)) continue;
    seen.add(nKey);

    // Server-side cooldown check.
    const delivery = await deps.getDeliveryRecord(nKey);
    if (delivery !== null) {
      const lastDelivery = new Date(delivery.lastDeliveredAtUtc).getTime();
      if (now.getTime() - lastDelivery < PUSH_COOLDOWN_MS) {
        suppressed++;
        continue;
      }
    }

    // Find matching devices.
    const devices = await deps.findDevicesForLocation(alert.locationKey);
    if (devices.length === 0) continue;

    const tokens = devices.map(d => d.token).filter(t => t.length > 0);
    if (tokens.length === 0) continue;

    // Build the push payload.
    const title = alert.title;
    const body =
      alert.description || `A ${alert.hazard} hazard has been detected.`;
    const data: Record<string, string> = {
      fingerprint: alert.fingerprint,
      notificationKey: nKey,
      locationKey: alert.locationKey,
      hazard: alert.hazard,
      severity: alert.severity,
      status: alert.status,
      rulesVersion: String(alert.payload.rulesVersion),
    };

    try {
      const count = await deps.sendPush(tokens, {title, body}, data);
      sent += count;
      reached += tokens.length;

      // Record delivery for cooldown.
      await deps.setDeliveryRecord(nKey, {
        notificationKey: nKey,
        lastDeliveredAtUtc: now.toISOString(),
        deliveryCount: (delivery?.deliveryCount ?? 0) + 1,
      });
    } catch (error) {
      logger.warning(
        'routePushNotifications',
        `FCM send failed for ${nKey}: ${String(error)}`
      );
    }
  }

  return {
    alertsConsidered: considered,
    notificationsSent: sent,
    devicesReached: reached,
    cooldownSuppressed: suppressed,
  };
}
