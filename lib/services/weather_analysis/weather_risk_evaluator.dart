import '../../domain/entities/weather/weather_bundle.dart';
import 'risk_level.dart';
import 'safety_rules.dart';
import 'weather_analysis.dart';
import 'weather_hazard.dart';
import 'weather_risk_input.dart';
import 'weather_severity.dart';

/// Deterministic, rule-based weather-risk engine (Phase 8).
///
/// Rules:
///  - Pure: no I/O, no randomness, no time-of-day dependencies beyond the
///    caller-supplied `now`.
///  - No LLM: every decision is a threshold comparison from [SafetyRules].
///  - Portable: the same thresholds and comparisons are mirrored verbatim in
///    `functions/` so mobile and server agree byte-for-byte.
///
/// This is an application-grade risk assessment, never a guarantee. Official
/// warnings always take precedence (see `AppConstants.assessmentDisclaimer`).
class WeatherRiskEvaluator {
  const WeatherRiskEvaluator();

  /// Evaluates all hazards for [bundle] relative to [now].
  ///
  /// Returns a [WeatherAnalysis] whose findings are ordered by the hazard
  /// declaration order in [WeatherHazard].
  WeatherAnalysis analyze(WeatherBundle bundle, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    final input = WeatherRiskInput.fromBundle(
      bundle,
      now: reference,
    );
    final findings = <HazardFinding>[
      ..._windFindings(input),
      ..._temperatureFindings(input),
      ..._precipitationFindings(input),
      ..._snowFindings(input),
      ..._iceFindings(input),
      ..._fogFindings(input),
      ..._convectiveFindings(input),
    ];

    var overall = WeatherSeverity.none;
    for (final finding in findings) {
      if (finding.severity.index > overall.index) {
        overall = finding.severity;
      }
    }

    return WeatherAnalysis(
      riskLevel: RiskLevel.fromSeverity(overall),
      overallSeverity: overall,
      findings: findings,
      rulesVersion: SafetyRules.version,
      analyzedAtUtc: reference,
    );
  }

  /// Deterministic alert identity for deduplication / cooldown.
  ///
  /// Anchored to the UTC hour of [analyzedAtUtc] so the same hazard at the
  /// same location shares a fingerprint for a one-hour bucket, after which a
  /// new occurrence can be reported again.
  String fingerprintFor(WeatherHazard hazard, String locationKey, DateTime analyzedAtUtc) {
    final utc = analyzedAtUtc.toUtc();
    final hourBucket = DateTime.utc(utc.year, utc.month, utc.day, utc.hour);
    return 'v${SafetyRules.version}:${hazard.name}:$locationKey:'
        '${hourBucket.toIso8601String()}';
  }

  // ------------------------------------------------------------------
  // Case severity helpers (raw values -> severity). These mirror the traffic
  // lights in the official risk matrix and must stay in lock-step with
  // `functions/`.
  // ------------------------------------------------------------------

  WeatherSeverity _windSeverity(WeatherRiskInput input) {
    final gust = input.peakGustKmh;
    final sustained = input.peakSustainedWindKmh;
    var severity = WeatherSeverity.none;
    if (gust != null) {
      final s = SafetyRules.windGust.severityFor(gust);
      if (s.index > severity.index) severity = s;
    }
    if (sustained != null) {
      final s = SafetyRules.windSustained.severityFor(sustained);
      if (s.index > severity.index) severity = s;
    }
    return severity;
  }

  WeatherSeverity _heatSeverity(WeatherRiskInput input) {
    final peak = input.maxTemperatureC > input.maxApparentTemperatureC
        ? input.maxTemperatureC
        : input.maxApparentTemperatureC;
    return SafetyRules.heat.severityFor(peak);
  }

  WeatherSeverity _coldSeverity(WeatherRiskInput input) {
    final trough = input.minTemperatureC < input.minApparentTemperatureC
        ? input.minTemperatureC
        : input.minApparentTemperatureC;
    return SafetyRules.cold.severityFor(trough);
  }

  // ------------------------------------------------------------------
  // WMO-code severity tables (kept local to the engine; mappings are in
  // `weather_code_mapper.dart` for hazard classification).
  // ------------------------------------------------------------------

