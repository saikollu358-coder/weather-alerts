import 'dart:async';
import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/alert_record.dart';
import '../../domain/entities/alert_status.dart';
import '../../domain/entities/monitored_location_record.dart';
import '../../domain/entities/user_preference.dart';
import '../../domain/repositories/alert_history_repository.dart';
import '../../domain/repositories/monitored_location_repository.dart';
import '../../domain/repositories/preference_repository.dart';
import '../../domain/repositories/sync_state_repository.dart';
import '../../domain/services/auth_service.dart';
import '../firebase/cloud_data_store.dart';
import 'sync_domain.dart';
import 'sync_planner.dart';

/// Result of a single domain sync run.
class SyncDomainResult {
  const SyncDomainResult({
    required this.domain,
    this.uploaded = 0,
    this.appliedLocal = 0,
    this.deletedRemote = 0,
    this.deletedLocal = 0,
  });

  final SyncDomain domain;
  final int uploaded;
  final int appliedLocal;
  final int deletedRemote;
  final int deletedLocal;

  bool get isEmpty =>
      uploaded == 0 &&
      appliedLocal == 0 &&
      deletedRemote == 0 &&
      deletedLocal == 0;

  @override
  String toString() => 'SyncResult(${domain.syncKey}: '
      'up:$uploaded dl:$appliedLocal dr:$deletedRemote del:$deletedLocal)';
}

/// Phase 14 cloud-sync orchestrator.
///
/// Reconciles locally-persisted user data (locations, preferences, alert
/// history) with the per-user Firestore sub-collections, using last-write-wins
/// semantics and a persistent snapshot (stored in the local [SyncStateRepository])
/// to detect remote deletions across devices.
///
/// Preference syncing is restricted to [syncablePreferenceKeys] so local-only
/// tokens (e.g. `device_id`) never leak to the cloud.
class CloudSyncService {
  CloudSyncService({
    required this.store,
    required this.auth,
    required this.locations,
    required this.preferences,
    required this.alerts,
    required this.syncState,
    required this.logger,
  });

  final CloudDataStore store;
  final AuthService auth;
  final MonitoredLocationRepository locations;
  final PreferenceRepository preferences;
  final AlertHistoryRepository alerts;
  final SyncStateRepository syncState;
  final AppLogger logger;

  /// User preference keys that are user-editable and safe to sync across
  /// devices.  Local-only tokens such as `device_id` are intentionally
  /// excluded.
  static const Set<String> syncablePreferenceKeys = {
    'notifications_enabled',
    'notification_prompt_dismissed',
  };

  static const Duration syncInterval = AppConstants.weatherRefreshInterval;

  bool _running = false;
  Timer? _timer;

  // ------------------------------------------------------------------
  // Availability
  // ------------------------------------------------------------------

  bool get isSyncAvailable => store.isAvailable && _uid != null;

  String? get _uid {
    final user = auth.currentUser;
    if (user == null || user.isLocalGuest) return null;
    return user.uid;
  }

  // ------------------------------------------------------------------
  // Public surface
  // ------------------------------------------------------------------

  /// Synchronizes every domain.  Errors in one domain do not prevent the
  /// others from running.  No-op when Firebase is unavailable or the user is
  /// a local guest.
  Future<void> syncAll() async {
    if (!isSyncAvailable) return;
    if (_running) return;
    _running = true;
    try {
      for (final domain in SyncDomain.values) {
        try {
          await syncDomain(domain);
        } on AppException catch (e) {
          logger.warning(
            'CloudSync',
            '${domain.syncKey} failed during syncAll: ${e.message}',
          );
        }
      }
    } finally {
      _running = false;
    }
  }

