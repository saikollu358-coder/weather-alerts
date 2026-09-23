import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_settings_controller.dart';
import 'notification_settings_state.dart';

/// Drives notification preferences + OS permission for the settings screen and
/// the dashboard prompt.
final notificationSettingsControllerProvider =
    NotifierProvider<NotificationSettingsController, NotificationSettingsState>(
  NotificationSettingsController.new,
);