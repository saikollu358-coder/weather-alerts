import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/weather_palette.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/weather_glyphs.dart';
import '../../../domain/entities/current_location.dart';
import '../../../domain/entities/weather/daily_forecast.dart';
import '../../../domain/entities/weather/hourly_forecast.dart';
import '../../../domain/entities/weather/weather_bundle.dart';
import '../../../domain/entities/weather/weather_snapshot.dart';
import '../../../services/weather_analysis/risk_level.dart';
import '../../../services/weather_analysis/weather_analysis.dart';
import '../../alerts/application/alert_text.dart';
import '../../alerts/presentation/alert_severity_colors.dart';
import '../../location/application/location_providers.dart';
import '../../location/application/location_state.dart';
import '../../notifications/presentation/notification_permission_banner.dart';
import '../application/dashboard_providers.dart';
import '../application/dashboard_state.dart';

/// Anchors the dashboard can scroll to, so the shell's navigation can jump to
/// the section that already exists on this page instead of inventing routes.
enum DashboardSection { hourly, daily }

/// Home tab of the dashboard: the weather-risk assessment for wherever the
/// device currently is.
///
/// Renders position -> weather -> forecast -> analysis -> risk, with the
/// mandatory "Last updated:" timestamp and stale indicator. There is no
/// location picker: the app asks for permission once and then follows the GPS.
///
/// Layout is responsive: a two-column dashboard with a summary rail on wide
/// viewports, a single scrolling column on narrow ones.
class DashboardHomeTab extends ConsumerStatefulWidget {
  const DashboardHomeTab({
    super.key,
    this.onOpenLocations,
    this.onOpenAlerts,
  });

  final VoidCallback? onOpenLocations;
  final VoidCallback? onOpenAlerts;

  @override
  ConsumerState<DashboardHomeTab> createState() => DashboardHomeTabState();
}

class DashboardHomeTabState extends ConsumerState<DashboardHomeTab> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _hourlyKey = GlobalKey();
  final GlobalKey _dailyKey = GlobalKey();

  bool _permissionRequested = false;

  /// Scrolls an existing section into view. Used by the shell's section links.
  void scrollToSection(DashboardSection section) {
    final target = switch (section) {
      DashboardSection.hourly => _hourlyKey,
      DashboardSection.daily => _dailyKey,
    };
    final context = target.currentContext;
    if (context == null) {
      _scrollController.animateTo(
        0,
        duration: AppMotion.standard,
        curve: AppMotion.enter,
      );
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: AppMotion.relaxed,
      curve: AppMotion.enter,
      alignment: 0.04,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardControllerProvider);
    final locationState = ref.watch(locationControllerProvider);
    final hasContent =
        dashboard.bundle != null && dashboard.analysis != null;

    // Ask for location permission as soon as the app is open without a fix.
    // There is nothing else to configure first, so this happens once per
    // session.
    if (!_permissionRequested &&
        dashboard.status == DashboardStatus.needsLocation &&
        locationState.status == LocationStatus.unknown) {
      _permissionRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(dashboardControllerProvider.notifier).requestPermission();
      });
    }

    final controller = ref.read(dashboardControllerProvider.notifier);
    Future<void> requestPermission() => controller.requestPermission();
    void openSettings() => controller.openSettings();
    void retry() => controller.retry();
    Future<void> refresh() => controller.refresh();

    if (!hasContent) {
      switch (dashboard.status) {
        case DashboardStatus.bootstrapping:
        case DashboardStatus.loading:
          return _LoadingView(label: dashboard.location?.label);
        case DashboardStatus.needsLocation:
          return _NeedsLocationPanel(
            locationState: locationState,
            onRequestPermission: requestPermission,
            onOpenSettings: openSettings,
          );
        case DashboardStatus.error:
          return _ErrorView(
            message: dashboard.errorMessage ?? 'Something went wrong.',
            onRetry: retry,
          );
        case DashboardStatus.ready:
          return const _LoadingView(label: null);
      }
    }

    return _PipelineView(
      dashboard: dashboard,
      scrollController: _scrollController,
      refreshing: dashboard.status == DashboardStatus.loading,
      errorMessage: dashboard.status == DashboardStatus.error
          ? dashboard.errorMessage
          : null,
      onRefresh: refresh,
      onOpenLocations: widget.onOpenLocations,
      onOpenAlerts: widget.onOpenAlerts,
      hourlyKey: _hourlyKey,
      dailyKey: _dailyKey,
    );
  }
}

