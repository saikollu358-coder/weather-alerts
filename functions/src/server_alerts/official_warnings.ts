/**
 * Official warnings contract (Phase 10).
 *
 * Unlike `server_alerts` — which are generated automatically from the
 * rule-based engine — official warnings are OPERATOR-SEEDED. There is no
 * authoritative third-party feed wired in, so this module only fixes the
 * document contract, validates any warning before it is written, and provides
 * an admin-only writer for seeding/update scripts. Official warnings always
 * take precedence over automatic assessments (see `AppConstants.assessmentDisclaimer`).
 */

import type {Firestore} from 'firebase-admin/firestore';
import {isValidLocationKey} from './contract';

export const OFFICIAL_WARNINGS_COLLECTION = 'official_warnings';

export const OFFICIAL_WARNING_CATEGORIES = [
  'flood',
  'storm',
  'heat',
  'cold',
  'wind',
  'tornado',
  'wildfire',
  'airquality',
  'advisory',
] as const;
export type OfficialWarningCategory =
  (typeof OFFICIAL_WARNING_CATEGORIES)[number];

export const OFFICIAL_WARNING_SEVERITIES = [
  'minor',
  'moderate',
  'high',
  'severe',
] as const;
export type OfficialWarningSeverity =
  (typeof OFFICIAL_WARNING_SEVERITIES)[number];

/** A warning issued by an authority for display to users. */
export interface OfficialWarning {
  /** Stable slug used as the Firestore document id. */
  id: string;
  title: string;
  body: string;
  category: OfficialWarningCategory;
  severity: OfficialWarningSeverity;
  /** Authority issuing the warning, e.g. `National Weather Service`. */
  source: string;
  issuedAtUtc: string;
  effectiveFromUtc: string;
  effectiveUntilUtc: string;
  /** Target `lat,lng`, or null for a region-wide warning. */
  locationKey?: string | null;
  /** Human-readable target area, e.g. `Austin, TX`. */
  locationName?: string | null;
  /** Last server write time (set by [publishOfficialWarning]). */
  updatedAtUtc?: string;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0;
}

function isValidIsoUtc(value: unknown): boolean {
  if (typeof value !== 'string') return false;
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) return false;
  return new Date(parsed).toISOString() === value;
}

/** True when [warning] is a well-formed official warning document. */
export function validateOfficialWarning(
  warning: unknown
): warning is OfficialWarning {
  if (typeof warning !== 'object' || warning === null) return false;
  const candidate = warning as Record<string, unknown>;
  if (
    !/^[a-z0-9-]{1,128}$/.test(
      typeof candidate['id'] === 'string' ? candidate['id'] : ''
    )
  ) {
    return false;
  }
  if (!isNonEmptyString(candidate['title'])) return false;
  if (!isNonEmptyString(candidate['body'])) return false;
  if (!isNonEmptyString(candidate['source'])) return false;
  if (
    !OFFICIAL_WARNING_CATEGORIES.includes(
      candidate['category'] as OfficialWarningCategory
    )
  ) {
    return false;
  }
  if (
    !OFFICIAL_WARNING_SEVERITIES.includes(
      candidate['severity'] as OfficialWarningSeverity
    )
  ) {
    return false;
  }
  if (!isValidIsoUtc(candidate['issuedAtUtc'])) return false;
  if (!isValidIsoUtc(candidate['effectiveFromUtc'])) return false;
  const effectiveUntil = candidate['effectiveUntilUtc'];
  if (!isValidIsoUtc(effectiveUntil)) return false;
  if (
    Date.parse(effectiveUntil as string) <
    Date.parse(candidate['effectiveFromUtc'] as string)
  ) {
    return false;
  }
  const locationKey = candidate['locationKey'];
  if (locationKey !== null && locationKey !== undefined) {
    if (typeof locationKey !== 'string' || !isValidLocationKey(locationKey))
      return false;
  }
  const locationName = candidate['locationName'];
  if (
    locationName !== null &&
    locationName !== undefined &&
    typeof locationName !== 'string'
  )
    return false;
  return true;
}

/**
 * Validates and writes an official warning. Admin-only: clients are denied by
 * Firestore rules; this helper is for operator seeding/update scripts and
 * future authoritative feeds.
 */
export async function publishOfficialWarning(
  db: Firestore,
  warning: OfficialWarning
): Promise<void> {
  if (!validateOfficialWarning(warning)) {
    throw new TypeError('invalid official warning');
  }
  await db
    .collection(OFFICIAL_WARNINGS_COLLECTION)
    .doc(warning.id)
    .set({...warning, updatedAtUtc: new Date().toISOString()});
}