  static WeatherSeverity _rainCodeSeverity(int code) => switch (code) {
        51 || 61 || 80 || 56 || 57 => WeatherSeverity.minor,
        53 || 63 || 81 || 66 => WeatherSeverity.moderate,
        55 || 65 || 82 || 67 => WeatherSeverity.high,
        _ => WeatherSeverity.none,
      };

  static WeatherSeverity _freezingCodeSeverity(int code) => switch (code) {
        56 || 57 => WeatherSeverity.moderate,
        66 => WeatherSeverity.high,
        67 => WeatherSeverity.severe,
        _ => WeatherSeverity.none,
      };

  static WeatherSeverity _snowCodeSeverity(int code) => switch (code) {
        71 || 77 || 85 => WeatherSeverity.minor,
        73 => WeatherSeverity.moderate,
        75 || 86 => WeatherSeverity.high,
        _ => WeatherSeverity.none,
      };

  static WeatherSeverity _fogCodeSeverity(int code) => switch (code) {
        45 => WeatherSeverity.moderate,
        48 => WeatherSeverity.high,
        _ => WeatherSeverity.none,
      };

  // ------------------------------------------------------------------
  // Per-hazard finding builders.
  // ------------------------------------------------------------------

  List<HazardFinding> _windFindings(WeatherRiskInput input) {
    final severity = _windSeverity(input);
    if (severity == WeatherSeverity.none) return const [];
    final gust = input.peakGustKmh;
    final value = gust ?? input.peakSustainedWindKmh;
    return [
      HazardFinding(
        hazard: WeatherHazard.highWind,
        severity: severity,
        reason: 'Peak wind ${gust != null ? 'gusts' : 'speeds'} of '
            '${_fmt(value)} km/h expected within ${input.windowHours} h.',
        value: value,
        unit: 'km/h',
      ),
    ];
  }

  List<HazardFinding> _temperatureFindings(WeatherRiskInput input) {
    final heat = _heatSeverity(input);
    final cold = _coldSeverity(input);
    final findings = <HazardFinding>[];
    if (heat != WeatherSeverity.none) {
      findings.add(HazardFinding(
        hazard: WeatherHazard.heat,
        severity: heat,
        reason: 'Temperatures peaking at ${_fmt(input.maxTemperatureC)}°C '
            '(${_fmt(input.maxApparentTemperatureC)}°C apparent) within '
            '${input.windowHours} h.',
        value: input.maxApparentTemperatureC,
        unit: '°C',
      ));
    }
    if (cold != WeatherSeverity.none) {
      findings.add(HazardFinding(
        hazard: WeatherHazard.cold,
        severity: cold,
        reason: 'Temperatures dropping to ${_fmt(input.minTemperatureC)}°C '
            '(${_fmt(input.minApparentTemperatureC)}°C apparent) within '
            '${input.windowHours} h.',
        value: input.minApparentTemperatureC,
        unit: '°C',
      ));
    }
    return findings;
  }

  List<HazardFinding> _precipitationFindings(WeatherRiskInput input) {
    final findings = <HazardFinding>[];
    final rainFromCode = _rainCodeSeverity(input.currentWeatherCode);
    final rainUpcomingCodes = input.upcomingWeatherCodes;
    var upcomingRain = WeatherSeverity.none;
    for (final code in rainUpcomingCodes) {
      final s = _rainCodeSeverity(code);
      if (s.index > upcomingRain.index) upcomingRain = s;
    }
    final rainSeverity =
        rainFromCode.index >= upcomingRain.index ? rainFromCode : upcomingRain;

    if (rainSeverity != WeatherSeverity.none) {
      final where = rainFromCode.index >= upcomingRain.index
          ? 'now'
          : 'in the next ${input.windowHours} h';
      final label = switch (rainSeverity) {
        WeatherSeverity.minor => 'Light',
        WeatherSeverity.moderate => 'Moderate',
        WeatherSeverity.high => 'Heavy',
        _ => 'Rain',
      };
      findings.add(HazardFinding(
        hazard: WeatherHazard.rain,
        severity: rainSeverity,
        reason: '$label rain expected $where.',
      ));
    }

    final floodSeverity =
        SafetyRules.flooding.severityFor(input.maxDailyPrecipMm);
    if (floodSeverity != WeatherSeverity.none) {
      findings.add(HazardFinding(
        hazard: WeatherHazard.flooding,
        severity: floodSeverity,
        reason: 'Up to ${_fmt(input.maxDailyPrecipMm)} mm of rain in a single '
            'day within ${input.accumulationHours} h.',
        value: input.maxDailyPrecipMm,
        unit: 'mm',
      ));
    }
    return findings;
  }

