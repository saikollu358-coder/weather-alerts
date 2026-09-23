import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/weather/daily_forecast.dart';
import '../../../domain/entities/weather/hourly_forecast.dart';
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

/// Home tab of the Phase 7 dashboard: the weather-risk assessment pipeline.
///
/// Renders location -> weather -> forecast -> analysis -> risk for the
/// selected location, with the mandatory "Last updated:" timestamp and stale
/// indicator, plus the add-location permission flow when no location exists.
class DashboardHomeTab extends ConsumerWidget {
  const DashboardHomeTab({
    super.key,
    this.onOpenLocations,
    this.onOpenAlerts,
  });

  final VoidCallback? onOpenLocations;
  final VoidCallback? onOpenAlerts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardControllerProvider);
    final locationState = ref.watch(locationControllerProvider);
    final hasContent =
        dashboard.bundle != null && dashboard.analysis != null;

    Future<void> addCurrent() =>
        ref.read(dashboardControllerProvider.notifier).useCurrentGps();
    Future<void> requestPermission() => ref
        .read(dashboardControllerProvider.notifier)
        .requestPermissionAndUseGps();
    Future<void> openSettings() =>
        ref.read(dashboardControllerProvider.notifier).openSettings();
    void retry() => ref.read(dashboardControllerProvider.notifier).retry();
    Future<void> refresh() =>
        ref.read(dashboardControllerProvider.notifier).refresh();

    if (!hasContent) {
      switch (dashboard.status) {
        case DashboardStatus.bootstrapping:
        case DashboardStatus.loading:
          return _LoadingView(label: dashboard.location?.name);
        case DashboardStatus.needsLocation:
          return _NeedsLocationPanel(
            locationState: locationState,
            onAddCurrent: addCurrent,
            onRequestPermission: requestPermission,
            onOpenSettings: openSettings,
            onOpenLocations: onOpenLocations,
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
      refreshing: dashboard.status == DashboardStatus.loading,
      errorMessage: dashboard.status == DashboardStatus.error
          ? dashboard.errorMessage
          : null,
      onRefresh: refresh,
      onOpenLocations: onOpenLocations,
      onOpenAlerts: onOpenAlerts,
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
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            label == null ? 'Loading weather risk…' : 'Loading $label…',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeedsLocationPanel extends StatelessWidget {
  const _NeedsLocationPanel({
    required this.locationState,
    required this.onAddCurrent,
    required this.onRequestPermission,
    required this.onOpenSettings,
    this.onOpenLocations,
  });

  final LocationState locationState;
  final VoidCallback onAddCurrent;
  final VoidCallback onRequestPermission;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenLocations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_location_alt_outlined,
                size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text('Add a location to start',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Weather risk assessment needs a place to monitor. You can use '
              'your current GPS position or a saved location.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            ..._permissionControls(theme),
            const SizedBox(height: 8),
            if (onOpenLocations != null)
              TextButton(
                onPressed: onOpenLocations,
                child: const Text('Choose from saved locations'),
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
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ];
      case LocationStatus.error:
        return [
          Text(
            locationState.errorMessage ?? 'Location services are unavailable.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ];
      case LocationStatus.unknown:
      case LocationStatus.ready:
        return [
          FilledButton.icon(
            key: const ValueKey('use_current_location_button'),
            onPressed: onAddCurrent,
            icon: const Icon(Icons.my_location),
            label: const Text('Use my current GPS location'),
          ),
        ];
    }
  }
}

// ---------------------------------------------------------------------
// The live pipeline view
// ---------------------------------------------------------------------

class _PipelineView extends StatelessWidget {
  const _PipelineView({
    required this.dashboard,
    required this.refreshing,
    required this.onRefresh,
    this.errorMessage,
    this.onOpenLocations,
    this.onOpenAlerts,
  });

  final DashboardState dashboard;
  final bool refreshing;
  final Future<void> Function() onRefresh;
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
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (location != null)
                  _LocationCard(location: location, onOpenLocations: onOpenLocations),
                const SizedBox(height: 8),
                _LastUpdatedBar(
                  fetchedAtUtc: bundle.fetchedAtUtc,
                  isStale: dashboard.isStale,
                  dataSource: bundle.dataSource,
                  refreshing: refreshing,
                  onRefresh: onRefresh,
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  _ErrorBanner(message: errorMessage!),
                ],
                const SizedBox(height: 8),
                const NotificationPermissionBanner(),
                const SizedBox(height: 8),
                _RiskBanner(analysis: analysis, activeCount: analysis.actionableFindings.length),
                const SizedBox(height: 12),
                _FindingsSection(findings: analysis.actionableFindings),
                const SizedBox(height: 12),
                _CurrentConditions(current: bundle.current),
                const SizedBox(height: 12),
                _HourlySection(hourly: bundle.hourly),
                const SizedBox(height: 12),
                _DailySection(daily: bundle.daily, onOpenAlerts: onOpenAlerts),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location, this.onOpenLocations});

  final dynamic location;
  final VoidCallback? onOpenLocations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.place_outlined),
        title: Text(location.name, style: theme.textTheme.titleMedium),
        subtitle: Text(
          '${location.latitude.toStringAsFixed(4)}, '
          '${location.longitude.toStringAsFixed(4)}',
        ),
        trailing: onOpenLocations == null
            ? null
            : OutlinedButton(
                onPressed: onOpenLocations,
                child: const Text('Change'),
              ),
      ),
    );
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
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(Icons.schedule, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Last updated: ${DateFormat('MMM d, yyyy HH:mm').format(fetchedAtUtc)} UTC '
            '($dataSource)',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (isStale)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: 'This data is older than its freshness window.',
              child: Chip(
                key: const ValueKey('stale_chip'),
                avatar: Icon(Icons.hourglass_disabled,
                    size: 16, color: scheme.error),
                label: Text(
                  'Data is stale',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.error),
                ),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
              ),
            ),
          ),
        IconButton(
          key: const ValueKey('refresh_button'),
          onPressed: refreshing ? null : onRefresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh weather',
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.onErrorContainer),
      ),
    );
  }
}

