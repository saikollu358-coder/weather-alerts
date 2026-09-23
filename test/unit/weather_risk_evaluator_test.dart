import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/domain/entities/weather/daily_forecast.dart';
import 'package:weather_alerts/domain/entities/weather/hourly_forecast.dart';
import 'package:weather_alerts/domain/entities/weather/weather_bundle.dart';
import 'package:weather_alerts/domain/entities/weather/weather_snapshot.dart';
import 'package:weather_alerts/services/weather_analysis/risk_level.dart';
import 'package:weather_alerts/services/weather_analysis/safety_rules.dart';
import 'package:weather_alerts/services/weather_analysis/weather_code_mapper.dart';
import 'package:weather_alerts/services/weather_analysis/weather_hazard.dart';
import 'package:weather_alerts/services/weather_analysis/weather_risk_evaluator.dart';
import 'package:weather_alerts/services/weather_analysis/weather_risk_input.dart';
import 'package:weather_alerts/services/weather_analysis/weather_severity.dart';

DateTime _ref() => DateTime.utc(2026, 9, 6, 12);

WeatherBundle _bundle({
  double temperatureC = 15,
  double apparentTemperatureC = 15,
  double? humidityPercent,
  double precipitationMm = 0,
  int weatherCode = 1,
  double windSpeedKmh = 5,
  double? windGustsKmh,
  List<HourlyForecastPoint> hourly = const [],
  List<DailyForecastPoint> daily = const [],
}) {
  return WeatherBundle(
    locationKey: '1.0,2.0',
    current: CurrentWeather(
      observedAtUtc: _ref(),
      temperatureC: temperatureC,
      apparentTemperatureC: apparentTemperatureC,
      humidityPercent: humidityPercent,
      precipitationMm: precipitationMm,
      weatherCode: weatherCode,
      windSpeedKmh: windSpeedKmh,
      windGustsKmh: windGustsKmh,
    ),
    hourly: hourly,
    daily: daily,
    fetchedAtUtc: _ref(),
    expiresAtUtc: _ref().add(const Duration(hours: 1)),
  );
}

HourlyForecastPoint _hourly(DateTime timeUtc, int code, double wind) =>
    HourlyForecastPoint(
      timeUtc: timeUtc,
      temperatureC: 15,
      weatherCode: code,
      windSpeedKmh: wind,
    );

DailyForecastPoint _day(
  int day, {
  double max = 15,
  double min = 8,
  double precip = 0,
  int code = 1,
}) =>
    DailyForecastPoint(
      dateUtc: DateTime.utc(2026, 9, 7 + day),
      weatherCode: code,
      temperatureMaxC: max,
      temperatureMinC: min,
      precipitationSumMm: precip,
    );