  /// Reconciles a single sync domain.  Throws [AppException] on failure
  /// after the attempt is recorded.
  Future<SyncDomainResult> syncDomain(SyncDomain domain) async {
    final uid = _uid;
    if (uid == null) throw const FirebaseUnavailableException();

    await syncState.recordAttempt(domain.syncKey);
    try {
      final result = await _runDomain(domain, uid);
      final json = _encodeSnapshot(result.nextSnapshot);
      await syncState.recordSuccess(domain.syncKey, value: json);
      return SyncDomainResult(
        domain: domain,
        uploaded: result.plan.uploadKeys.length,
        appliedLocal: result.plan.applyLocalKeys.length,
        deletedRemote: result.plan.deleteRemoteKeys.length,
        deletedLocal: result.plan.deleteLocalKeys.length,
      );
    } on AppException catch (e) {
      await syncState.recordFailure(domain.syncKey);
      logger.warning('CloudSync', '${domain.syncKey} failed: ${e.message}');
      rethrow;
    }
  }

  /// Starts a periodic background resync.  Safe to call repeatedly.
  void startPeriodic() {
    if (_timer != null) return;
    _timer = Timer.periodic(syncInterval, (_) => syncAll());
  }

  /// Cancels the periodic resync.
  void stopPeriodic() {
    _timer?.cancel();
    _timer = null;
  }

  // ------------------------------------------------------------------
  // Domain internals
  // ------------------------------------------------------------------

  Future<_ReconcileResult> _runDomain(SyncDomain domain, String uid) async {
    final loaded = await _loadDomain(domain, uid);

    final snapshotState = await syncState.stateFor(domain.syncKey);
    final snapshotMap = _decodeSnapshot(snapshotState?.value);

    final plan = SyncPlanner.plan(
      local: loaded.localUpdated,
      remote: loaded.remoteUpdated,
      snapshot: snapshotMap,
      deletionsEnabled: domain != SyncDomain.alerts,
    );

    await _executeUploads(domain, uid, plan, loaded);
    await _executeDeletes(domain, uid, plan, loaded);
    await _executeApplies(domain, uid, plan, loaded);

    return _ReconcileResult(plan: plan, nextSnapshot: plan.nextSnapshot);
  }

  // ------------------------------------------------------------------
  // Load local + remote data
  // ------------------------------------------------------------------

  Future<_DomainData> _loadDomain(SyncDomain domain, String uid) async {
    final remoteDocs = await store.queryData(
      ownerId: uid,
      collection: domain.collection,
    );
    final remoteUpdated = <String, DateTime>{};
    final remoteFull = <String, Map<String, dynamic>>{};
    for (final doc in remoteDocs) {
      final ms = doc.data['updatedAtUtc'] as int?;
      if (ms != null) {
        remoteUpdated[doc.id] = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      }
      remoteFull[doc.id] = doc.data;
    }

    switch (domain) {
      case SyncDomain.locations:
        final records = await locations.allLocations();
        final localUpdated = <String, DateTime>{};
        final localDocs = <String, Map<String, dynamic>>{};
        for (final r in records) {
          localUpdated[r.locationKey] = r.updatedAtUtc;
          localDocs[r.locationKey] = _locationToDoc(r);
        }
        return _DomainData(localUpdated, localDocs, remoteUpdated, remoteFull);
      case SyncDomain.preferences:
        final prefs = await preferences.all();
        final localUpdated = <String, DateTime>{};
        final localDocs = <String, Map<String, dynamic>>{};
        for (final p in prefs) {
          if (!syncablePreferenceKeys.contains(p.key)) continue;
          localUpdated[p.key] = p.updatedAtUtc;
          localDocs[p.key] = _preferenceToDoc(p);
        }
        return _DomainData(localUpdated, localDocs, remoteUpdated, remoteFull);
      case SyncDomain.alerts:
        final records = await alerts.alerts();
        final localUpdated = <String, DateTime>{};
        final localDocs = <String, Map<String, dynamic>>{};
        for (final r in records) {
          localUpdated[r.fingerprint] = r.updatedAtUtc;
          localDocs[r.fingerprint] = _alertToDoc(r);
        }
        return _DomainData(localUpdated, localDocs, remoteUpdated, remoteFull);
    }
  }

  // ------------------------------------------------------------------
  // Execute plan actions
  // ------------------------------------------------------------------

