# Server-Side Alerts

Phase 10 wiring: a scheduled Cloud Function that regenerates weather alerts
server-side. Each alert lives in the read-only `server_alerts` collection,
keyed by the same deterministic hour-bucket fingerprint the mobile client uses,
so server-generated history and client-side alerts can never diverge.

Push notification routing: after regeneration,
newly-behavior alerts (`detected`/`escalated`) are routed to the FCM tokens of
every device whose `locationKeys` include the alert's location, enforcing
a server-side cooldown.

Official warnings (`official_warnings`) are operator-seeded contracts; there is
no authoritative feed, so nothing generates them automatically. Both document
sets are read-only for clients (firestore.rules) — only the Admin SDK writes.

## Components (`functions/src/server_alerts/`)

| File | Responsibility |
| --- | --- |
| `contract.ts` | Document contracts for `server_alerts`, region registry (`public/<regionId>`), official warning shape; the fingerprint / notification-key builders and latitude/longitude/location-key validation. |
| `openmeteo.ts` | Open-Meteo `/forecast` fetch mirroring `OpenMeteoWeatherService` (same URL, params, `timezone=UTC`, `forecast_days=7`). Converts the API's parallel arrays into the point-object lists `evaluateWeatherRisk` consumes. |
| `pipeline.ts` | Pure orchestrator `runServerAlertGeneration(deps)` with injected data access: list regions → fetch bundle → evaluate with the verbatim Phase 8 engine → compute drafts → write → prune expired. |
| `publisher.ts` | `evaluateLocation(analysis, region, prior, now)`: fresh → `detected`, severity grew → `escalated`, otherwise keep status; clears hazards no longer present → `resolved`. Mirrors `AlertIngestUseCase`. |
| `push_router.ts` | **Phase 12.** `routePushNotifications(alerts, deps, now)`: filters active (`detected`/`escalated`) server alerts, applies the per-notificationKey cooldown, matches device tokens by location, sends FCM multicast pushes and records delivery. Pure with injected data access. |
| `triggers.ts` | `generateServerAlerts`: `onSchedule('every 15 minutes')` (UTC) wiring real Firestore + Open-Meteo into the pipeline, then routing active alerts to FCM via the Admin SDK. |
| `official_warnings.ts` | Official-warning contract + `validateOfficialWarning` + admin-only `publishOfficialWarning` writer. |

The scheduler runs every 15 minutes, matching the app's `weatherRefreshInterval`.

## Collection layout

| Path | Owner | Readable by | Written by |
| --- | --- | --- | --- |
| `server_alerts/<fingerprint>` | Cloud Functions | signed-in clients | functions (rules deny clients) |
| `official_warnings/<id>` | operators | signed-in clients | admin/seed scripts |
| `public/<regionId>` | operators | everyone | admin (rules deny clients) |
| `users/<uid>/devices/<deviceId>` | the user | the user | the user (Phase 12 FCM token registry) |
| `notification_deliveries/<notificationKey>` | Cloud Functions | no one | functions (push cooldown) |

## Identity parity

The document **id of a server alert equals the fingerprint**:

```
v{RULES_VERSION}:{hazard}:{locationKey}:{UTC-hour-bucket ISO-8601}
```

It is computed by `alertFingerprint` (mirrors
`WeatherRiskEvaluator.fingerprintFor`). The same hazard + location share a doc
for a one-hour bucket, then a new occurrence gets a new id. Resolutions are
written as updates to the *original* fingerprint doc.

Each document also carries `notificationKey`:

```
notif:v{RULES_VERSION}:{hazard}:{locationKey}
```

— deliberately without the hour bucket, matching
`BackgroundWeatherCheckUseCase.notificationKeyFor`. Phase 12 uses that key as
the cooldown identity: a push is only delivered when no push for the same key
happened within `PUSH_COOLDOWN_MS` (3 hours, mirroring
`AppConstants.alertNotificationCooldown`).

## Push routing (Phase 12)

