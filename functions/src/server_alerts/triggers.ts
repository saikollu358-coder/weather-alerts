/**
 * Scheduled server-side alert generation (Phase 10) with push routing (Phase 12).
 *
 * Runs every 15 minutes (mirrors `AppConstants.weatherRefreshInterval`),
 * evaluates every operator-registered region under `public` via the
 * verbatim Phase 8 engine, and upserts documents into the read-only
 * `server_alerts` collection keyed by the deterministic hour-bucket fingerprint.
 *
 * After alert generation, newly-detected or escalated alerts are routed to
 * FCM push notifications for device tokens whose monitored locations match.
 * Server-side cooldown (3 hours per notificationKey) prevents duplicate pushes.
 *
 * Firebase rules deny client writes to `server_alerts`; only this function
 * writes them. Nothing sensitive is logged: regions are public reference data
 * and Open-Meteo is unauthenticated.
 */

import {getFirestore} from 'firebase-admin/firestore';
import {getMessaging} from 'firebase-admin/messaging';
import {logger} from 'firebase-functions/v2';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {
  MonitoredRegion,
  ServerAlertDocument,
  parseMonitoredRegion,
} from './contract';
import {fetchWeatherBundle} from './openmeteo';
import {
  AlertPipelineDeps,
  PipelineLogger,
  runServerAlertGeneration,
} from './pipeline';
import {
  DeviceDocument,
  DeliveryRecord,
  NOTIFICATION_DELIVERIES_COLLECTION,
  PushRouterDeps,
  routePushNotifications,
} from './push_router';

const SERVER_ALERTS_COLLECTION = 'server_alerts';
const PUBLIC_COLLECTION = 'public';
const USERS_COLLECTION = 'users';
const DEVICES_SUBCOLLECTION = 'devices';

const triggerLogger: PipelineLogger = {
  debug: (tag, message) => logger.debug(message, {tag}),
  warning: (tag, message) => logger.warn(message, {tag}),
};

function buildPipelineDeps(): AlertPipelineDeps {
  const db = getFirestore();
  return {
    async listRegions() {
      const snapshot = await db.collection(PUBLIC_COLLECTION).get();
      const regions: MonitoredRegion[] = [];
      for (const doc of snapshot.docs) {
        const region = parseMonitoredRegion(doc.data(), doc.id);
        if (region !== null && region.enabled) regions.push(region);
      }
      return regions;
    },
    async fetchBundle(region) {
      return fetchWeatherBundle(region);
    },
    async loadPriorAlerts(locationKey) {
      const snapshot = await db
        .collection(SERVER_ALERTS_COLLECTION)
        .where('locationKey', '==', locationKey)
        .get();
      return snapshot.docs.map(doc => doc.data() as ServerAlertDocument);
    },
    async writeAlert(id, doc) {
      await db.collection(SERVER_ALERTS_COLLECTION).doc(id).set(doc);
    },
    async pruneExpired(now) {
      const snapshot = await db
        .collection(SERVER_ALERTS_COLLECTION)
        .where('expiresAtUtc', '<', now.toISOString())
        .get();
      let pruned = 0;
      for (const doc of snapshot.docs) {
        await doc.ref.delete();
        pruned++;
      }
      return pruned;
    },
  };
}

function buildPushRouterDeps(): PushRouterDeps {
  const db = getFirestore();
  const messaging = getMessaging();
  return {
    async findDevicesForLocation(locationKey: string) {
      // Query all users' device sub-collections for devices matching the location.
      // Firestore doesn't support cross-collection queries natively, so we
      // iterate through users. For production scale this would use a
      // denormalized `device_tokens` collection with a `locationKeys` array
      // and an `array-contains` filter. For now, the `public/<region>`
      // registry is small and the user base is expected to be modest.
      const usersSnapshot = await db.collection(USERS_COLLECTION).get();
      const devices: DeviceDocument[] = [];
      for (const userDoc of usersSnapshot.docs) {
        const devicesSnapshot = await userDoc.ref
          .collection(DEVICES_SUBCOLLECTION)
          .get();
        for (const deviceDoc of devicesSnapshot.docs) {
          const data = deviceDoc.data();
          const locationKeys = data['locationKeys'] as string[] | undefined;
          if (locationKeys && locationKeys.includes(locationKey)) {
            devices.push({
              token: (data['token'] as string) ?? '',
              deviceId: deviceDoc.id,
              uid: userDoc.id,
              locationKeys,
              platform: data['platform'] as string | undefined,
              createdAtUtc: data['createdAtUtc'] as number | undefined,
              updatedAtUtc: data['updatedAtUtc'] as number | undefined,
            });
          }
        }
      }
      return devices;
    },
    async getDeliveryRecord(notificationKey: string) {
      const doc = await db
        .collection(NOTIFICATION_DELIVERIES_COLLECTION)
        .doc(notificationKey)
        .get();
      if (!doc.exists) return null;
      return doc.data() as DeliveryRecord;
    },
    async setDeliveryRecord(notificationKey, record) {
      await db
        .collection(NOTIFICATION_DELIVERIES_COLLECTION)
        .doc(notificationKey)
        .set(record);
    },
    async sendPush(tokens, notification, data) {
      if (tokens.length === 0) return 0;
      // Firebase Admin multicast: up to 500 tokens per call.
      const message = {
        notification: {
          title: notification.title,
          body: notification.body,
        },
        data,
        tokens,
      };
      const response = await messaging.sendEachForMulticast(message);
      let successCount = 0;
      for (let i = 0; i < response.responses.length; i++) {
        const resp = response.responses[i];
        if (resp.success) {
          successCount++;
        } else {
          logger.warn('push send failed', {
            token: tokens[i].substring(0, 12) + '...',
            error: resp.error?.message ?? 'unknown',
          });
        }
      }
      return successCount;
    },
  };
}

/**
 * Retriggerable every-15-minutes alert generation with push notification
 * routing. Failures are logged and swallowed so a transient Open-Meteo
 * outage never poisons the schedule, and push failures never prevent
 * alert document persistence.
 */
export const generateServerAlerts = onSchedule(
  {
    schedule: 'every 15 minutes',
    timeZone: 'UTC',
    timeoutSeconds: 300,
    memory: '256MiB',
  },
  async () => {
    const now = new Date();
    let pipelineResult;
    try {
      pipelineResult = await runServerAlertGeneration(buildPipelineDeps(), {
        logger: triggerLogger,
        now,
      });
      logger.info('server alert generation complete', pipelineResult);
    } catch (error) {
      logger.error('server alert generation failed', error);
      return;
    }

    // Route push notifications for newly-detected / escalated alerts.
    if (pipelineResult.alertsWritten > 0) {
      try {
        const db = getFirestore();
        // Load only actionable alerts written in this run.
        // Since we don't have the written docs directly, load all active alerts
        // and let the router filter by status.
        const snapshot = await db
          .collection(SERVER_ALERTS_COLLECTION)
          .where('status', 'in', ['detected', 'escalated'])
          .get();
        const alerts = snapshot.docs.map(
          doc => doc.data() as ServerAlertDocument
        );
        const pushResult = await routePushNotifications(
          alerts,
          buildPushRouterDeps(),
          now,
          triggerLogger
        );
        logger.info('push routing complete', pushResult);
      } catch (error) {
        logger.error('push routing failed', error);
      }
    }
  }
);
