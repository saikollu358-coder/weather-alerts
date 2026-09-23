import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../notifications/application/notification_settings_providers.dart';
import '../../notifications/application/notification_settings_state.dart';
import '../../../domain/enums/notification_permission.dart';

/// Settings: notification preferences + permission state, and an about
/// section. Entry point is the app-bar gear button on the dashboard shell.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = settings.errorMessage;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Notifications',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              key: const ValueKey('notifications_switch'),
              title: const Text('Weather risk alerts'),
              subtitle: const Text(
                'Deliver alerts for hazards at your monitored locations. '
                '${AppConstants.assessmentDisclaimer}',
              ),
              value: settings.enabled && !settings.isLoading,
              onChanged: settings.isLoading
                  ? null
                  : (value) => ref
                      .read(notificationSettingsControllerProvider.notifier)
                      .toggleEnabled(value),
            ),
          ),
          if (!settings.isLoading) _PermissionPanel(settings: settings),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'About',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appName,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppConstants.tagline,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppConstants.assessmentDisclaimer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
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

class _PermissionPanel extends ConsumerWidget {
  const _PermissionPanel({required this.settings});

  final NotificationSettingsState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller =
        ref.read(notificationSettingsControllerProvider.notifier);

    switch (settings.permission) {
      case NotificationPermissionStatus.granted:
        return Card(
          child: ListTile(
            leading: Icon(Icons.check_circle, color: scheme.primary),
            title: const Text('Notifications are active'),
            subtitle: const Text(
                'The system permission is granted. Alerts will reach the '
                'notification tray.'),
          ),
        );
      case NotificationPermissionStatus.denied:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_off_outlined,
                        color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Notifications are off at the system level.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Allow notifications to receive weather risk alerts.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      key: const ValueKey('allow_notifications_button'),
                      onPressed: () => controller.allowNotifications(),
                      child: const Text('Allow notifications'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      key: const ValueKey('open_system_settings_button_denied'),
                      onPressed: () => controller.openSystemSettings(),
                      child: const Text('Open app settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      case NotificationPermissionStatus.permanentlyDenied:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.block, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Notifications are blocked.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'The system no longer shows the permission prompt. Re-enable '
                  'notifications from the app settings page.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const ValueKey('open_system_settings_button'),
                  onPressed: () => controller.openSystemSettings(),
                  child: const Text('Open app settings'),
                ),
              ],
            ),
          ),
        );
    }
  }
}