After the pipeline writes alert documents, `generateServerAlerts` loads every
active (`detected`/`escalated`) server alert and hands it to
`routePushNotifications`. For each alert it:

1. computes the `notificationKey` cooldown identity;
2. skips the alert when a `notification_deliveries` record shows a push inside
   the cooldown window;
3. joins the alert's `locationKey` against `users/{uid}/devices/*.locationKeys`
   to find matching FCM tokens;
4. sends one FCM **multicast** message (title/body from the alert document,
   data payload carrying `fingerprint`, `notificationKey`, `locationKey`,
   `hazard`, `severity`, `status`, `rulesVersion`);
5. records the delivery timestamp and increments the count.

Client counterpart: `DeviceTokenService` (Flutter) registers the device token and
writes its `locationKeys` from the device's own current position via
`syncCurrentLocation()` whenever the app captures a fix (or when the FCM token is
rotated). It holds **at most one** key — the app has no saved places — so a push
is delivered to exactly the devices standing in the affected area. The client's
`NotificationAppBootstrap` forwards foreground pushes to the local notification
tray. Push failures are logged and
swallowed — a failed send never rolls back alert persistence, and an
Open-Meteo outage never poisons the schedule.

Tapping one of these pushes opens the in-app alert detail route
(`/alerts/:id`) via `AlertTapController`, which consumes the same
`fingerprint` key — see `NOTIFICATIONS_BACKGROUND_MONITORING.md#tapping-a-notification`.

**Scale note:** `findDevicesForLocation` currently scans `users/{uid}/devices`
per location key. For larger user bases this should be replaced with a
fan-out `device_tokens/{tokenId}` collection queried with `array-contains` —
flagged for a follow-up phase, not part of this milestone.

## Status transitions (publisher)

For every actionable finding (`severity` above `none`):

- no prior doc, or prior doc `resolved`/`expired` → **detected**;
- prior active doc, severity rank increased → **escalated**;
- otherwise the existing status is preserved.

After processing findings, any previously-active doc for the location whose
hazard is absent from the latest analysis is marked **resolved**. Expired docs
are pruned by `pruneExpired` each run. Retention is 7 days
(`SERVER_ALERTS_RETENTION_MS`, mirrors `AppConstants.alertRetention`).

Failure semantics: a region whose weather cannot be fetched is *skipped*
(never resolved) — unavailable data must not be treated as "conditions
cleared". This is why trigger failures are logged and swallowed.

## Region registry

Regions evaluated server-side are stored as documents under `public/<regionId>`:
`{ name, latitude, longitude, locationKey, enabled, updatedAtUtc }`.

- `locationKey` defaults to `lat,lng` and must match
  `<latitude>,<longitude>`.
- `enabled` defaults true.
- The pipeline only evaluates regions that parse and are enabled.

The registry is operator-maintained (clients cannot write under `/public`).

## Official warnings

Shape is fixed in `official_warnings.ts`; `validateOfficialWarning` enforces it
before writing. Design:

- `id` is a stable lowercase slug used as the doc id.
- `severity` comes from the mobile vocabulary (`minor`…`severe`).
- `effectiveFromUtc`/`effectiveUntilUtc` bound the validity window.
- `locationKey` is optional and, when present, targets one area.

There is no live authoritative feed yet, so nothing ingests them
automatically; operators publish via `publishOfficialWarning` or seed scripts.

## Determinism & safety

- Same engine as the client: `evaluateWeatherRisk` runs the verbatim Phase 8
  port (`functions/src/weather_analysis/`).
- No LLM anywhere in the alert path — every decision is a threshold comparison.
- No secrets or tokens are logged; Open-Meteo is public and unauthenticated.
- Nothing here is a guarantee: automatic assessments are advisory only and
  official warnings always take precedence.

## Verify

```sh
cd functions
npm run lint
npm test            # builds then runs node --test (rules + server_alerts + push_router)
```

From the repo root, `flutter analyze` and `flutter test` must stay green.