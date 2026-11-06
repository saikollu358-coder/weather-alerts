import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../data/repositories/local_repository_providers.dart';
import '../../../domain/entities/alert_record.dart';
import 'alerts_providers.dart';

/// Loads one stored alert by fingerprint for the detail screen.
///
/// Returns null when no record with that fingerprint exists locally, which is
/// the normal case when the alert has already been resolved and aged out (or
/// when a push arrives for an area the device is not tracking). The screen turns
/// null into an explanatory state rather than an error, since a tap is only a
/// navigation hint.
final alertDetailProvider = FutureProvider.family<AlertRecord?, String>(
  (ref, fingerprint) async {
    if (fingerprint.isEmpty) return null;
    try {
      return await ref
          .read(alertHistoryRepositoryProvider)
          .alertByFingerprint(fingerprint);
    } on AppException catch (e) {
      ref
          .read(appLoggerProvider)
          .warning('AlertDetail', 'lookup failed: ${e.runtimeType}');
      rethrow;
    } catch (e) {
      ref
          .read(appLoggerProvider)
          .warning('AlertDetail', 'lookup failed: ${e.runtimeType}');
      rethrow;
    }
  },
);

/// Acknowledges an alert and refreshes both the detail view and the alerts tab.
///
/// Kept here so the detail screen and the tab share one write path; both read
/// through the same repository.
final acknowledgeAlertProvider = Provider<AcknowledgeAlert>(
  (ref) => AcknowledgeAlert(ref),
);

/// Marks a single alert as acknowledged and invalidates the affected readers.
class AcknowledgeAlert {
  AcknowledgeAlert(this._ref);

  final Ref _ref;

  Future<void> call(String fingerprint) async {
    await _ref
        .read(alertHistoryRepositoryProvider)
        .markAcknowledged(fingerprint);
    _ref.invalidate(alertDetailProvider(fingerprint));
    // The alerts tab shows the same records; keep it from displaying a stale
    // "Acknowledge" button after returning from the detail screen.
    _ref.invalidate(alertsControllerProvider);
  }
}