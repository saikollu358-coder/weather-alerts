import 'package:flutter/material.dart';

import 'weather_palette.dart';

/// Central theme definitions for the application.
///
/// Safety-first visual language: clear information hierarchy, accessible
/// contrast, Material 3. Severity-level colors are intentionally NOT defined
/// here — they are part of the domain model (see domain/entities) so the same
/// palette drives the analysis engine, alerts and UI consistently, and so
/// severity is never communicated through color alone.
///
/// The dashboard renders on the dark navy scheme from [WeatherPalette]; the
/// light scheme keeps the same hierarchy so text-only contrast stays
/// acceptable on either.
abstract final class AppTheme {
  AppTheme._();

  /// Seed for the brand color. Cyan accent over a navy canvas.
  static const Color seedColor = Color(0xFF38BDF8);

  /// Semantic accent used for the "safety" surface in the dashboard.
  static const Color safetyGreen = WeatherPalette.safe;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  /// Page background for the dashboard shell, painted by the theme so screens
  /// do not each have to set their own scaffold color.
  static Color canvasFor(Brightness brightness) =>
      brightness == Brightness.dark ? WeatherPalette.canvas : const Color(0xFFF4F7FC);

  static ThemeData _build(Brightness brightness) {
    final scheme = _schemeFor(brightness);

    final textTheme = _textThemeFor(scheme, brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      textTheme: textTheme,
      scaffoldBackgroundColor: canvasFor(brightness),
      canvasColor: canvasFor(brightness),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: brightness == Brightness.dark
            ? WeatherPalette.canvasElevated
            : scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: brightness == Brightness.dark
            ? WeatherPalette.surface
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeatherPalette.radiusCard),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        space: 1,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: WeatherPalette.surfaceRaised,
        side: BorderSide(color: WeatherPalette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeatherPalette.radiusPill),
        ),
        labelStyle: textTheme.labelSmall,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: WeatherPalette.canvasElevated,
        surfaceTintColor: Colors.transparent,
        indicatorColor: WeatherPalette.cyan.withValues(alpha: 0.16),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? WeatherPalette.cyan
                : WeatherPalette.textMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? WeatherPalette.cyan
                : WeatherPalette.textMuted,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WeatherPalette.radiusControl),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          side: const BorderSide(color: WeatherPalette.borderStrong),
          foregroundColor: WeatherPalette.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WeatherPalette.radiusControl),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WeatherPalette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WeatherPalette.radiusControl),
          borderSide: const BorderSide(color: WeatherPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WeatherPalette.radiusControl),
          borderSide: const BorderSide(color: WeatherPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WeatherPalette.radiusControl),
          borderSide: const BorderSide(color: WeatherPalette.cyan, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: WeatherPalette.surfaceRaised,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeatherPalette.radiusControl),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: WeatherPalette.surfaceRaised,
          borderRadius: BorderRadius.circular(WeatherPalette.radiusControl),
          border: Border.all(color: WeatherPalette.border),
        ),
        textStyle: textTheme.bodySmall,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: WeatherPalette.cyan,
        linearTrackColor: WeatherPalette.surfaceRaised,
        circularTrackColor: WeatherPalette.surfaceRaised,
      ),
    );
  }

  static ColorScheme _schemeFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      ).copyWith(surface: const Color(0xFFF4F7FC));
    }

    // Dark: built from the seed, then overridden so the navy canvas, cyan
    // accent and text ramp are exactly the design tokens.
    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).copyWith(
      primary: WeatherPalette.cyan,
      onPrimary: const Color(0xFF04202E),
      secondary: WeatherPalette.blue,
      onSecondary: Colors.white,
      tertiary: WeatherPalette.teal,
      error: WeatherPalette.danger,
      onError: Colors.white,
      surface: WeatherPalette.canvas,
      onSurface: WeatherPalette.textPrimary,
      surfaceContainerLowest: WeatherPalette.canvas,
      surfaceContainerLow: WeatherPalette.canvasElevated,
      surfaceContainer: WeatherPalette.surface,
      surfaceContainerHigh: WeatherPalette.surfaceRaised,
      surfaceContainerHighest: WeatherPalette.surfaceRaised,
      onSurfaceVariant: WeatherPalette.textSecondary,
      outline: WeatherPalette.borderStrong,
      outlineVariant: WeatherPalette.border,
    );
  }

  /// Slightly tightened type ramp: a premium dashboard leans on a small number
  /// of confident sizes rather than the default body scale.
  static TextTheme _textThemeFor(ColorScheme scheme, Brightness brightness) {
    final base = Typography.material2021(
      colorScheme: scheme,
    ).englishLike.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );

    return base.copyWith(
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.w300,
        letterSpacing: -2,
        height: 1.05,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w400,
        letterSpacing: -1,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
      bodySmall: base.bodySmall?.copyWith(
        height: 1.4,
        color: brightness == Brightness.dark
            ? WeatherPalette.textSecondary
            : scheme.onSurfaceVariant,
      ),
    );
  }
}