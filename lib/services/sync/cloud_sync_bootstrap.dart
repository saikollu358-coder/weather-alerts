import 'dart:async';

import '../../core/utils/logger.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/services/auth_service.dart';
import 'cloud_sync_service.dart';

/// One-time startup wiring for the Phase 14 cloud sync.
///
/// Listens to the [AuthService] session stream and starts / stops the
/// periodic resync.  A signed-in non-guest user triggers an immediate
/// reconciliation.  The bootstrap never throws: failures are logged and
/// swallowed so the app boots reliably in local-only or offline mode.
class CloudSyncBootstrap {
  CloudSyncBootstrap({
    required this.sync,
    required this.auth,
    required this.logger,
  });

  final CloudSyncService sync;
  final AuthService auth;
  final AppLogger logger;

  bool _initialized = false;

  /// Subscribes to auth state and kicks off the first sync (if the user
  /// is signed in and Firebase is configured).  Idempotent.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    auth.watchAuthState().listen(
      _onAuthChanged,
      onError: (Object _) {
        // Stream errors are advisory; the sync keeps running.
      },
    );
    // If a session was already restored before the first event fires,
    // kick off a sync for the current user.
    _onAuthChanged(auth.currentUser);
  }

  void _onAuthChanged(AuthUser? user) {
    final signedInNonGuest = user != null && !user.isLocalGuest;
    if (signedInNonGuest) {
      logger.debug('CloudSyncBootstrap', 'sync enabled for ${user.uid}');
      unawaited(sync.syncAll());
      sync.startPeriodic();
    } else {
      sync.stopPeriodic();
    }
  }
}