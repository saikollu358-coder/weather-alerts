import 'package:flutter/material.dart';

/// Visual tokens for the premium dark weather dashboard.
///
/// Purely presentational: nothing here influences data fetching, analysis or
/// alerting. Severity and risk colors deliberately stay in the domain layer
/// (see `alertSeverityColor` and `RiskLevel`) so one palette drives the engine
/// and the UI — these tokens only cover surfaces, accents and text.
abstract final class WeatherPalette {
  WeatherPalette._();

  // ---------------------------------------------------------------------
  // Surfaces (dark navy)
  // ---------------------------------------------------------------------

  /// Page background, deepest layer.
  static const Color canvas = Color(0xFF060A14);

  /// Slightly raised background used behind cards and rails.
  static const Color canvasElevated = Color(0xFF0A1120);

  /// Default card fill.
  static const Color surface = Color(0xFF101A2D);

  /// Raised card fill (hover, selected states).
  static const Color surfaceRaised = Color(0xFF16223A);

  /// Translucent fill for glass surfaces.
  static const Color glassFill = Color(0x14A9C6FF);

  /// Translucent fill for interactive glass surfaces.
  static const Color glassFillStrong = Color(0x1FA9C6FF);

  /// Hairline border on cards.
  static const Color border = Color(0xFF1E2B47);

  /// Emphasised border, used for selected/active items.
  static const Color borderStrong = Color(0xFF2E4269);

  // ---------------------------------------------------------------------
  // Accents
  // ---------------------------------------------------------------------

  /// Primary cyan accent.
  static const Color cyan = Color(0xFF38BDF8);

  /// Deeper blue accent for gradients.
  static const Color blue = Color(0xFF4C8DFF);

  /// Teal accent used for precipitation and "safe" highlights.
  static const Color teal = Color(0xFF2DD4BF);

  /// Low-risk / all-clear color.
  static const Color safe = Color(0xFF22C55E);

  /// Warning ramp, mirrored from the domain risk levels.
  static const Color caution = Color(0xFFF59E0B);
  static const Color cautionHigh = Color(0xFFF97316);
  static const Color danger = Color(0xFFEF4444);

  // ---------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------

  static const Color textPrimary = Color(0xFFE9F0FB);
  static const Color textSecondary = Color(0xFF9DB0CE);
  static const Color textMuted = Color(0xFF6C809F);

  // ---------------------------------------------------------------------
  // Shape
  // ---------------------------------------------------------------------

  /// Large hero / feature surfaces.
  static const double radiusHero = 24;

  /// Standard cards.
  static const double radiusCard = 20;

  /// Small controls and chips.
  static const double radiusControl = 14;

  /// Pill shapes.
  static const double radiusPill = 999;

  // ---------------------------------------------------------------------
  // Elevation
  // ---------------------------------------------------------------------

  /// Soft ambient shadow so cards lift off the navy canvas without hard edges.
  static List<BoxShadow> get cardShadow => const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ];

  /// Cyan glow, used sparingly on the single most important surface only.
  static List<BoxShadow> glow(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.28),
          blurRadius: 28,
          spreadRadius: -6,
        ),
      ];

  /// Vertical accent gradient for the hero banner.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF16294D), Color(0xFF0D1730), Color(0xFF0A1120)],
  );

  /// Page-level gradient behind the dashboard.
  static const LinearGradient canvasGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A1428), Color(0xFF060A14)],
  );

  /// Fill for the sidebar / header glass rails.
  static const LinearGradient railGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xF20A1120), Color(0xF2060A14)],
  );
}