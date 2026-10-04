import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/alert_record.dart';
import '../../../services/weather_analysis/weather_severity.dart';
import '../application/alerts_controller.dart';
import '../application/alerts_providers.dart';
import '../application/alerts_state.dart';
import 'alert_severity_colors.dart';

/// Alerts tab of the dashboard shell: the alerts that are active right now,
/// backed by [alertsControllerProvider].
class AlertsTab extends ConsumerWidget {
  const AlertsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(alertsControllerProvider);
    final notifier = ref.read(alertsControllerProvider.notifier);

    return Column(
      children: [
        _AlertSummaryBar(activeCount: state.active.length),
        Expanded(child: _buildBody(context, theme, state, notifier)),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    AlertsState state,
    AlertsController notifier,
  ) {
    switch (state.status) {
      case AlertsStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case AlertsStatus.error:
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
                  state.errorMessage ?? 'Something went wrong.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: notifier.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      case AlertsStatus.ready:
        final records = state.active;
        if (records.isEmpty) {
          return const _EmptyAlerts(
            icon: Icons.notifications_active_outlined,
            message: 'No active alerts. We will warn you here when hazardous '
                'weather reaches your current location.',
          );
        }
        return RefreshIndicator(
          onRefresh: notifier.refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _ActiveAlertCard(
              record: records[index],
              onAcknowledge: () =>
                  notifier.acknowledge(records[index].fingerprint),
            ),
          ),
        );
    }
  }
}

class _AlertSummaryBar extends StatelessWidget {
  const _AlertSummaryBar({required this.activeCount});

  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                activeCount == 0
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                size: 20,
                color: activeCount == 0 ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                activeCount == 0
                    ? 'No active alerts'
                    : '$activeCount active alert${activeCount == 1 ? '' : 's'}',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppConstants.assessmentDisclaimer,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ActiveAlertCard extends StatelessWidget {
  const _ActiveAlertCard({required this.record, required this.onAcknowledge});

  final AlertRecord record;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severity = WeatherSeverity.tryParse(record.severity);
    final color = alertSeverityColor(severity ?? WeatherSeverity.none);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(Icons.warning_amber_rounded,
                  color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    record.reason,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Detected ${DateFormat('MMM d, HH:mm').format(record.detectedAtUtc.toLocal())}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!record.acknowledged)
              TextButton(
                onPressed: onAcknowledge,
                child: const Text('Acknowledge'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}