import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../data/repositories/local_repository_providers.dart';
import '../../../domain/entities/alert_status.dart';
import 'alerts_state.dart';

/// Owns alert listing for the alerts tab.
///
/// Widgets never touch the alert repository; they watch
/// [alertsControllerProvider] and call [refresh] / [acknowledge].
class AlertsController extends Notifier<AlertsState> {
  static const int _historyLimit = 50;

  final String _unexpectedMessage = 'Could not load alerts.';

  @override
  AlertsState build() {
    // Kick off an initial load; the widget renders the loading state until
    // refresh completes.
    refresh();
    return const AlertsState.loading();
  }

  /// Reloads active + history lists from the repository.
  Future<void> refresh() async {
    final repository = ref.read(alertHistoryRepositoryProvider);
    final logger = ref.read(appLoggerProvider);
    try {
      final active = await repository.activeAlerts(limit: 50);
      final resolved =
          await repository.alerts(status: AlertStatus.resolved, limit: _historyLimit);
      final expired =
          await repository.alerts(status: AlertStatus.expired, limit: _historyLimit);
      final history = [...resolved, ...expired]
        ..sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
      _set(AlertsState(
        status: AlertsStatus.ready,
        active: active,
        history: history.take(_historyLimit).toList(),
      ));
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