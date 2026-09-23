/**
 * Cloud Functions entrypoint.
 *
 * Phase 8 exports the verbatim server port of the mobile weather-analysis
 * engine (`evaluateWeatherRisk`). Phase 10 adds the scheduled server-side
 * alert pipeline: it evaluates every operator-registered region on a 15-minute
 * schedule and writes deterministic, hour-bucket-keyed documents to the
 * read-only `server_alerts` collection — preserving a byte-for-byte agreement
 * between server-generated alerts and what the mobile client would produce.
 */

export {
  evaluateWeatherRisk,
  type WeatherAnalysisJson,
  type WeatherBundleJson,
  type HazardFindingJson,
  type CurrentWeatherJson,
  type HourlyForecastPointJson,
  type DailyForecastPointJson,
} from './weather_analysis/analyze';

export {
  RULES_VERSION,
  RULES_VERSION_DATE,
  severityForValue,
  type WeatherThresholds,
} from './weather_analysis/rules';

export {
  SERVER_ALERTS_RETENTION_MS,
  NOTIFICATION_KEY_PREFIX,
  DOC_SOURCE_ID,
  type AlertStatus,
  type SeverityId,
  type ServerAlertDocument,
  type MonitoredRegion,
  severityRank,
  isActionableSeverity,
  severityLabel,
  hazardLabel,
  alertFingerprint,
  notificationKeyFor,
  isActiveStatus,
  isValidCoordinate,
  isValidLocationKey,
  parseMonitoredRegion,
} from './server_alerts/contract';

export {
  DATA_SOURCE,
  WeatherFetchError,
  type FetchWeatherOptions,
  parseWeatherBody,
  fetchWeatherBundle,
} from './server_alerts/openmeteo';

export {evaluateLocation, type AlertDraft} from './server_alerts/publisher';

export {
  runServerAlertGeneration,
  type AlertPipelineDeps,
  type PipelineLogger,
  type PipelineResult,
  type RunOptions,
} from './server_alerts/pipeline';

export {generateServerAlerts} from './server_alerts/triggers';

export {
  PUSH_COOLDOWN_MS,
  NOTIFICATION_DELIVERIES_COLLECTION,
  DEVICES_SUBCOLLECTION,
  USERS_COLLECTION,
  type DeviceDocument,
  type DeliveryRecord,
  type PushRouterDeps,
  type PushRouterLogger,
  type PushRouterResult,
  routePushNotifications,
} from './server_alerts/push_router';

export {
  OFFICIAL_WARNINGS_COLLECTION,
  OFFICIAL_WARNING_CATEGORIES,
  OFFICIAL_WARNING_SEVERITIES,
  type OfficialWarning,
  type OfficialWarningCategory,
  type OfficialWarningSeverity,
  validateOfficialWarning,
  publishOfficialWarning,
} from './server_alerts/official_warnings';
