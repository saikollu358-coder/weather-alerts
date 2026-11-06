import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_motion.dart';
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
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.standard,
            switchInCurve: AppMotion.enter,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            // Keep both states full-size while they cross-fade, so the spinner
            // and the list do not jump to a different alignment mid-transition.
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              alignment: Alignment.topCenter,
              children: <Widget>[
                ...previousChildren,
                ?currentChild,
              ],
            ),
            child: KeyedSubtree(
              key: ValueKey('${state.status}-${state.errorMessage}'),
              child: _buildBody(context, theme, state, notifier),
            ),
          ),
        ),
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
        return const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        );
      case AlertsStatus.error:
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
                        size: 48, color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                  AnimatedEntrance(
                    delay: AppMotion.staggerFor(1),
                    child: Text(
                      state.errorMessage ?? 'Something went wrong.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AnimatedEntrance(
                    delay: AppMotion.staggerFor(2),
                    child: FilledButton.icon(
                      onPressed: notifier.refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ),
                ],
              ),
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
            itemBuilder: (context, index) => AnimatedEntrance(
              // Alert identities are stable (fingerprint), so an item that
              // survives a refresh is not re-animated from scratch.
              key: ValueKey(records[index].fingerprint),
              delay: AppMotion.staggerFor(index),
              beginOffset: const Offset(0, 0.06),
              beginScale: 0.96,
              child: _ActiveAlertCard(
                record: records[index],
                onAcknowledge: () =>
                    notifier.acknowledge(records[index].fingerprint),
              ),
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
    final hasAlerts = activeCount > 0;
    // Tint tracks the state so the bar itself carries the signal; the wording
    // beside it still states the situation in words.
    final background =
        hasAlerts ? scheme.errorContainer : scheme.surfaceContainerLow;
    final onBackground =
        hasAlerts ? scheme.onErrorContainer : scheme.onSurface;

    return AnimatedContainer(
      duration: AppMotion.standard,
      curve: AppMotion.enter,
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedSwitcher(
                duration: AppMotion.standard,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: Icon(
                  hasAlerts
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  key: ValueKey(hasAlerts),
                  size: 20,
                  color: hasAlerts ? scheme.error : scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              // The count is rendered as text, never as colour alone.
              PopOnChange(
                identity: activeCount,
                beginScale: 0.92,
                duration: AppMotion.standard,
                child: Text(
                  activeCount == 0
                      ? 'No active alerts'
                      : '$activeCount active alert${activeCount == 1 ? '' : 's'}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: onBackground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: AppMotion.quick,
            child: Text(
              AppConstants.assessmentDisclaimer,
              key: ValueKey(onBackground.toARGB32()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasAlerts
                    ? scheme.onErrorContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
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

    return PressableScale(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: AppMotion.standard,
                curve: AppMotion.enter,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.warning_amber_rounded,
                    color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: AppMotion.quick,
                      child: Text(
                        record.title,
                        key: ValueKey(record.title),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.reason,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    AnimatedOpacity(
                      duration: AppMotion.standard,
                      opacity: record.acknowledged ? 0.6 : 1,
                      child: Text(
                        'Detected ${DateFormat('MMM d, HH:mm').format(record.detectedAtUtc.toLocal())}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
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
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedEntrance(
                beginScale: 0.8,
                child: _AllClearGlyph(
                  icon: icon,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty-state icon inside a ring that draws itself once.
///
/// A finite, single pass: an endlessly pulsing "all clear" would compete with
/// real alerts for attention every time the list is legitimately empty.
class _AllClearGlyph extends StatelessWidget {
  const _AllClearGlyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReducedMotion(context)) {
      return Icon(icon, size: 48, color: color);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.relaxed,
      curve: AppMotion.enter,
      builder: (context, value, _) => SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (value > 0)
              Transform.scale(
                scale: value,
                child: Opacity(
                  opacity: 1 - value,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
            Transform.scale(
              scale: 0.85 + 0.15 * value,
              child: Icon(icon, size: 48, color: color),
            ),
          ],
        ),
      ),
    );
  }
}