class _RiskBanner extends StatelessWidget {
  const _RiskBanner({required this.analysis, required this.activeCount});

  final WeatherAnalysis analysis;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _riskColor(analysis.riskLevel);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: color),
              const SizedBox(width: 8),
              Text(
                riskLabel(analysis.riskLevel),
                style: theme.textTheme.titleLarge?.copyWith(color: color),
              ),
              const Spacer(),
              Text(
                severityLabel(analysis.overallSeverity),
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            activeCount == 0
                ? 'No hazardous weather conditions detected.'
                : '$activeCount hazard${activeCount == 1 ? '' : 's'} active for '
                    'this location.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            AppConstants.assessmentDisclaimer,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FindingsSection extends StatelessWidget {
  const _FindingsSection({required this.findings});

  final List<HazardFinding> findings;

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hazards', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final finding in findings)
              Tooltip(
                message: finding.reason,
                child: Chip(
                  avatar: Icon(
                    Icons.circle,
                    size: 12,
                    color: alertSeverityColor(finding.severity),
                  ),
                  label: Text(
                      '${severityLabel(finding.severity)} '
                      '${hazardLabel(finding.hazard)}'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CurrentConditions extends StatelessWidget {
  const _CurrentConditions({required this.current});

  final CurrentWeather current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutation = [
      _Metric('Feels like', '${current.apparentTemperatureC.toStringAsFixed(0)}°C'),
      if (current.humidityPercent != null)
        _Metric('Humidity', '${current.humidityPercent!.round()}%'),
      _Metric('Wind', '${current.windSpeedKmh.round()} km/h'),
      if (current.windGustsKmh != null)
        _Metric('Gusts', '${current.windGustsKmh!.round()} km/h'),
      _Metric('Precipitation', '${current.precipitationMm.toStringAsFixed(1)} mm'),
      _Metric('Condition', _wmoConditionLabel(current.weatherCode)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Now', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(_wmoConditionIcon(current.weatherCode),
                    size: 40, color: scheme.primary),
                const SizedBox(width: 12),
                Text(
                  '${current.temperatureC.toStringAsFixed(1)}°C',
                  style: theme.textTheme.displaySmall,
                ),
                const Spacer(),
                Icon(current.isDay ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final metric in mutation)
                  _MetricChip(label: metric.label, value: metric.value),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final String value;
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        SizedBox(
          width: 96,
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _HourlySection extends StatelessWidget {
  const _HourlySection({required this.hourly});

  final List<HourlyForecastPoint> hourly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = hourly.take(12).toList();
    if (points.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Next hours', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: points.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    _HourlyCell(point: points[index]),
              ),
            ),
          ],
        ),
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
    return Container(
      width: 72,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${point.timeUtc.hour.toString().padLeft(2, '0')}:00',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Icon(_wmoConditionIcon(point.weatherCode),
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text('${point.temperatureC.round()}°',
              style: theme.textTheme.bodyMedium),
          if (probability != null)
            Text(
              '$probability%',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
        ],
      ),
    );
  }
}

class _DailySection extends StatelessWidget {
  const _DailySection({required this.daily, this.onOpenAlerts});

  final List<DailyForecastPoint> daily;
  final VoidCallback? onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = daily.take(7).toList();
    if (days.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weekly', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final day in days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        DateFormat('EEE, MMM d').format(day.dateUtc),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Icon(_wmoConditionIcon(day.weatherCode),
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant),
                    const Spacer(),
                    Text(
                      '${day.temperatureMinC.round()}° / '
                      '${day.temperatureMaxC.round()}°',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 72,
                      child: Text(
                        '${day.precipitationSumMm.toStringAsFixed(0)} mm',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Presentation helpers
// ---------------------------------------------------------------------

Color _riskColor(RiskLevel level) => switch (level) {
      RiskLevel.low => Colors.green.shade600,
      RiskLevel.moderate => Colors.amber.shade800,
      RiskLevel.high => Colors.deepOrange.shade600,
      RiskLevel.critical => Colors.red.shade700,
    };

String _wmoConditionLabel(int code) {
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

IconData _wmoConditionIcon(int code) {
  if (code == 0 || code == 1) return Icons.wb_sunny_outlined;
  if (code == 2) return Icons.wb_cloudy_outlined;
  if (code == 3) return Icons.cloud_outlined;
  if (code == 45 || code == 48) return Icons.cloud_outlined;
  if (code >= 51 && code <= 57) return Icons.water_drop_outlined;
  if (code >= 61 && code <= 67) return Icons.umbrella_outlined;
  if (code >= 71 && code <= 77) return Icons.ac_unit_outlined;
  if (code >= 80 && code <= 82) return Icons.umbrella_outlined;
  if (code == 85 || code == 86) return Icons.ac_unit_outlined;
  if (code >= 95) return Icons.thunderstorm_outlined;
  return Icons.cloud_outlined;
}