  Future<void> _executeUploads(
    SyncDomain domain,
    String uid,
    SyncPlan plan,
    _DomainData loaded,
  ) async {
    for (final key in plan.uploadKeys) {
      final doc = loaded.localDocs[key];
      if (doc == null) continue;
      await store.setDocument(
        ownerId: uid,
        collection: domain.collection,
        documentId: key,
        data: doc,
      );
    }
  }

  Future<void> _executeDeletes(
    SyncDomain domain,
    String uid,
    SyncPlan plan,
    _DomainData loaded,
  ) async {
    for (final key in plan.deleteRemoteKeys) {
      await store.deleteDocument(
        ownerId: uid,
        collection: domain.collection,
        documentId: key,
      );
    }
    for (final key in plan.deleteLocalKeys) {
      await _deleteLocal(domain, key, loaded);
    }
  }

  Future<void> _executeApplies(
    SyncDomain domain,
    String uid,
    SyncPlan plan,
    _DomainData loaded,
  ) async {
    for (final key in plan.applyLocalKeys) {
      final data = loaded.remoteDocs[key];
      if (data == null) continue;
      await _applyRemote(domain, key, data);
    }
  }

  Future<void> _applyRemote(
    SyncDomain domain,
    String key,
    Map<String, dynamic> data,
  ) async {
    switch (domain) {
      case SyncDomain.locations:
        final record = _locationFromDoc(key, data);
        final existing = await locations.byCoordinates(
          record.latitude,
          record.longitude,
        );
        if (existing == null) {
          await locations.addLocation(record);
        } else {
          await locations.updateLocation(record.copyWith(id: existing.id));
        }
      case SyncDomain.preferences:
        await preferences.write(key, data['value'] as String? ?? '');
      case SyncDomain.alerts:
        await alerts.upsertAlert(_alertFromDoc(data));
    }
  }

  Future<void> _deleteLocal(
    SyncDomain domain,
    String key,
    _DomainData loaded,
  ) async {
    switch (domain) {
      case SyncDomain.locations:
        final parts = key.split(',');
        if (parts.length == 2) {
          final lat = double.tryParse(parts[0]);
          final lng = double.tryParse(parts[1]);
          if (lat != null && lng != null) {
            final existing = await locations.byCoordinates(lat, lng);
            if (existing?.id != null) {
              await locations.removeLocation(existing!.id!);
            }
          }
        }
      case SyncDomain.preferences:
        await preferences.delete(key);
      case SyncDomain.alerts:
        // Deletions are not tracked for the alerts domain.
        break;
    }
  }

  // ------------------------------------------------------------------
  // Snapshot serialization
  // ------------------------------------------------------------------

  static String _encodeSnapshot(Map<String, DateTime> map) {
    return jsonEncode({
      'snapshot': {
        for (final e in map.entries) e.key: e.value.millisecondsSinceEpoch,
      },
    });
  }

  static Map<String, DateTime> _decodeSnapshot(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final map = parsed['snapshot'] as Map<String, dynamic>?;
      if (map == null) return const {};
      return {
        for (final e in map.entries)
          if (e.value is int)
            e.key: DateTime.fromMillisecondsSinceEpoch(e.value as int, isUtc: true),
      };
    } on Object {
      return const {};
    }
  }
}

// ------------------------------------------------------------------
// Private helpers — no state
// ------------------------------------------------------------------

class _DomainData {
  const _DomainData(
    this.localUpdated,
    this.localDocs,
    this.remoteUpdated,
    this.remoteDocs,
  );

  final Map<String, DateTime> localUpdated;
  final Map<String, Map<String, dynamic>> localDocs;
  final Map<String, DateTime> remoteUpdated;
  final Map<String, Map<String, dynamic>> remoteDocs;
}

class _ReconcileResult {
  const _ReconcileResult({required this.plan, required this.nextSnapshot});

  final SyncPlan plan;
  final Map<String, DateTime> nextSnapshot;
}

// ------------------------------------------------------------------
// Domain doc codecs (module-private, deterministic)
// ------------------------------------------------------------------

