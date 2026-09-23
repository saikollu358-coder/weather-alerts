# Weather Safety Rules (Phase 8)

Centralized, deterministic weather-risk rule engine.

> **Positioning:** This is an application-generated weather-risk *assessment*.
> It is never a forecast or disaster prediction, and it never replaces official
> warnings, which always take precedence.

## Purpose

The app must classify raw weather data into hazards and severities using only
deterministic, versioned rules — no LLMs, no heuristics in widgets. This
document describes where the rules live, what they contain, and how to change
them safely.

## Source of truth

| Layer | Location | Responsibility |
| --- | --- | --- |
| Hazards | `lib/services/weather_analysis/weather_hazard.dart` | Canonical `WeatherHazard` enum (thunderstorm, rain, flooding, snow, ice, heat, cold, fog, highWind, hail, lightning). |
| Severity | `lib/services/weather_analysis/weather_severity.dart` | `WeatherSeverity` (none → minor → moderate → high → severe), ordered by `index`. |
| Risk level | `lib/services/weather_analysis/risk_level.dart` | `RiskLevel` (low/moderate/high/critical) derived from the worst severity. |
| WMO mapping | `lib/services/weather_analysis/weather_code_mapper.dart` | WMO weather-code → hazard categories. |
| **Thresholds** | `lib/services/weather_analysis/safety_rules.dart` | **The versioned rule set. Every threshold lives here.** |
| Aggregation | `lib/services/weather_analysis/weather_risk_input.dart` | Reduces a `WeatherBundle` to plain metrics (peaks, minima, accumulations) over 24 h alert and 72 h accumulation windows. |
| Evaluation | `lib/services/weather_analysis/weather_risk_evaluator.dart` | Pure function `analyze(bundle, {now}) → WeatherAnalysis` (findings + risk level). |
| Result model | `lib/services/weather_analysis/weather_analysis.dart` | `HazardFinding` + `WeatherAnalysis`; canonical strings for `AlertRecord`. |
| Provider | `lib/services/weather_analysis/weather_analysis_providers.dart` | Shared stateless `WeatherRiskEvaluator`. |

The Cloud Functions port mirrors this engine **verbatim** so the server-side
alert pipeline and the mobile client always agree:

`functions/src/weather_analysis/` → `rules.ts`, `wmo_codes.ts`, `analyze.ts`
(parity tests: `functions/src/test/rules.test.ts`).

## Threshold matrix (version 1, 2026-09-06)

All comparisons are *inclusive* (`>=` or `<=`). Peak values are taken across
current conditions plus the 24 h alert window; accumulations across 72 h.

| Hazard | Metric | minor | moderate | high | severe |
| --- | --- | --- | --- | --- | --- |
| High wind | peak gusts (km/h) | ≥ 40 | ≥ 60 | ≥ 75 | ≥ 90 |
| High wind | sustained (km/h) | ≥ 30 | ≥ 45 | ≥ 60 | ≥ 75 |
| Heat | max temp or apparent (°C) | ≥ 30 | ≥ 33 | ≥ 36 | ≥ 40 |
| Cold | min temp or apparent (°C) | ≤ 0 | ≤ −5 | ≤ −10 | ≤ −18 |
| Flooding | largest single-day rain (mm) | ≥ 20 | ≥ 40 | ≥ 60 | ≥ 100 |
| Snow | single-day water-equivalent (mm) | ≥ 5 | ≥ 10 | ≥ 20 | ≥ 35 |

### WMO-code severity tables

Code-driven severities are fixed (not thresholds):

* **Rain:** `51/56/57/61/80` minor · `53/63/66/81` moderate · `55/65/67/82` high.
* **Freezing (ice):** `56/57` moderate · `66` high · `67` severe (only when
  temperatures allow, i.e. max ≤ 2 °C).
* **Snow:** `71/77/85` minor · `73` moderate · `75/86` high.
* **Fog:** `45` moderate · `48` high.
* **Convective:** `95/96/99` → thunderstorm + lightning at *high*; `96/99` also
  hail at *high*.

### Snow and ice rules

* **Snow** only counts on days whose max *and* min temperature are ≤ 2 °C, so
  warm-season rain never masquerades as snow.
* **Ice** is reported only when the max temperature is ≤ 2 °C **and** a freezing
  drizzle/rain code is present.

## Changing a threshold

1. Edit `safety_rules.dart` *and* `functions/src/weather_analysis/rules.ts`.
2. Bump `SafetyRules.version` (Dart) and `RULES_VERSION` (TS) to the same value,
   and update `versionDate`.
3. Extend the parity tests in `test/unit/weather_risk_evaluator_test.dart` and
   `functions/src/test/rules.test.ts` (and `lib/domain/entities/alert_record.dart`
   docs if hazard/severity vocab changes).
4. Run both suites:
   ```sh
   flutter analyze && flutter test
   cd functions && npm test
   ```

Never modify thresholds ad hoc to make a test pass — that is exactly the
"Never modify safety thresholds to make tests pass" rule from AGENTS.md.

## Alert fingerprinting

[HazardFinding] and [WeatherAnalysis] are also used to produce a deterministic
`fingerprint` per hazard and location, anchored to the UTC hour
(`WeatherRiskEvaluator.fingerprintFor`). Alert-history deduplication (Phase 4)
uses fingerprints to suppress repeated identical alerts within the cooldown
window (`AppConstants.alertNotificationCooldown`).