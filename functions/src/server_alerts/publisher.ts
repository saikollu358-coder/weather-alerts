/**
 * Converts an analysis into `server_alerts` documents (Phase 10).
 *
 * Mirrors the mobile `AlertIngestUseCase` ingestion decisions:
 *   - a fresh fingerprint -> `detected`;
 *   - an existing active alert whose severity grew -> `escalated`;
 *   - otherwise the existing status is kept;
 *   - hazards that were active for the location but are no longer present in
 *     the latest analysis -> `resolved`.
 *
 * Pure and deterministic; the status transition table is identical to the
 * client so server-generated history can be merged without drift.
 */

import {
  DOC_SOURCE_ID,
  SERVER_ALERTS_RETENTION_MS,
  ServerAlertDocument,
  alertFingerprint,
  hazardLabel,
  isActionableSeverity,
  isActiveStatus,
  notificationKeyFor,
  severityLabel,
  severityRank,
} from './contract';
import {MonitoredRegion} from './contract';
import type {WeatherAnalysisJson} from '../weather_analysis/analyze';

/** A document ready for `server_alerts/<id>` writing. */
export interface AlertDraft {
  id: string;
  doc: ServerAlertDocument;
}

/** Builds every draft (new, updated or resolved) for one location/analysis. */
export function evaluateLocation(
  analysis: WeatherAnalysisJson,
  region: MonitoredRegion,
  prior: ServerAlertDocument[],
  now: Date
): AlertDraft[] {
  const nowIso = now.toISOString();
  const expiresIso = new Date(
    now.getTime() + SERVER_ALERTS_RETENTION_MS
  ).toISOString();
  const drafts: AlertDraft[] = [];
  const activeHazards = new Set<string>();

  for (const finding of analysis.findings) {
    if (!isActionableSeverity(finding.severity)) continue;
    activeHazards.add(finding.hazard);
    const fingerprint = alertFingerprint(
      finding.hazard,
      region.locationKey,
      now
    );
    const existing = prior.find(
      candidate => candidate.fingerprint === fingerprint
    );

    // isFresh covers both first detection and re-detection after a resolution
    // within the same hour bucket (mirrors `AlertRecord.isActive`).
    const isFresh = existing === undefined || !isActiveStatus(existing.status);
    const severityGrew =
      existing !== undefined &&
      severityRank(existing.severity) < severityRank(finding.severity);
    const status = isFresh
      ? 'detected'
      : severityGrew
        ? 'escalated'
        : existing.status;

    drafts.push({
      id: fingerprint,
      doc: {
        fingerprint,
        notificationKey: notificationKeyFor(finding.hazard, region.locationKey),
        hazard: finding.hazard,
        severity: finding.severity as ServerAlertDocument['severity'],
        status,
        title: `${severityLabel(finding.severity)} ${hazardLabel(finding.hazard)}`,
        description: finding.reason,
        reason: finding.reason,
        locationKey: region.locationKey,
        payload: {
          value: finding.value ?? null,
          unit: finding.unit ?? null,
          rulesVersion: analysis.rulesVersion,
        },
        detectedAtUtc: existing?.detectedAtUtc ?? nowIso,
        updatedAtUtc: nowIso,
        resolvedAtUtc: null,
        expiresAtUtc: expiresIso,
        acknowledged: existing?.acknowledged ?? false,
        source: DOC_SOURCE_ID,
        riskLevel: analysis.riskLevel,
        overallSeverity:
          analysis.overallSeverity as ServerAlertDocument['overallSeverity'],
        assessedAtUtc: nowIso,
      },
    });
  }

  // Resolve previously-active hazards that are no longer present in the latest
  // analysis for this location. The update reuses the original fingerprint id.
  for (const priorDoc of prior) {
    if (priorDoc.locationKey !== region.locationKey) continue;
    if (!isActiveStatus(priorDoc.status)) continue;
    if (activeHazards.has(priorDoc.hazard)) continue;
    drafts.push({
      id: priorDoc.fingerprint,
      doc: {
        ...priorDoc,
        status: 'resolved',
        updatedAtUtc: nowIso,
        resolvedAtUtc: nowIso,
      },
    });
  }

  return drafts;
}