Map<String, dynamic> _locationToDoc(MonitoredLocationRecord r) => {
      'name': r.name,
      'latitude': r.latitude,
      'longitude': r.longitude,
      if (r.accuracy != null) 'accuracy': r.accuracy,
      'source': r.source.name,
      'isMonitored': r.isMonitored,
      'isPrimary': r.isPrimary,
      'createdAtUtc': r.createdAtUtc.millisecondsSinceEpoch,
      'updatedAtUtc': r.updatedAtUtc.millisecondsSinceEpoch,
      if (r.lastUsedAtUtc != null)
        'lastUsedAtUtc': r.lastUsedAtUtc!.millisecondsSinceEpoch,
    };

MonitoredLocationRecord _locationFromDoc(
  String key,
  Map<String, dynamic> data,
) {
  final sourceStr = data['source'] as String? ?? 'gps';
  return MonitoredLocationRecord(
    name: data['name'] as String? ?? '',
    latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
    accuracy: (data['accuracy'] as num?)?.toDouble(),
    source: MonitoredLocationSource.values
            .where((v) => v.name == sourceStr)
            .firstOrNull ?? MonitoredLocationSource.gps,
    isMonitored: data['isMonitored'] as bool? ?? false,
    isPrimary: data['isPrimary'] as bool? ?? false,
    createdAtUtc: _msToUtc(data['createdAtUtc']),
    updatedAtUtc: _msToUtc(data['updatedAtUtc']),
    lastUsedAtUtc:
        data['lastUsedAtUtc'] != null ? _msToUtc(data['lastUsedAtUtc']) : null,
  );
}

Map<String, dynamic> _preferenceToDoc(UserPreference p) => {
      'value': p.value,
      'updatedAtUtc': p.updatedAtUtc.millisecondsSinceEpoch,
    };

Map<String, dynamic> _alertToDoc(AlertRecord r) => {
      'fingerprint': r.fingerprint,
      'hazard': r.hazard,
      'severity': r.severity,
      'status': r.status.name,
      'title': r.title,
      'description': r.description,
      'reason': r.reason,
      'locationKey': r.locationKey,
      'payload': jsonEncode(r.payload),
      'detectedAtUtc': r.detectedAtUtc.millisecondsSinceEpoch,
      'updatedAtUtc': r.updatedAtUtc.millisecondsSinceEpoch,
      if (r.resolvedAtUtc != null)
        'resolvedAtUtc': r.resolvedAtUtc!.millisecondsSinceEpoch,
      if (r.expiresAtUtc != null)
        'expiresAtUtc': r.expiresAtUtc!.millisecondsSinceEpoch,
      'acknowledged': r.acknowledged,
    };

AlertRecord _alertFromDoc(Map<String, dynamic> data) {
  final statusStr = data['status'] as String? ?? 'detected';
  return AlertRecord(
    fingerprint: data['fingerprint'] as String? ?? '',
    hazard: data['hazard'] as String? ?? '',
    severity: data['severity'] as String? ?? '',
    status: AlertStatus.values
            .where((v) => v.name == statusStr)
            .firstOrNull ?? AlertStatus.detected,
    title: data['title'] as String? ?? '',
    description: data['description'] as String? ?? '',
    reason: data['reason'] as String? ?? '',
    locationKey: data['locationKey'] as String? ?? '',
    payload: _parsePayload(data['payload']),
    detectedAtUtc: _msToUtc(data['detectedAtUtc']),
    updatedAtUtc: _msToUtc(data['updatedAtUtc']),
    resolvedAtUtc: data['resolvedAtUtc'] != null
        ? _msToUtc(data['resolvedAtUtc'])
        : null,
    expiresAtUtc: data['expiresAtUtc'] != null
        ? _msToUtc(data['expiresAtUtc'])
        : null,
    acknowledged: data['acknowledged'] as bool? ?? false,
  );
}

DateTime _msToUtc(dynamic ms) {
  if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return DateTime.utc(2026);
}

Map<String, dynamic> _parsePayload(dynamic raw) {
  if (raw is String && raw.isNotEmpty) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) return parsed;
    } on Object {
      // Intentional: malformed payloads are treated as empty.
    }
  }
  return const {};
}
