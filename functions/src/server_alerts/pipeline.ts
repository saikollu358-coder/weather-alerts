/**
 * Server-side alert generation orchestration (Phase 10).
 *
 * `runServerAlertGeneration` is pure with injected data-access so the full run
 * can be unit-tested without Firebase. The scheduled trigger
 * (`functions/src/server_alerts/triggers.ts`) wires real Firestore + Open-Meteo
 * dependencies into it.
 *
 * Failure semantics: a region whose weather cannot be fetched is SKIPPED rather
 * than resolved — data unavailable must never be interpreted as "conditions
 * cleared" (this mirrors the client, which only ingests on a successful load).
 */

import {evaluateWeatherRisk} from '../weather_analysis/analyze';
import {
  MonitoredRegion,
  ServerAlertDocument,
  isValidCoordinate,
  isValidLocationKey,
} from './contract';
import {evaluateLocation} from './publisher';
import type {WeatherBundleJson} from '../weather_analysis/analyze';

/** Logging seam; scheduled runs wire this to `firebase-functions/logger`. */
export interface PipelineLogger {
  debug(tag: string, message: string): void;
  warning(tag: string, message: string): void;
}

/** Injectable data-access surface for the pipeline. */
export interface AlertPipelineDeps {
  /** Loads operator-registered monitored regions. */
  listRegions(): Promise<MonitoredRegion[]>;
  /** Fetches a fresh weather bundle for a region. */
  fetchBundle(region: MonitoredRegion): Promise<WeatherBundleJson>;
  /** Loads current `server_alerts` documents for a location. */
  loadPriorAlerts(locationKey: string): Promise<ServerAlertDocument[]>;
  /** Persists/upserts one alert document. */
  writeAlert(id: string, doc: ServerAlertDocument): Promise<void>;
  /** Removes expired `server_alerts` documents. Returns the number removed. */
  pruneExpired(now: Date): Promise<number>;
}

export interface PipelineResult {
  regionsScanned: number;
  regionsEvaluated: number;
  alertsWritten: number;
  expiredPruned: number;
}

const silentLogger: PipelineLogger = {
  debug: () => {},
  warning: () => {},
};

export interface RunOptions {
  now?: Date;
  logger?: PipelineLogger;
}

export async function runServerAlertGeneration(
  deps: AlertPipelineDeps,
  options: RunOptions = {}
): Promise<PipelineResult> {
  const logger = options.logger ?? silentLogger;
  const now = options.now ?? new Date();
  const regions = await deps.listRegions();
  let evaluated = 0;
  let written = 0;

  for (const region of regions) {
    if (
      !isValidCoordinate(region.latitude, region.longitude) ||
      !isValidLocationKey(region.locationKey)
    ) {
      logger.warning(
        'runServerAlertGeneration',
        `skipping invalid region ${region.docId}`
      );
      continue;
    }

    let bundle: WeatherBundleJson;
    try {
      bundle = await deps.fetchBundle(region);
    } catch (error) {
      logger.warning(
        'runServerAlertGeneration',
        `fetch failed for ${region.docId}: ${String(error)}`
      );
      continue;
    }

    const analysis = evaluateWeatherRisk(bundle, {now});
    const prior = await deps.loadPriorAlerts(region.locationKey);
    const drafts = evaluateLocation(analysis, region, prior, now);

    for (const draft of drafts) {
      await deps.writeAlert(draft.id, draft.doc);
      written++;
    }
    evaluated++;
    logger.debug(
      'runServerAlertGeneration',
      `${region.docId}: ${drafts.length} alert document(s)`
    );
  }

  const expiredPruned = await deps.pruneExpired(now);
  logger.debug(
    'runServerAlertGeneration',
    `pruned ${expiredPruned} expired document(s)`
  );

  return {
    regionsScanned: regions.length,
    regionsEvaluated: evaluated,
    alertsWritten: written,
    expiredPruned,
  };
}
