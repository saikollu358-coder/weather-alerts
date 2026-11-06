import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/weather_palette.dart';

/// Rounded, softly lit surface used across the dashboard.
///
/// This is presentation only: it wraps whatever [child] it is given and never
/// reaches into application state. Blur is opt-in because a [BackdropFilter]
/// per card is expensive on low-end devices and inside long scrolling lists —
/// the default (translucent fill + hairline border + soft shadow) reads the
/// same at these opacities.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = WeatherPalette.radiusCard,
    this.fill,
    this.borderColor,
    this.blur = false,
    this.elevated = true,
    this.gradient,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  /// Overrides the default translucent fill.
  final Color? fill;

  /// Overrides the default hairline border.
  final Color? borderColor;

  /// Adds a real backdrop blur. Use on at most one or two surfaces per screen.
  final bool blur;

  /// Whether to paint the ambient shadow.
  final bool elevated;

  /// Optional fill gradient (used by the location hero).
  final Gradient? gradient;

  /// Optional tap affordance; adds a subtle scale response.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radiusShape = BorderRadius.circular(radius);
    final background = gradient == null
        ? (fill ?? WeatherPalette.glassFill)
        : null;

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        gradient: gradient,
        borderRadius: radiusShape,
        border: Border.all(color: borderColor ?? WeatherPalette.border),
        boxShadow: elevated ? WeatherPalette.cardShadow : null,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );

    if (blur) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: surface,
      );
    }

    if (onTap != null) {
      surface = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radiusShape,
          splashColor: WeatherPalette.cyan.withValues(alpha: 0.10),
          highlightColor: WeatherPalette.cyan.withValues(alpha: 0.06),
          child: surface,
        ),
      );
    }

    if (margin != null) {
      surface = Padding(padding: margin!, child: surface);
    }
    return surface;
  }
}

/// Section title with an optional trailing action, used on every card header.
class DashboardSectionHeader extends StatelessWidget {
  const DashboardSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: WeatherPalette.cyan),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: WeatherPalette.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Small pill used for severity, status and metadata.
class DashboardPill extends StatelessWidget {
  const DashboardPill({
    super.key,
    required this.label,
    this.color = WeatherPalette.cyan,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: filled ? 0.18 : 0.09),
        borderRadius: BorderRadius.circular(WeatherPalette.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          // Pills sit in a Wrap with the card's width as their cap, so the label
          // stays flexible and wraps onto a second line rather than
          // pushing past the card edge. Labels are never truncated.
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label + value pair used inside metric grids and summary cards.
class DashboardMetric extends StatelessWidget {
  const DashboardMetric({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent,
    this.valueStyle,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Optional accent for the icon; the value text stays high-contrast.
  final Color? accent;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: accent ?? WeatherPalette.textMuted),
              const SizedBox(width: 5),
            ],
            // Metrics sit in narrow columns, so the caption yields width to the
            // icon and ellipsizes rather than overflowing the tile.
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: WeatherPalette.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: valueStyle ??
              theme.textTheme.titleSmall?.copyWith(
                color: WeatherPalette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}