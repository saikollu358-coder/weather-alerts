/**
 * WMO weather-code mapping — VERBATIM port of
 * `lib/services/weather_analysis/weather_code_mapper.dart` and the code-severity
 * tables in `weather_risk_evaluator.dart` (Phase 8).
 */

export const WMO_HAZARD_DEFINITIONS = [
  0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77,
  80, 81, 82, 85, 86, 95, 96, 99,
] as const;

export type WmoCode = (typeof WMO_HAZARD_DEFINITIONS)[number];

/** Mirrors WeatherCodeMapper.hazardsFor: a code may map to multiple hazards. */
export function hazardsFor(code: number): HazardName[] {
  switch (code) {
    case 0:
    case 1:
    case 2:
    case 3:
      return [];
    case 45:
    case 48:
      return ['fog'];
    case 51:
    case 53:
    case 55:
    case 61:
    case 63:
    case 65:
    case 80:
    case 81:
    case 82:
      return ['rain'];
    case 56:
    case 57:
    case 66:
    case 67:
      return ['ice', 'rain'];
    case 71:
    case 73:
    case 75:
    case 77:
    case 85:
    case 86:
      return ['snow'];
    case 95:
      return ['thunderstorm', 'lightning'];
    case 96:
    case 99:
      return ['thunderstorm', 'lightning', 'hail'];
    default:
      return [];
  }
}

export type HazardName =
  | 'thunderstorm'
  | 'rain'
  | 'flooding'
  | 'snow'
  | 'ice'
  | 'heat'
  | 'cold'
  | 'fog'
  | 'highWind'
  | 'hail'
  | 'lightning';

/** Mirrors the rain severity table in weather_risk_evaluator.dart. */
export function rainCodeSeverity(
  code: number
): 'none' | 'minor' | 'moderate' | 'high' {
  switch (code) {
    case 51:
    case 56:
    case 57:
    case 61:
    case 80:
      return 'minor';
    case 53:
    case 63:
    case 66:
    case 81:
      return 'moderate';
    case 55:
    case 65:
    case 67:
    case 82:
      return 'high';
    default:
      return 'none';
  }
}

/** Mirrors the freezing-code severity table in weather_risk_evaluator.dart. */
export function freezingCodeSeverity(
  code: number
): 'none' | 'moderate' | 'high' | 'severe' {
  switch (code) {
    case 56:
    case 57:
      return 'moderate';
    case 66:
      return 'high';
    case 67:
      return 'severe';
    default:
      return 'none';
  }
}

/** Mirrors the snow-code severity table in weather_risk_evaluator.dart. */
export function snowCodeSeverity(
  code: number
): 'none' | 'minor' | 'moderate' | 'high' {
  switch (code) {
    case 71:
    case 77:
    case 85:
      return 'minor';
    case 73:
      return 'moderate';
    case 75:
    case 86:
      return 'high';
    default:
      return 'none';
  }
}

/** Mirrors the fog-code severity table in weather_risk_evaluator.dart. */
export function fogCodeSeverity(code: number): 'none' | 'moderate' | 'high' {
  switch (code) {
    case 45:
      return 'moderate';
    case 48:
      return 'high';
    default:
      return 'none';
  }
}

/** Whether a code represents convective activity (thunder/lightning/hail). */
export function isConvective(code: number): boolean {
  return code === 95 || code === 96 || code === 99;
}

/** Whether a code carries a hail hazard (96/99 in WMO). */
export function carriesHail(code: number): boolean {
  return code === 96 || code === 99;
}