  List<HazardFinding> _snowFindings(WeatherRiskInput input) {
    final fromCode = _snowCodeSeverity(input.currentWeatherCode);
    var upcomingSnow = WeatherSeverity.none;
    for (final code in input.upcomingWeatherCodes) {
      final s = _snowCodeSeverity(code);
      if (s.index > upcomingSnow.index) upcomingSnow = s;
    }
    final codeSeverity =
        fromCode.index >= upcomingSnow.index ? fromCode : upcomingSnow;
    final accumulationSeverity =
        SafetyRules.snow.severityFor(input.maxDailySnowMm);
    final severity = codeSeverity.index >= accumulationSeverity.index
        ? codeSeverity
        : accumulationSeverity;
    if (severity == WeatherSeverity.none) return const [];

    final cm = (input.maxDailySnowMm / 10).toStringAsFixed(1);
    return [
      HazardFinding(
        hazard: WeatherHazard.snow,
        severity: severity,
        reason: 'Snowfall of up to ${_fmt(input.maxDailySnowMm)} mm '
            'water-equivalent (~$cm cm) expected within '
            '${input.accumulationHours} h.',
        value: input.maxDailySnowMm,
        unit: 'mm',
      ),
    ];
  }

  List<HazardFinding> _iceFindings(WeatherRiskInput input) {
    if (input.maxTemperatureC > 2) return const [];
    var freezes = _freezingCodeSeverity(input.currentWeatherCode);
    for (final code in input.upcomingWeatherCodes) {
      final s = _freezingCodeSeverity(code);
      if (s.index > freezes.index) freezes = s;
    }
    if (freezes == WeatherSeverity.none) return const [];
    return [
      HazardFinding(
        hazard: WeatherHazard.ice,
        severity: freezes,
        reason: 'Freezing precipitation expected with temperatures at or below '
            '2°C — surfaces are likely slick.',
        value: input.maxTemperatureC,
        unit: '°C',
      ),
    ];
  }

  List<HazardFinding> _fogFindings(WeatherRiskInput input) {
    var fog = _fogCodeSeverity(input.currentWeatherCode);
    for (final code in input.upcomingWeatherCodes) {
      final s = _fogCodeSeverity(code);
      if (s.index > fog.index) fog = s;
    }
    if (fog == WeatherSeverity.none) return const [];
    return [
      HazardFinding(
        hazard: WeatherHazard.fog,
        severity: fog,
        reason: fog == WeatherSeverity.high
            ? 'Dense freezing-rime fog expected — visibility severely reduced.'
            : 'Fog expected — reduced visibility possible.',
        value: null,
      ),
    ];
  }

  List<HazardFinding> _convectiveFindings(WeatherRiskInput input) {
    final allCodes = [input.currentWeatherCode, ...input.upcomingWeatherCodes];
    var hasThunder = false;
    var hasHail = false;
    var hasLightning = false;
    for (final code in allCodes) {
      if (code == 95 || code == 96 || code == 99) {
        hasThunder = true;
        hasLightning = true;
      }
      if (code == 96 || code == 99) hasHail = true;
    }
    final findings = <HazardFinding>[];
    if (hasThunder) {
      findings.add(HazardFinding(
        hazard: WeatherHazard.thunderstorm,
        severity: WeatherSeverity.high,
        reason: 'Thunderstorm activity expected within ${input.windowHours} h.',
      ));
    }
    if (hasLightning) {
      findings.add(HazardFinding(
        hazard: WeatherHazard.lightning,
        severity: WeatherSeverity.high,
        reason: 'Lightning risk expected within ${input.windowHours} h.',
      ));
    }
    if (hasHail) {
      findings.add(HazardFinding(
        hazard: WeatherHazard.hail,
        severity: WeatherSeverity.high,
        reason: 'Thunderstorms with hail expected within ${input.windowHours} h.',
      ));
    }
    return findings;
  }

  static String _fmt(double? value) {
    if (value == null) return '--';
    final text = (value * 10).roundToDouble() / 10;
    final asString = text.toStringAsFixed(1);
    return asString.endsWith('.0') ? asString.substring(0, asString.length - 2) : asString;
  }
}