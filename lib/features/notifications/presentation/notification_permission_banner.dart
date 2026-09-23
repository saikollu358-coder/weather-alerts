import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/enums/notification_permission.dart';
import '../application/notification_settings_providers.dart';

/// In-app prompt asking the user to enable weather-risk notifications.
///
/// Shown inline on the dashboard home tab only when it can actually help:
/// notifications are enabled in preferences, the OS permission is not granted
/// and the user has not dismissed the prompt ("Not now").
class NotificationPermissionBanner extends ConsumerWidget {
  const NotificationPermissionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsControllerProvider);
    if (settings.isLoading || !settings.canShowPrompt) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(notificationSettingsControllerProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final action = switch (settings.permission) {
      NotificationPermissionStatus.denied => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const ValueKey('dismiss_notifications_banner_button'),
              onPressed: () => controller.dismissPrompt(),
              child: const Text('Not now'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('allow_notifications_banner_button'),
              onPressed: () => controller.allowNotifications(),
              child: const Text('Allow'),
            ),
          ],
        ),
      NotificationPermissionStatus.permanentlyDenied => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const ValueKey('dismiss_notifications_banner_button'),
              onPressed: () => controller.dismissPrompt(),
              child: const Text('Not now'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('open_system_settings_banner_button'),
              onPressed: () => controller.openSystemSettings(),
              child: const Text('Open app settings'),
            ),
          ],
        ),
      NotificationPermissionStatus.granted => const SizedBox.shrink(),
    };

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Enable weather alerts to stay informed about hazards at '
                    'your monitored locations.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            action,
          ],
        ),
      ),
    );
  }
}