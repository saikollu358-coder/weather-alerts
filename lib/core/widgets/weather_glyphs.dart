import 'package:flutter/material.dart';

/// Shared WMO weather-code presentation.
///
/// Display concern only: classification of a code into a *risk* stays in the
/// analysis engine. Both the dashboard and the alerts surfaces use these so the
/// same condition never renders under two different names or icons.

/// Human label for a WMO weather code, e.g. `Clear`, `Freezing rain`.
String weatherConditionLabel(int code) {
  if (code == 0 || code == 1) return 'Clear';
  if (code == 2) return 'Partly cloudy';
  if (code == 3) return 'Overcast';
  if (code == 45 || code == 48) return code == 48 ? 'Rime fog' : 'Fog';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if (code >= 61 && code <= 67) return code >= 66 ? 'Freezing rain' : 'Rain';
  if (code >= 71 && code <= 77) return 'Snow';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code == 85 || code == 86) return 'Snow showers';
  if (code >= 95) return code >= 96 ? 'Thunderstorm & hail' : 'Thunderstorm';
  return 'Unknown';
}

/// Icon for a WMO weather code.
IconData weatherConditionIcon(int code) {
  if (code == 0 || code == 1) return Icons.wb_sunny_rounded;
  if (code == 2) return Icons.wb_cloudy_rounded;
  if (code == 3) return Icons.cloud_rounded;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 51 && code <= 57) return Icons.grain_rounded;
  if (code >= 61 && code <= 67) return Icons.water_drop_rounded;
  if (code >= 71 && code <= 77) return Icons.ac_unit_rounded;
  if (code >= 80 && code <= 82) return Icons.umbrella_rounded;
  if (code == 85 || code == 86) return Icons.ac_unit_rounded;
  if (code >= 95) return Icons.thunderstorm_rounded;
  return Icons.cloud_rounded;
}

/// Accent color for a weather icon: cool tones for benign conditions, warmer
/// tones for the ones worth looking at. Purely decorative — every surface also
/// states the condition as text.
Color weatherAccentFor(int code) {
  if (code == 0 || code == 1) return const Color(0xFFFBBF24);
  if (code == 2 || code == 3) return const Color(0xFF7DD3FC);
  if (code == 45 || code == 48) return const Color(0xFF94A3B8);
  if (code >= 51 && code <= 67) return const Color(0xFF38BDF8);
  if (code >= 71 && code <= 86) return const Color(0xFFA5F3FC);
  if (code >= 95) return const Color(0xFFFB923C);
  return const Color(0xFF7DD3FC);
}