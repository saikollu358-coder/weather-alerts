import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/weather_palette.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../domain/entities/alert_record.dart';
import '../../../domain/entities/alert_status.dart';
import '../../../services/weather_analysis/weather_hazard.dart';
import '../../../services/weather_analysis/weather_severity.dart';
import '../application/alert_detail_providers.dart';
import '../application/alert_text.dart';
import 'alert_severity_colors.dart';

/// Detail view for a single alert, opened from a notification tap.
///
/// Reads the record by fingerprint from local history. A tap is only a
/// navigation hint: if the alert is no longer stored (already resolved and
/// aged out, or a push for an area this device does not track), the screen says
/// so plainly instead of showing a spinner or pretending the alert is current.
class AlertDetailScreen extends ConsumerWidget {
  const AlertDetailScreen({super.key, required this.fingerprint});

  /// Decoded alert fingerprint taken from the route.
  final String fingerprint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(alertDetailProvider(fingerprint));

    // Same backdrop as the dashboard shell, so opening this over a tab does not
    // swap one dark surface for a flat one.
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: WeatherPalette.canvasGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Alert details')),
        body: detail.when(
          loading: () => const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
          error: (error, _) => _DetailMessage(
            icon: Icons.error_outline,
            title: 'Could not load this alert',
            message: 'Please try again in a moment.',
            action: FilledButton.icon(
              onPressed: () => ref.invalidate(alertDetailProvider(fingerprint)),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
          data: (record) => record == null
              ? const _DetailMessage(
                  icon: Icons.history_toggle_off,
                  title: 'This alert is no longer available',
                  message: 'It has already been resolved, expired or removed '
                      'from this device. Your current risk is always shown on '
                      'the Weather and Alerts tabs.',
                )
              : _AlertDetailBody(record: record),
        ),
      ),
    );
  }
}

class _AlertDetailBody extends ConsumerWidget {
  const _AlertDetailBody({required this.record});

  final AlertRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final severity = WeatherSeverity.tryParse(record.severity);
    final hazard = WeatherHazard.tryParse(record.hazard);
    final color = alertSeverityColor(severity ?? WeatherSeverity.none);
    final value = record.payload['value'];
    final unit = record.payload['unit'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        AnimatedEntrance(
          beginScale: 0.94,
          child: _Header(
            record: record,
            color: color,
            hazardLabelText: hazard == null
                ? record.hazard
                : hazardLabel(hazard),
            severityLabelText: severity == null
                ? record.severity
                : severityLabel(severity),
          ),
        ),
        AnimatedEntrance(
          delay: AppMotion.staggerFor(1),
          child: _Section(
            title: 'Why this was flagged',
            child: Text(
              record.reason,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ),
        AnimatedEntrance(
          delay: AppMotion.staggerFor(2),
          child: _Section(
            title: 'Details',
            child: Column(
              children: [
                _DetailRow(
                  label: 'Status',
                  value: statusLabel(record.status),
                ),
                _DetailRow(label: 'Location', value: record.locationKey),
                if (value != null)
                  _DetailRow(
                    label: 'Reading',
                    value: unit == null
                        ? '$value'
                        : '$value $unit',
                  ),
                _DetailRow(
                  label: 'Detected',
                  value: _formatUtc(record.detectedAtUtc),
                ),
                _DetailRow(
                  label: 'Last updated',
                  value: _formatUtc(record.updatedAtUtc),
                ),
                if (record.acknowledged)
                  const _DetailRow(label: 'Acknowledged', value: 'Yes'),
              ],
            ),
          ),
        ),
        AnimatedEntrance(
          delay: AppMotion.staggerFor(3),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              AppConstants.assessmentDisclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        if (!record.acknowledged)
          AnimatedEntrance(
            delay: AppMotion.staggerFor(4),
            child: FilledButton.icon(
              onPressed: () =>
                  ref.read(acknowledgeAlertProvider)(record.fingerprint),
              icon: const Icon(Icons.check),
              label: const Text('Acknowledge'),
            ),
          ),
      ],
    );
  }

  static String _formatUtc(DateTime utc) =>
      DateFormat('MMM d, yyyy HH:mm').format(utc.toLocal());
}

/// Display label for an alert lifecycle state.
String statusLabel(AlertStatus status) => switch (status) {
      AlertStatus.detected => 'Detected',
      AlertStatus.active => 'Active',
      AlertStatus.escalated => 'Escalated',
      AlertStatus.resolved => 'Resolved',
      AlertStatus.expired => 'Expired',
    };

class _Header extends StatelessWidget {
  const _Header({
    required this.record,
    required this.color,
    required this.hazardLabelText,
    required this.severityLabelText,
  });

  final AlertRecord record;
  final Color color;
  final String hazardLabelText;
  final String severityLabelText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: color.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(12),
              child: Icon(Icons.warning_amber_rounded, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title.isEmpty
                        ? '$severityLabelText $hazardLabelText'
                        : record.title,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Chip(label: statusLabel(record.status), color: color),
                      _Chip(
                        label: severityLabelText,
                        color: color,
                        filled: true,
                      ),
                    ],
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.filled = false});

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: filled ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

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
              beginScale: 0.85,
              child: Icon(
                icon,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            AnimatedEntrance(
              delay: AppMotion.staggerFor(1),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedEntrance(
              delay: AppMotion.staggerFor(2),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              AnimatedEntrance(
                delay: AppMotion.staggerFor(3),
                child: action!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}