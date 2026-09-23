import 'package:flutter/material.dart';

import '../../../services/weather_analysis/weather_severity.dart';

/// Material color for a hazard severity, shared across alert surfaces.
///
/// Resolve the canonical string stored on an [AlertRecord] via
/// [WeatherSeverity.tryParse] before calling this.
Color alertSeverityColor(WeatherSeverity severity) => switch (severity) {
      WeatherSeverity.none || WeatherSeverity.minor => Colors.green.shade600,
      WeatherSeverity.moderate => Colors.amber.shade800,
      WeatherSeverity.high => Colors.deepOrange.shade600,
      WeatherSeverity.severe => Colors.red.shade700,
    };