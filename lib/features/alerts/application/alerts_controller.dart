import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../data/repositories/local_repository_providers.dart';
import 'alerts_state.dart';

/// Owns alert listing for the alerts tab.
///
/// Widgets never touch the alert repository; they watch
/// [alertsControllerProvider] and call [refresh] / [acknowledge].
///
/// Only currently-active alerts are exposed. Resolved and expired records stay
/// in the local store because the ingest pipeline needs them for deduplication
/// and escalation tracking, but they are not part of this tab.
class AlertsController extends Notifier<AlertsState> {
  final String _unexpectedMessage = 'Could not load alerts.';

  @override
  AlertsState build() {
    // Kick off an initial load; the widget renders the loading state until
    // refresh completes.
    refresh();
    return const AlertsState.loading();
  }

  /// Reloads the active alerts from the repository.
  Future<void> refresh() async {
    final repository = ref.read(alertHistoryRepositoryProvider);
    final logger = ref.read(appLoggerProvider);
    try {
      final active = await repository.activeAlerts(limit: 50);
      _set(AlertsState(status: AlertsStatus.ready, active: active));
    } on AppException catch (e) {
      _set(AlertsState(status: AlertsStatus.error, errorMessage: e.message));
    } catch (e) {
      logger.warning('AlertsController', 'refresh failed: ${e.runtimeType}');
      _set(AlertsState(status: AlertsStatus.error, errorMessage: _unexpectedMessage));
    }
  }

  /// Marks an active alert as acknowledged by the user.
  Future<void> acknowledge(String fingerprint) async {
    try {
      await ref
          .read(alertHistoryRepositoryProvider)
          .markAcknowledged(fingerprint);
      await refresh();
    } catch (e) {
      ref.read(appLoggerProvider).warning(
          'AlertsController', 'acknowledge failed: ${e.runtimeType}');
    }
  }

  void _set(AlertsState next) {
    if (!ref.mounted) return;
    state = next;
  }
}