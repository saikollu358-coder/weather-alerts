import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/alert_record.dart';
import '../../../domain/entities/alert_status.dart';
import '../../../services/weather_analysis/weather_severity.dart';
import '../application/alerts_controller.dart';
import '../application/alerts_providers.dart';
import '../application/alerts_state.dart';
import 'alert_severity_colors.dart';

/// Alerts tab of the dashboard shell: live alerts + resolved/expired history
/// backed by [alertsControllerProvider].
class AlertsTab extends ConsumerStatefulWidget {
  const AlertsTab({super.key});

  @override
  ConsumerState<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends ConsumerState<AlertsTab> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(alertsControllerProvider);
    final notifier = ref.read(alertsControllerProvider.notifier);

    return Column(
      children: [
        _AlertSummaryBar(activeCount: state.active.length, scheme: scheme),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Active'),
                  icon: Icon(Icons.notifications_active_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('History'),
                  icon: Icon(Icons.history),
                ),
              ],
              selected: {_showHistory},
              onSelectionChanged: (selection) =>
                  setState(() => _showHistory = selection.first),
            ),
          ),
        ),
        Expanded(child: _buildBody(context, state, notifier)),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AlertsState state,
    AlertsController notifier,
  ) {
    final theme = Theme.of(context);
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
        final records =
            _showHistory ? state.history : state.active;
        if (records.isEmpty) {
          return _EmptyAlerts(
            icon:
                _showHistory ? Icons.history : Icons.notifications_active_outlined,
            message: _showHistory
                ? 'No finished alerts recorded yet.'
                : 'No active alerts. Check back when weather changes.',
          );
        }
        return RefreshIndicator(
          onRefresh: notifier.refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _showHistory
                ? _HistoryAlertCard(record: records[index])
                : _ActiveAlertCard(
                    record: records[index],
                    onAcknowledge: () => notifier.acknowledge(
                      records[index].fingerprint,
                    ),
                  ),
          ),
        );
    }
  }
}

class _AlertSummaryBar extends StatelessWidget {
  const _AlertSummaryBar({required this.activeCount, required this.scheme});

  final int activeCount;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 8),
Text(
                  '$activeCount active alert${activeCount == 1 ? '' : 's'}',
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

class _HistoryAlertCard extends StatelessWidget {
  const _HistoryAlertCard({required this.record});

  final AlertRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = record.status;
    final isExpired = status == AlertStatus.expired;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            isExpired ? Icons.history : Icons.check_circle_outline,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(record.title, style: theme.textTheme.titleSmall),
        subtitle: Text(
          DateFormat('MMM d, HH:mm').format(
              (record.resolvedAtUtc ?? record.updatedAtUtc).toLocal()),
        ),
        trailing: Chip(
          label: Text(isExpired ? 'Expired' : 'Resolved'),
          visualDensity: VisualDensity.compact,
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