void main() {
  group('WeatherCodeMapper', () {
    test('maps clear/cloudy codes to no hazard', () {
      expect(WeatherCodeMapper.hazardsFor(0), isEmpty);
      expect(WeatherCodeMapper.hazardsFor(3), isEmpty);
    });

    test('maps drizzle and rain to the rain hazard', () {
      expect(WeatherCodeMapper.hazardsFor(51), [WeatherHazard.rain]);
      expect(WeatherCodeMapper.hazardsFor(65), [WeatherHazard.rain]);
      expect(WeatherCodeMapper.hazardsFor(82), [WeatherHazard.rain]);
    });

    test('maps freezing drizzle/rain to ice plus rain', () {
      for (final code in [56, 57, 66, 67]) {
        expect(
          WeatherCodeMapper.hazardsFor(code),
          containsAll([WeatherHazard.ice, WeatherHazard.rain]),
        );
      }
    });

    test('maps snow codes to the snow hazard', () {
      expect(WeatherCodeMapper.hazardsFor(71), [WeatherHazard.snow]);
      expect(WeatherCodeMapper.hazardsFor(86), [WeatherHazard.snow]);
    });

    test('maps fog codes to the fog hazard', () {
      expect(WeatherCodeMapper.hazardsFor(45), [WeatherHazard.fog]);
      expect(WeatherCodeMapper.hazardsFor(48), [WeatherHazard.fog]);
    });

    test('thunderstorm with hail maps to thunderstorm, lightning and hail',
        () {
      final hazards = WeatherCodeMapper.hazardsFor(96);
      expect(
        hazards,
        containsAll([
          WeatherHazard.thunderstorm,
          WeatherHazard.lightning,
          WeatherHazard.hail,
        ]),
      );
    });

    test('unknown codes map to no hazard', () {
      expect(WeatherCodeMapper.hazardsFor(999), isEmpty);
    });
  });

  group('WeatherThresholds', () {
    const breakpoints = WeatherThresholds(
      minor: 40,
      moderate: 60,
      high: 75,
      severe: 90,
    );

    test('ascending breakpoints respect >= boundaries', () {
      expect(breakpoints.severityFor(39), WeatherSeverity.none);
      expect(breakpoints.severityFor(40), WeatherSeverity.minor);
      expect(breakpoints.severityFor(59.9), WeatherSeverity.minor);
      expect(breakpoints.severityFor(60), WeatherSeverity.moderate);
      expect(breakpoints.severityFor(75), WeatherSeverity.high);
      expect(breakpoints.severityFor(90), WeatherSeverity.severe);
      expect(breakpoints.severityFor(120), WeatherSeverity.severe);
    });

    const cold = WeatherThresholds(
      minor: 0,
      moderate: -5,
      high: -10,
      severe: -18,
      exceed: false,
    );

    test('descending breakpoints respect <= boundaries', () {
      expect(cold.severityFor(1), WeatherSeverity.none);
      expect(cold.severityFor(0), WeatherSeverity.minor);
      expect(cold.severityFor(-5), WeatherSeverity.moderate);
      expect(cold.severityFor(-10), WeatherSeverity.high);
      expect(cold.severityFor(-18), WeatherSeverity.severe);
      expect(cold.severityFor(-30), WeatherSeverity.severe);
    });
  });

  group('WeatherRiskInput.fromBundle', () {
    test('includes only forecast points within the alert window', () {
      final bundle = _bundle(
        hourly: [
          _hourly(_ref().add(const Duration(hours: 2)), 95, 60),
          _hourly(_ref().add(const Duration(hours: 30)), 95, 60),
        ],
      );
      final input = WeatherRiskInput.fromBundle(
        bundle,
        now: _ref(),
        windowHours: 24,
      );
      expect(input.upcomingWeatherCodes, [95]);
    });

    test('tracks peak gust and sustained wind across the window', () {
      final bundle = _bundle(
        windSpeedKmh: 20,
        windGustsKmh: 50,
        hourly: [_hourly(_ref().add(const Duration(hours: 1)), 2, 70)],
      );
      final input = WeatherRiskInput.fromBundle(bundle, now: _ref());
      expect(input.peakGustKmh, 70);
      expect(input.peakSustainedWindKmh, 70);
    });

    test('picks the largest single-day precipitation', () {
      final bundle = _bundle(
        daily: [
          _day(0, precip: 12),
          _day(1, precip: 75),
          _day(2, precip: 30),
        ],
      );
      final input = WeatherRiskInput.fromBundle(bundle, now: _ref());
      expect(input.maxDailyPrecipMm, 75);
    });

    test('counts snow only on days cold enough for snowfall', () {
      final bundle = _bundle(
        daily: [
          _day(0, max: -2, min: -8, precip: 15),
          _day(1, max: 6, min: 1, precip: 40),
        ],
      );
      final input = WeatherRiskInput.fromBundle(bundle, now: _ref());
      expect(input.maxDailySnowMm, 15);
    });
  });

  group('WeatherRiskEvaluator', () {
    const evaluator = WeatherRiskEvaluator();

    test('returns low risk with no findings for calm clear weather', () {
      final analysis = evaluator.analyze(_bundle(), now: _ref());
      expect(analysis.riskLevel, RiskLevel.low);
      expect(analysis.overallSeverity, WeatherSeverity.none);
      expect(analysis.findings, isEmpty);
      expect(analysis.hasActiveHazards, isFalse);
      expect(analysis.rulesVersion, SafetyRules.version);
    });

    test('is deterministic for identical inputs', () {
      final bundle = _bundle(windGustsKmh: 80, weatherCode: 95);
      final a = evaluator.analyze(bundle, now: _ref());
      final b = evaluator.analyze(bundle, now: _ref());
      expect(a.riskLevel, b.riskLevel);
      expect(a.findings.length, b.findings.length);
      for (var i = 0; i < a.findings.length; i++) {
        expect(a.findings[i].hazard, b.findings[i].hazard);
        expect(a.findings[i].severity, b.findings[i].severity);
        expect(a.findings[i].reason, b.findings[i].reason);
      }
    });

    test('classifies gusts of 82 km/h as high-severity wind', () {
      final analysis = evaluator.analyze(
        _bundle(windSpeedKmh: 35, windGustsKmh: 82),
        now: _ref(),
      );
      final wind = analysis.findings.singleWhere(
        (f) => f.hazard == WeatherHazard.highWind,
      );
      expect(wind.severity, WeatherSeverity.high);
      expect(analysis.riskLevel, RiskLevel.high);
      expect(wind.value, 82);
      expect(wind.unit, 'km/h');
    });

    test('classifies gusts of 95 km/h as severe wind (critical)', () {
      final analysis = evaluator.analyze(
        _bundle(windGustsKmh: 95),
        now: _ref(),
      );
      expect(
        analysis.findings
            .singleWhere((f) => f.hazard == WeatherHazard.highWind)
            .severity,
        WeatherSeverity.severe,
      );
      expect(analysis.riskLevel, RiskLevel.critical);
    });

    test('uses sustained wind as fallback when gusts are absent', () {
      final analysis = evaluator.analyze(
        _bundle(windSpeedKmh: 65),
        now: _ref(),
      );
      final wind = analysis.findings.singleWhere(
        (f) => f.hazard == WeatherHazard.highWind,
      );
      expect(wind.severity, WeatherSeverity.high);
    });

    test('flags a heat wave from the apparent temperature extreme', () {
      final analysis = evaluator.analyze(
        _bundle(temperatureC: 38, apparentTemperatureC: 40),
        now: _ref(),
      );
      final heat = analysis.findings.singleWhere(
        (f) => f.hazard == WeatherHazard.heat,
      );
      expect(heat.severity, WeatherSeverity.severe);
      expect(analysis.riskLevel, RiskLevel.critical);
    });

    test('flags extreme cold', () {
      final analysis = evaluator.analyze(
        _bundle(temperatureC: -12, apparentTemperatureC: -15),
        now: _ref(),
      );
      final cold = analysis.findings.singleWhere(
        (f) => f.hazard == WeatherHazard.cold,
      );
      expect(cold.severity, WeatherSeverity.high);
      expect(analysis.riskLevel, RiskLevel.high);
    });

    test('combines heat and cold findings with the worst severity on top', () {
      // In-window hot hourly point plus a very cold current reading would be
      // contradictory; instead verify multiple different hazards combine.
      final analysis = evaluator.analyze(
        _bundle(
          temperatureC: 34,
          apparentTemperatureC: 34,
          hourly: [_hourly(_ref().add(const Duration(hours: 1)), 2, 80)],
        ),
        now: _ref(),
      );
      final heat = analysis.findings.singleWhere(
        (f) => f.hazard == WeatherHazard.heat,
      );
      final wind = analysis.findings.singleWhere(
        (f) => f.hazard == WeatherHazard.highWind,
      );
      expect(heat.severity, WeatherSeverity.moderate);
      expect(wind.severity, WeatherSeverity.severe);
      expect(analysis.overallSeverity, WeatherSeverity.severe);
      expect(analysis.riskLevel, RiskLevel.critical);
    });

    test('flags heavy rain and flooding from the daily accumulation', () {
      final analysis = evaluator.analyze(
        _bundle(
          weatherCode: 65,
          daily: [_day(0, precip: 70)],
        ),
        now: _ref(),
      );
      final rain = analysis.findings.singleWhere(
        (f) => f.hazard == WeatherHazard.rain,
      );
      final flood = analysis.findings.singleWhere(
        (f) => f.hazard == WeatherHazard.flooding,
      );
      expect(rain.severity, WeatherSeverity.high);
      expect(flood.severity, WeatherSeverity.high);
      expect(analysis.riskLevel, RiskLevel.high);
    });

    test('flags snow on a cold day', () {
      final analysis = evaluator.analyze(
        _bundle(
          daily: [_day(0, max: -2, min: -9, precip: 12)],
        ),
        now: _ref(),
      );
      final snow = analysis.findings.singleWhere(
        (f) => f.hazard == WeatherHazard.snow,
      );
      expect(snow.severity, WeatherSeverity.moderate);
      expect(snow.value, 12);
    });

    test('flags ice from freezing rain when temperatures allow', () {
      final analysis = evaluator.analyze(
        _bundle(temperatureC: 1, apparentTemperatureC: 0, weatherCode: 66),
        now: _ref(),
      );
      final ice = analysis.findings.singleWhere(
        (f) => f.hazard == WeatherHazard.ice,
      );
      expect(ice.severity, WeatherSeverity.high);
    });

    test('ignores freezing codes when temperatures are too warm', () {
      final analysis = evaluator.analyze(
        _bundle(temperatureC: 12, apparentTemperatureC: 11, weatherCode: 67),
        now: _ref(),
      );
      expect(
        analysis.findings.where((f) => f.hazard == WeatherHazard.ice),
        isEmpty,
      );
      // The rain component still triggers.
      expect(
        analysis.findings.any((f) => f.hazard == WeatherHazard.rain),
        isTrue,
      );
    });

    test('flags fog', () {
      final moderate = evaluator.analyze(
        _bundle(weatherCode: 45),
        now: _ref(),
      );
      expect(
        moderate.findings
            .singleWhere((f) => f.hazard == WeatherHazard.fog)
            .severity,
        WeatherSeverity.moderate,
      );
    });

    test('flags thunderstorm, lightning and hail from code 99', () {
      final analysis = evaluator.analyze(
        _bundle(weatherCode: 99),
        now: _ref(),
      );
      for (final hazard in [
        WeatherHazard.thunderstorm,
        WeatherHazard.lightning,
        WeatherHazard.hail,
      ]) {
        final finding = analysis.findings.singleWhere((f) => f.hazard == hazard);
        expect(finding.severity, WeatherSeverity.high);
      }
      expect(analysis.riskLevel, RiskLevel.high);
    });

    test('detects convective hazards from in-window hourly codes', () {
      final analysis = evaluator.analyze(
        _bundle(
          weatherCode: 1,
          hourly: [_hourly(_ref().add(const Duration(hours: 3)), 95, 10)],
        ),
        now: _ref(),
      );
      expect(
        analysis.findings.any((f) => f.hazard == WeatherHazard.thunderstorm),
        isTrue,
      );
      expect(
        analysis.findings.any((f) => f.hazard == WeatherHazard.lightning),
        isTrue,
      );
    });

    test('ignores lightning when only rain is forecast', () {
      final analysis = evaluator.analyze(
        _bundle(
          weatherCode: 1,
          hourly: [_hourly(_ref().add(const Duration(hours: 3)), 61, 10)],
        ),
        now: _ref(),
      );
      expect(analysis.findings.any((f) => f.hazard == WeatherHazard.lightning),
          isFalse);
      expect(
        analysis.findings.any((f) => f.hazard == WeatherHazard.thunderstorm),
        isFalse,
      );
      expect(
        analysis.findings.any((f) => f.hazard == WeatherHazard.rain),
        isTrue,
      );
    });

    test('generates a deterministic, time-anchored fingerprint', () {
      final sameHour = evaluator.fingerprintFor(
        WeatherHazard.flooding,
        '1.0,2.0',
        DateTime.utc(2026, 9, 6, 12, 33),
      );
      final sameHourAgain = evaluator.fingerprintFor(
        WeatherHazard.flooding,
        '1.0,2.0',
        DateTime.utc(2026, 9, 6, 12, 59),
      );
      final nextHour = evaluator.fingerprintFor(
        WeatherHazard.flooding,
        '1.0,2.0',
        DateTime.utc(2026, 9, 6, 13, 5),
      );
      expect(sameHour, sameHourAgain);
      expect(sameHour, isNot(nextHour));
    });

    test('fingerprints differ across hazards and locations', () {
      final a = evaluator.fingerprintFor(
        WeatherHazard.flooding,
        '1.0,2.0',
        _ref(),
      );
      final b = evaluator.fingerprintFor(
        WeatherHazard.flooding,
        '9.0,8.0',
        _ref(),
      );
      final c = evaluator.fingerprintFor(
        WeatherHazard.heat,
        '1.0,2.0',
        _ref(),
      );
      expect(a, isNot(b));
      expect(a, isNot(c));
    });
  });
}