// ---------------------------------------------------------------------
// Non-pipeline states
// ---------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _BreathingProgressIndicator(),
          const SizedBox(height: 16),
          AnimatedEntrance(
            beginScale: 0.96,
            child: Text(
              label == null ? 'Loading weather risk…' : 'Loading $label…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: WeatherPalette.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loader whose halo settles on the final frame instead of looping.
///
/// A permanently repeating animation would keep the frame pipeline busy for
/// no reason once the real content arrives, so this grows a ring once and
/// stops.
class _BreathingProgressIndicator extends StatefulWidget {
  const _BreathingProgressIndicator();

  @override
  State<_BreathingProgressIndicator> createState() =>
      _BreathingProgressIndicatorState();
}

class _BreathingProgressIndicatorState
    extends State<_BreathingProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.relaxed,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const CircularProgressIndicator(color: WeatherPalette.cyan),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedEntrance(
                beginScale: 0.9,
                child: Icon(Icons.error_outline,
                    size: 48, color: WeatherPalette.danger),
              ),
              const SizedBox(height: 12),
              AnimatedEntrance(
                delay: AppMotion.staggerFor(1),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              AnimatedEntrance(
                delay: AppMotion.staggerFor(2),
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeedsLocationPanel extends StatelessWidget {
  const _NeedsLocationPanel({
    required this.locationState,
    required this.onRequestPermission,
    required this.onOpenSettings,
  });

  final LocationState locationState;
  final Future<void> Function() onRequestPermission;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedEntrance(
              beginScale: 0.88,
              child: _PulsingLocationGlyph(color: WeatherPalette.cyan),
            ),
            const SizedBox(height: 16),
            AnimatedEntrance(
              delay: AppMotion.staggerFor(1),
              child: Text('Turn on location',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            AnimatedEntrance(
              delay: AppMotion.staggerFor(2),
              child: Text(
                'Weather alerts are based on where you are right now. Allow '
                'location access and this app will follow you automatically.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: WeatherPalette.textSecondary),
              ),
            ),
            const SizedBox(height: 24),
            AnimatedEntrance(
              delay: AppMotion.staggerFor(3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _permissionControls(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _permissionControls(ThemeData theme) {
    switch (locationState.status) {
      case LocationStatus.waitingPermission:
      case LocationStatus.denied:
        return [
          FilledButton.icon(
            key: const ValueKey('allow_location_button'),
            onPressed: onRequestPermission,
            icon: const Icon(Icons.pin_drop_outlined),
            label: const Text('Allow location access'),
          ),
        ];
      case LocationStatus.deniedForever:
        return [
          Text(
            'Location permission was denied permanently. Allow it in system '
            'Settings to use your current position.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: WeatherPalette.textSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('open_settings_button'),
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open Settings'),
          ),
        ];
      case LocationStatus.unavailable:
        return [
          Text(
            'Location services are turned off. Turn them on to use your '
            'current position.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: WeatherPalette.textSecondary),
          ),
        ];
      case LocationStatus.error:
        return [
          Text(
            locationState.errorMessage ?? 'Location services are unavailable.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: WeatherPalette.danger),
          ),
        ];
      case LocationStatus.ready:
      case LocationStatus.unknown:
        return [
          FilledButton.icon(
            key: const ValueKey('use_current_location_button'),
            onPressed: onRequestPermission,
            icon: const Icon(Icons.my_location),
            label: const Text('Use my current location'),
          ),
        ];
    }
  }
}

/// Location glyph with a one-shot halo that expands and fades on arrival.
///
/// Deliberately not a repeating pulse: a looping tween would keep the frame
/// pipeline alive for the whole time this panel is on screen.
class _PulsingLocationGlyph extends StatefulWidget {
  const _PulsingLocationGlyph({required this.color});

  final Color color;

  @override
  State<_PulsingLocationGlyph> createState() => _PulsingLocationGlyphState();
}

class _PulsingLocationGlyphState extends State<_PulsingLocationGlyph>
    with SingleTickerProviderStateMixin {
  static const double _glyphSize = 56;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.relaxed,
  );

  late final CurvedAnimation _halo = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _halo.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return SizedBox(
      width: _glyphSize * 2,
      height: _glyphSize * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _halo,
            builder: (context, _) {
              if (_halo.value == 0) return const SizedBox.shrink();
              return Transform.scale(
                scale: 0.6 + 0.8 * _halo.value,
                child: Opacity(
                  opacity: (1 - _halo.value) * 0.35,
                  child: Container(
                    width: _glyphSize * 1.6,
                    height: _glyphSize * 1.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                  ),
                ),
              );
            },
          ),
          Icon(Icons.my_location, size: _glyphSize, color: color),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// The live pipeline view
// ---------------------------------------------------------------------

/// Below this width the summary rail is folded into the main column instead of
/// sitting beside it.
const double _kRailBreakpoint = 1080;

class _PipelineView extends StatelessWidget {
  const _PipelineView({
    required this.dashboard,
    required this.scrollController,
    required this.refreshing,
    required this.onRefresh,
    required this.hourlyKey,
    required this.dailyKey,
    this.errorMessage,
    this.onOpenLocations,
    this.onOpenAlerts,
  });

  final DashboardState dashboard;
  final ScrollController scrollController;
  final bool refreshing;
  final Future<void> Function() onRefresh;
  final GlobalKey hourlyKey;
  final GlobalKey dailyKey;
  final String? errorMessage;
  final VoidCallback? onOpenLocations;
  final VoidCallback? onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final bundle = dashboard.bundle!;
    final analysis = dashboard.analysis!;
    final location = dashboard.location;

    return Column(
      children: [
        if (refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => onRefresh(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final railFits = constraints.maxWidth >= _kRailBreakpoint;
                final rail = _SummaryRail(
                  bundle: bundle,
                  location: location,
                  isStale: dashboard.isStale,
                  refreshing: refreshing,
                  onRefresh: onRefresh,
                  onOpenLocations: onOpenLocations,
                );
                final main = _MainColumn(
                  dashboard: dashboard,
                  bundle: bundle,
                  analysis: analysis,
                  location: location,
                  refreshing: refreshing,
                  errorMessage: errorMessage,
                  onRefresh: onRefresh,
                  onOpenLocations: onOpenLocations,
                  onOpenAlerts: onOpenAlerts,
                  hourlyKey: hourlyKey,
                  dailyKey: dailyKey,
                );

                return railFits
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: main),
                          const SizedBox(width: 4),
                          SizedBox(width: 340, child: rail),
                        ],
                      )
                    : main;
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The scrolling dashboard column. Holds the hero, hazard card, current
/// conditions, hourly strip and the weekly list.
class _MainColumn extends StatelessWidget {
  const _MainColumn({
    required this.dashboard,
    required this.bundle,
    required this.analysis,
    required this.location,
    required this.refreshing,
    required this.errorMessage,
    required this.onRefresh,
    required this.onOpenLocations,
    required this.onOpenAlerts,
    required this.hourlyKey,
    required this.dailyKey,
  });

  final DashboardState dashboard;
  final WeatherBundle bundle;
  final WeatherAnalysis analysis;
  final CurrentLocation? location;
  final bool refreshing;
  final String? errorMessage;
  final Future<void> Function() onRefresh;
  final VoidCallback? onOpenLocations;
  final VoidCallback? onOpenAlerts;
  final GlobalKey hourlyKey;
  final GlobalKey dailyKey;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        if (location != null)
          AnimatedEntrance(
            child: _LocationHero(
              location: location!,
              fetchedAtUtc: bundle.fetchedAtUtc,
              isStale: dashboard.isStale,
              dataSource: bundle.dataSource,
              refreshing: refreshing,
              onRefresh: onRefresh,
              onOpenLocations: onOpenLocations,
            ),
          ),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          AnimatedEntrance(
            delay: AppMotion.staggerFor(1),
            child: _ErrorBanner(message: errorMessage!),
          ),
        ],
        const SizedBox(height: 12),
        const NotificationPermissionBanner(),
        AnimatedEntrance(
          delay: AppMotion.staggerFor(2),
          child: _HazardCard(
            analysis: analysis,
            activeCount: analysis.actionableFindings.length,
            onOpenAlerts: onOpenAlerts,
          ),
        ),
        const SizedBox(height: 14),
        AnimatedEntrance(
          delay: AppMotion.staggerFor(3),
          child: _CurrentConditions(current: bundle.current),
        ),
        const SizedBox(height: 14),
        AnimatedEntrance(
          delay: AppMotion.staggerFor(4),
          child: _HourlySection(
            key: hourlyKey,
            hourly: bundle.hourly,
          ),
        ),
        const SizedBox(height: 14),
        AnimatedEntrance(
          delay: AppMotion.staggerFor(5),
          child: _DailySection(
            key: dailyKey,
            daily: bundle.daily,
          ),
        ),
      ],
    );
  }
}

/// Right-hand summary panel: today's outlook plus a preview of the existing map.
class _SummaryRail extends StatelessWidget {
  const _SummaryRail({
    required this.bundle,
    required this.location,
    required this.isStale,
    required this.refreshing,
    required this.onRefresh,
    this.onOpenLocations,
  });

  final WeatherBundle bundle;

  /// The app's single current location, reused by the map preview.
  final CurrentLocation? location;
  final bool isStale;
  final bool refreshing;
  final Future<void> Function() onRefresh;
  final VoidCallback? onOpenLocations;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 16, 20, 28),
      children: [
        AnimatedEntrance(
          delay: AppMotion.staggerFor(1),
          child: _TodaySummaryCard(
            bundle: bundle,
            isStale: isStale,
            refreshing: refreshing,
            onRefresh: onRefresh,
          ),
        ),
        const SizedBox(height: 14),
        AnimatedEntrance(
          delay: AppMotion.staggerFor(2),
          child: _MapPreviewCard(
            location: location,
            onOpenLocations: onOpenLocations,
          ),
        ),
      ],
    );
  }
}

class _LocationHero extends StatelessWidget {
  const _LocationHero({
    required this.location,
    required this.fetchedAtUtc,
    required this.isStale,
    required this.dataSource,
    required this.refreshing,
    required this.onRefresh,
    this.onOpenLocations,
  });

  final CurrentLocation location;
  final DateTime fetchedAtUtc;
  final bool isStale;
  final String dataSource;
  final bool refreshing;
  final Future<void> Function() onRefresh;
  final VoidCallback? onOpenLocations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracy = location.position.accuracy;
    final coordinate =
        '${location.latitude.toStringAsFixed(3)}, '
        '${location.longitude.toStringAsFixed(3)}';

    return GlassCard(
      radius: WeatherPalette.radiusHero,
      gradient: WeatherPalette.heroGradient,
      borderColor: WeatherPalette.borderStrong,
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: WeatherPalette.cyan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: WeatherPalette.cyan.withValues(alpha: 0.30),
                  ),
                ),
                padding: const EdgeInsets.all(11),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: WeatherPalette.cyan,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: WeatherPalette.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    // [CurrentLocation.label] already falls back to the
                    // coordinate string when no place name could be resolved,
                    // so repeating it here would just print the same text twice.
                    AnimatedSwitcher(
                      duration: AppMotion.standard,
                      child: Text(
                        _heroSubtitle(location, coordinate, accuracy),
                        key: ValueKey(
                          '${location.hasResolvedName}$coordinate$accuracy',
                        ),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: WeatherPalette.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              if (onOpenLocations != null)
                IconButton(
                  icon: const Icon(Icons.map_outlined),
                  tooltip: 'Show on map',
                  color: WeatherPalette.textSecondary,
                  onPressed: onOpenLocations,
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _LastUpdatedBar(
            fetchedAtUtc: fetchedAtUtc,
            isStale: isStale,
            dataSource: dataSource,
            refreshing: refreshing,
            onRefresh: onRefresh,
          ),
        ],
      ),
    );
  }

  /// Secondary line under the place name.
  ///
  /// Always keeps the accuracy reading; only adds coordinates when the label
  /// is a real place name, so an unresolved label is not duplicated verbatim.
  static String _heroSubtitle(
    CurrentLocation location,
    String coordinate,
    double? accuracy,
  ) {
    final accuracyText = accuracy == null ? null : '±${accuracy.round()} m';
    if (!location.hasResolvedName) {
      return accuracyText ?? 'Current position';
    }
    return [
      coordinate,
      if (accuracyText != null) '· $accuracyText',
    ].join(' ');
  }
}

class _LastUpdatedBar extends StatelessWidget {
  const _LastUpdatedBar({
    required this.fetchedAtUtc,
    required this.isStale,
    required this.dataSource,
    required this.refreshing,
    required this.onRefresh,
  });

  final DateTime fetchedAtUtc;
  final bool isStale;
  final String dataSource;
  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Icon(Icons.schedule, size: 15, color: WeatherPalette.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Last updated: '
            '${DateFormat('MMM d, HH:mm').format(fetchedAtUtc.toLocal())} '
            '($dataSource)',
            maxLines: 2,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: WeatherPalette.textSecondary),
          ),
        ),
        if (isStale)
          AnimatedEntrance(
            beginScale: 0.8,
            beginOffset: const Offset(0.4, 0),
            duration: AppMotion.standard,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'This data is older than its freshness window.',
                child: DashboardPill(
                  key: const ValueKey('stale_chip'),
                  label: 'Stale',
                  color: WeatherPalette.caution,
                  icon: Icons.hourglass_disabled_rounded,
                ),
              ),
            ),
          ),
        // One bounded turn per refresh: a looping spinner here would keep the
        // frame pipeline running even after the data has landed.
        AnimatedRotation(
          turns: refreshing ? 1 : 0,
          duration: AppMotion.relaxed,
          curve: AppMotion.enter,
          child: IconButton(
            key: const ValueKey('refresh_button'),
            onPressed: refreshing ? null : () => onRefresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh weather',
            color: WeatherPalette.cyan,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: WeatherPalette.danger.withValues(alpha: 0.12),
        borderRadius:
            BorderRadius.circular(WeatherPalette.radiusControl),
        border: Border.all(color: WeatherPalette.danger.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: WeatherPalette.danger),
      ),
    );
  }
}

