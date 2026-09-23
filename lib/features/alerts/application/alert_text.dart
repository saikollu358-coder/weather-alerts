import '../../../services/weather_analysis/risk_level.dart';
import '../../../services/weather_analysis/weather_hazard.dart';
import '../../../services/weather_analysis/weather_severity.dart';

/// Human labels for the analysis-engine vocabulary.
///
/// Kept separate from the pure analysis engine so thresholds and classification
/// stay portable to `functions/`, while display text lives in the UI layer.

/// Display label for a hazard, e.g. `Thunderstorm`, `High wind`.
String hazardLabel(WeatherHazard hazard) => switch (hazard) {
      WeatherHazard.thunderstorm => 'Thunderstorm',
      WeatherHazard.rain => 'Rain',
      WeatherHazard.flooding => 'Flooding',
      WeatherHazard.snow => 'Snow',
      WeatherHazard.ice => 'Ice',
      WeatherHazard.heat => 'Heat',
      WeatherHazard.cold => 'Cold',
      WeatherHazard.fog => 'Fog',
      WeatherHazard.highWind => 'High wind',
      WeatherHazard.uvExposure => 'UV exposure',
      WeatherHazard.airQuality => 'Air quality',
      WeatherHazard.hail => 'Hail',
      WeatherHazard.lightning => 'Lightning',
      WeatherHazard.drought => 'Drought',
    };

/// Display label for a severity, e.g. `Moderate`, `Severe`.
String severityLabel(WeatherSeverity severity) => switch (severity) {
      WeatherSeverity.none => 'None',
      WeatherSeverity.minor => 'Minor',
      WeatherSeverity.moderate => 'Moderate',
      WeatherSeverity.high => 'High',
      WeatherSeverity.severe => 'Severe',
    };

/// Display label for a risk level, e.g. `High risk`.
String riskLabel(RiskLevel level) => switch (level) {
      RiskLevel.low => 'Low risk',
      RiskLevel.moderate => 'Moderate risk',
      RiskLevel.high => 'High risk',
      RiskLevel.critical => 'Critical risk',
    };