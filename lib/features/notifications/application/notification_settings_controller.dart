import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../data/repositories/local_repository_providers.dart';
import '../../../services/notifications/notification_service_providers.dart';
import 'notification_preferences.dart';
import 'notification_settings_providers.dart';
import 'notification_settings_state.dart';

/// Owns notification preferences + OS permission for the settings screen and
/// the dashboard prompt.
///
/// Widgets never touch the notification plugin or preferences directly; they
/// watch [notificationSettingsControllerProvider] and call [toggleEnabled] /
/// [allowNotifications] / [dismissPrompt] / [openSystemSettings].
class NotificationSettingsController
    extends Notifier<NotificationSettingsState> {
  final String _unexpectedMessage = 'Notification settings are unavailable.';

  @override
  NotificationSettingsState build() {
    _resolve();
    return const NotificationSettingsState.initial();
  }

  Future<void> _resolve() async {
    final preferences = ref.read(preferenceRepositoryProvider);
    final service = ref.read(notificationServiceProvider);
    try {
      final enabled = NotificationPreferences.enabledFrom(
        await preferences.read(NotificationPreferences.enabledKey),
      );
      final dismissed = NotificationPreferences.promptDismissedFrom(
        await preferences.read(NotificationPreferences.promptDismissedKey),
      );
      final permission = await service.permissionStatus();
      _set(NotificationSettingsState(
        isLoading: false,
        enabled: enabled,
        permission: permission,
        promptDismissed: dismissed,
      ));
    } on AppException catch (e) {
      logger.warning('NotificationSettingsController', e.message);
      _set(_failure());
    } catch (e) {
      logger.warning(
        'NotificationSettingsController',
        'resolve failed: ${e.runtimeType}',
      );
      _set(_failure());
    }
  }

  /// Flips the master switch and persists it.
  ///
  /// Absent preference means "enabled" (the default), so disabling must store
  /// an explicit 'false' rather than delete the key.
  Future<void> toggleEnabled(bool enabled) async {
    _set(state.copyWith(enabled: enabled, clearError: true));
    final key = NotificationPreferences.enabledKey;
    try {
      final preferences = ref.read(preferenceRepositoryProvider);
      await preferences.write(key, enabled ? 'true' : 'false');
    } on AppException catch (e) {
      logger.warning('NotificationSettingsController', e.message);
      _set(_failure());
    } catch (e) {
      logger.warning(
        'NotificationSettingsController',
        'toggle failed: ${e.runtimeType}',
      );
      _set(_failure());
    }
  }

  /// Shows the OS permission prompt (kept available while denial is
  /// re-promptable) and refreshes the resolved permission.
  Future<void> allowNotifications() async {
    final service = ref.read(notificationServiceProvider);
    _set(state.copyWith(clearError: true));
    try {
      await service.requestPermission();
      final permission = await service.permissionStatus();
      _set(state.copyWith(permission: permission));
    } on AppException catch (e) {
      logger.warning('NotificationSettingsController', e.message);
      _set(_failure());
    } catch (e) {
      logger.warning(
        'NotificationSettingsController',
        'allowNotifications failed: ${e.runtimeType}',
      );
      _set(_failure());
    }
  }

  /// Persists the user's "Not now" so the dashboard prompt stays out of the
  /// way until they enable it from settings.
  Future<void> dismissPrompt() async {
    _set(state.copyWith(promptDismissed: true));
    try {
      await ref
          .read(preferenceRepositoryProvider)
          .write(NotificationPreferences.promptDismissedKey, 'true');
    } on AppException catch (e) {
      logger.warning('NotificationSettingsController', e.message);
      _set(_failure());
    } catch (e) {
      logger.warning(
        'NotificationSettingsController',
        'dismissPrompt failed: ${e.runtimeType}',
      );
      _set(_failure());
    }
  }

  /// Opens OS app settings (used from the permanently-denied state).
  Future<void> openSystemSettings() async {
    final service = ref.read(notificationServiceProvider);
    try {
      await service.openSystemSettings();
    } on AppException catch (e) {
      logger.warning('NotificationSettingsController', e.message);
      _set(_failure());
    } catch (e) {
      logger.warning(
        'NotificationSettingsController',
        'openSystemSettings failed: ${e.runtimeType}',
      );
      _set(_failure());
    }
  }

  NotificationSettingsState _failure() => state.copyWith(
        isLoading: false,
        errorMessage: _unexpectedMessage,
      );

  void _set(NotificationSettingsState next) {
    if (!ref.mounted) return;
    state = next;
  }

  AppLogger get logger => ref.read(appLoggerProvider);
}