/// Modern hazard card: risk level, severity, hazard count and the disclaimer.
///
/// The values all come from the deterministic analysis; this only decides how
/// they are presented. The risk word is always rendered beside the color.
class _HazardCard extends StatelessWidget {
  const _HazardCard({
    required this.analysis,
    required this.activeCount,
    this.onOpenAlerts,
  });

  final WeatherAnalysis analysis;
  final int activeCount;
  final VoidCallback? onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _riskColor(analysis.riskLevel);
    final findings = analysis.actionableFindings;

    return GlassCard(
      borderColor: color.withValues(alpha: 0.38),
      fill: color.withValues(alpha: 0.09),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PopOnChange(
                identity: analysis.riskLevel,
                child: Icon(Icons.shield_rounded, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              // The label is always rendered next to the colour: risk is never
              // communicated through colour alone.
              Expanded(
                child: PopOnChange(
                  identity: analysis.riskLevel,
                  child: Text(
                    riskLabel(analysis.riskLevel),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: AppMotion.quick,
                child: DashboardPill(
                  key: ValueKey(analysis.overallSeverity),
                  label: severityLabel(analysis.overallSeverity),
                  color: color,
                  filled: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedNumber(
            value: activeCount.toDouble(),
            duration: AppMotion.standard,
            format: (value) {
              final count = value.round();
              return count == 0
                  ? 'No hazardous weather conditions detected.'
                  : '$count hazard${count == 1 ? '' : 's'} active for '
                      'this location.';
            },
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: WeatherPalette.textPrimary),
          ),
          if (findings.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Hazards',
              style: theme.textTheme.titleSmall?.copyWith(
                color: WeatherPalette.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < findings.length; i++)
                  AnimatedEntrance(
                    key: ValueKey('${findings[i].hazard.name}-'
                        '${findings[i].severity.name}'),
                    delay: AppMotion.staggerFor(i + 1),
                    beginScale: 0.9,
                    child: Tooltip(
                      message: findings[i].reason,
                      child: DashboardPill(
                        label: '${severityLabel(findings[i].severity)} '
                            '${hazardLabel(findings[i].hazard)}',
                        color: alertSeverityColor(findings[i].severity),
                        filled: true,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  size: 14, color: WeatherPalette.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppConstants.assessmentDisclaimer,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: WeatherPalette.textMuted),
                ),
              ),
            ],
          ),
          if (onOpenAlerts != null && activeCount > 0) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenAlerts,
                style: TextButton.styleFrom(
                  foregroundColor: WeatherPalette.cyan,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('View active alerts'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Premium current-conditions card.
class _CurrentConditions extends StatelessWidget {
  const _CurrentConditions({required this.current});

  final CurrentWeather current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = weatherAccentFor(current.weatherCode);
    final metrics = <Widget>[
      DashboardMetric(
        label: 'Feels like',
        value: '${current.apparentTemperatureC.toStringAsFixed(0)}°C',
        icon: Icons.thermostat_rounded,
      ),
      if (current.humidityPercent != null)
        DashboardMetric(
          label: 'Humidity',
          value: '${current.humidityPercent!.round()}%',
          icon: Icons.water_drop_outlined,
        ),
      DashboardMetric(
        label: 'Wind',
        value: '${current.windSpeedKmh.round()} km/h',
        icon: Icons.air_rounded,
      ),
      if (current.windGustsKmh != null)
        DashboardMetric(
          label: 'Gusts',
          value: '${current.windGustsKmh!.round()} km/h',
          icon: Icons.storm_rounded,
        ),
      DashboardMetric(
        label: 'Precipitation',
        value: '${current.precipitationMm.toStringAsFixed(1)} mm',
        icon: Icons.umbrella_outlined,
      ),
      DashboardMetric(
        label: 'Condition',
        value: weatherConditionLabel(current.weatherCode),
        icon: Icons.cloud_queue_rounded,
      ),
    ];

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      borderColor: accent.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: AppMotion.standard,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale:
                        Tween<double>(begin: 0.7, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: Icon(
                  weatherConditionIcon(current.weatherCode),
                  key: ValueKey(current.weatherCode),
                  size: 60,
                  color: accent,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedNumber(
                      value: current.temperatureC,
                      begin: 0,
                      format: (value) => '${value.toStringAsFixed(1)}°C',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: WeatherPalette.textPrimary,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: AppMotion.quick,
                      child: Text(
                        weatherConditionLabel(current.weatherCode),
                        key: ValueKey(current.weatherCode),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: accent),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: WeatherPalette.surfaceRaised,
                  borderRadius:
                      BorderRadius.circular(WeatherPalette.radiusPill),
                  border: Border.all(color: WeatherPalette.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      current.isDay
                          ? Icons.wb_sunny_outlined
                          : Icons.nights_stay_outlined,
                      size: 15,
                      color: current.isDay
                          ? WeatherPalette.caution
                          : WeatherPalette.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      current.isDay ? 'Daytime' : 'Night',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: WeatherPalette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              // Five metrics wrap onto one row on wide cards and two on narrow
              // ones, without a fixed column count per breakpoint.
              const spacing = 14.0;
              final columns =
                  ((constraints.maxWidth + spacing) / 132).floor().clamp(2, 5);
              final width = (constraints.maxWidth - spacing * (columns - 1)) /
                  columns;
              return Wrap(
                spacing: spacing,
                runSpacing: 14,
                children: [
                  for (var i = 0; i < metrics.length; i++)
                    AnimatedEntrance(
                      delay: AppMotion.staggerFor(i + 1),
                      beginOffset: const Offset(0, 0.25),
                      duration: AppMotion.quick,
                      child: SizedBox(width: width, child: metrics[i]),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HourlySection extends StatelessWidget {
  const _HourlySection({super.key, required this.hourly});

  final List<HourlyForecastPoint> hourly;

  @override
  Widget build(BuildContext context) {
    final points = hourly.take(24).toList();
    if (points.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DashboardSectionHeader(
            title: 'Next hours',
            icon: Icons.schedule_rounded,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: points.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => AnimatedEntrance(
                beginOffset: const Offset(0.25, 0),
                beginScale: 0.92,
                duration: AppMotion.quick,
                delay: AppMotion.staggerFor(index),
                child: _HourlyCell(point: points[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HourlyCell extends StatelessWidget {
  const _HourlyCell({required this.point});

  final HourlyForecastPoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final probability = point.precipitationProbability;
    final accent = weatherAccentFor(point.weatherCode);
    // Wetter hours get a stronger outline, so the risk gradient is legible at
    // a glance. Colour is a secondary cue; the percentage label stays visible.
    final wetness = ((probability ?? 0) / 100).clamp(0.0, 1.0);
    final borderColor = Color.lerp(
      WeatherPalette.border,
      WeatherPalette.cyan,
      wetness,
    )!;

    return Container(
      width: 88,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(WeatherPalette.radiusControl),
        color: WeatherPalette.surfaceRaised.withValues(alpha: 0.45 + 0.35 * wetness),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${point.timeUtc.toLocal().hour.toString().padLeft(2, '0')}:00',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: WeatherPalette.textSecondary),
          ),
          AnimatedSwitcher(
            duration: AppMotion.quick,
            child: Icon(
              weatherConditionIcon(point.weatherCode),
              key: ValueKey(point.weatherCode),
              size: 24,
              color: accent,
            ),
          ),
          AnimatedNumber(
            value: point.temperatureC,
            format: (value) => '${value.round()}°',
            duration: AppMotion.standard,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: WeatherPalette.textPrimary),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.air_rounded,
                  size: 11, color: WeatherPalette.textMuted),
              const SizedBox(width: 3),
              Text(
                '${point.windSpeedKmh.round()}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: WeatherPalette.textMuted, fontSize: 10.5),
              ),
            ],
          ),
          AnimatedNumber(
            value: probability?.toDouble() ?? 0,
            format: (value) => '${value.round()}%',
            duration: AppMotion.standard,
            style: theme.textTheme.labelSmall?.copyWith(
              color: probability == null
                  ? WeatherPalette.textMuted
                  : WeatherPalette.teal,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's outlook. Only values the app already stores are shown.
class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard({
    required this.bundle,
    required this.isStale,
    required this.refreshing,
    required this.onRefresh,
  });

  final WeatherBundle bundle;
  final bool isStale;
  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final today = bundle.daily.isEmpty ? null : bundle.daily.first;
    final current = bundle.current;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            title: today == null ? 'Current' : 'Today',
            icon: Icons.insights_rounded,
            trailing: AnimatedRotation(
              turns: refreshing ? 1 : 0,
              duration: AppMotion.relaxed,
              curve: AppMotion.enter,
              child: IconButton(
                onPressed: refreshing ? null : () => onRefresh(),
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh weather',
                color: WeatherPalette.textSecondary,
              ),
            ),
          ),
          if (isStale)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: DashboardPill(
                label: 'Older than its freshness window',
                color: WeatherPalette.caution,
                icon: Icons.hourglass_disabled_rounded,
              ),
            ),
          const SizedBox(height: 14),
          if (today != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(weatherConditionIcon(today.weatherCode),
                    size: 34, color: weatherAccentFor(today.weatherCode)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    weatherConditionLabel(today.weatherCode),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: WeatherPalette.textPrimary),
                  ),
                ),
                AnimatedNumber(
                  value: today.temperatureMaxC,
                  format: (value) => '${value.round()}°',
                  duration: AppMotion.standard,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: WeatherPalette.cyan,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 6),
                AnimatedNumber(
                  value: today.temperatureMinC,
                  format: (value) => '${value.round()}°',
                  duration: AppMotion.standard,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: WeatherPalette.textSecondary),
                ),
              ],
            ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 3.1,
            children: [
              DashboardMetric(
                label: 'Max',
                value: today == null
                    ? '${current.temperatureC.round()}°C'
                    : '${today.temperatureMaxC.round()}°C',
                icon: Icons.keyboard_arrow_up_rounded,
                accent: WeatherPalette.caution,
              ),
              DashboardMetric(
                label: 'Min',
                value: today == null
                    ? '${current.temperatureC.round()}°C'
                    : '${today.temperatureMinC.round()}°C',
                icon: Icons.keyboard_arrow_down_rounded,
                accent: WeatherPalette.blue,
              ),
              DashboardMetric(
                label: 'Rain',
                value: today == null
                    ? '${current.precipitationMm.toStringAsFixed(1)} mm'
                    : '${today.precipitationSumMm.toStringAsFixed(1)} mm',
                icon: Icons.umbrella_outlined,
                accent: WeatherPalette.teal,
              ),
              DashboardMetric(
                label: 'Chance of rain',
                value: (today?.precipitationProbabilityMax) == null
                    ? '—'
                    : '${today!.precipitationProbabilityMax}%',
                icon: Icons.percent_rounded,
                accent: WeatherPalette.cyan,
              ),
              DashboardMetric(
                label: 'Humidity',
                value: current.humidityPercent == null
                    ? '—'
                    : '${current.humidityPercent!.round()}%',
                icon: Icons.water_drop_outlined,
                accent: WeatherPalette.teal,
              ),
              DashboardMetric(
                label: 'Wind',
                value: '${current.windSpeedKmh.round()} km/h',
                icon: Icons.air_rounded,
                accent: WeatherPalette.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rounded preview of the current position that hands off to the app's real
/// Map tab.
///
/// It deliberately does **not** embed a second [LocationsMapView]: the map tab
/// already owns the single `flutter_map` instance (and its tile layer /
/// radar overlay), and adding another would multiply map widgets inside a
/// scrolling column. This card presents the same position data and opens the
/// existing map instead.
class _MapPreviewCard extends StatelessWidget {
  const _MapPreviewCard({required this.location, this.onOpenLocations});

  final CurrentLocation? location;
  final VoidCallback? onOpenLocations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracy = location?.position.accuracy;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      gradient: WeatherPalette.heroGradient,
      borderColor: WeatherPalette.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            title: 'Location',
            icon: Icons.map_rounded,
            trailing: onOpenLocations == null
                ? null
                : TextButton(
                    onPressed: onOpenLocations,
                    style: TextButton.styleFrom(
                      foregroundColor: WeatherPalette.cyan,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Open map'),
                  ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(
              color: WeatherPalette.glassFill,
              borderRadius:
                  BorderRadius.circular(WeatherPalette.radiusControl),
              border: Border.all(color: WeatherPalette.border),
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: WeatherPalette.cyan.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: WeatherPalette.cyan.withValues(alpha: 0.45),
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    location == null
                        ? Icons.location_off_outlined
                        : Icons.place_rounded,
                    color: location == null
                        ? WeatherPalette.textMuted
                        : WeatherPalette.cyan,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  location?.label ?? 'No position yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: WeatherPalette.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  accuracy == null
                      ? 'Waiting for a GPS fix'
                      : 'Accuracy ±${accuracy.round()} m',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: WeatherPalette.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailySection extends StatelessWidget {
  const _DailySection({super.key, required this.daily});

  final List<DailyForecastPoint> daily;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = daily.take(7).toList();
    if (days.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DashboardSectionHeader(
            title: '7-day outlook',
            icon: Icons.calendar_month_rounded,
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < days.length; i++)
            AnimatedEntrance(
              delay: AppMotion.staggerFor(i + 1),
              duration: AppMotion.quick,
              beginOffset: const Offset(0, 0.2),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        DateFormat('EEE, MMM d').format(days[i].dateUtc.toLocal()),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: WeatherPalette.textPrimary),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: AppMotion.quick,
                      child: Icon(
                        weatherConditionIcon(days[i].weatherCode),
                        key: ValueKey(days[i].weatherCode),
                        size: 20,
                        color: weatherAccentFor(days[i].weatherCode),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${days[i].temperatureMinC.round()}° / '
                      '${days[i].temperatureMaxC.round()}°',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: WeatherPalette.textPrimary),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 76,
                      child: AnimatedNumber(
                        value: days[i].precipitationSumMm,
                        format: (value) => '${value.toStringAsFixed(0)} mm',
                        duration: AppMotion.standard,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: WeatherPalette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Presentation helpers
// ---------------------------------------------------------------------

Color _riskColor(RiskLevel level) => switch (level) {
      RiskLevel.low => WeatherPalette.safe,
      RiskLevel.moderate => WeatherPalette.caution,
      RiskLevel.high => WeatherPalette.cautionHigh,
      RiskLevel.critical => WeatherPalette.danger,
    };