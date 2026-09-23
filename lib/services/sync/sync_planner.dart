/// Result of [SyncPlanner.plan]: the exact remote/local actions to execute
/// and the reconciled snapshot to persist after a successful sync run.
class SyncPlan {
  const SyncPlan({
    required this.uploadKeys,
    required this.applyLocalKeys,
    required this.deleteRemoteKeys,
    required this.deleteLocalKeys,
    required this.nextSnapshot,
  });

  /// Keys whose local copy is newer or absent remotely → write to the cloud.
  final List<String> uploadKeys;

  /// Keys whose cloud copy is newer or absent locally → apply locally.
  final List<String> applyLocalKeys;

  /// Keys deleted locally and unchanged remotely → delete from the cloud.
  final List<String> deleteRemoteKeys;

  /// Keys deleted remotely and unchanged locally → delete locally.
  final List<String> deleteLocalKeys;

  /// Reconciled key → updatedAtUtc (UTC) to persist as the next snapshot
  /// after a successful sync.
  final Map<String, DateTime> nextSnapshot;

  bool get isEmpty =>
      uploadKeys.isEmpty &&
      applyLocalKeys.isEmpty &&
      deleteRemoteKeys.isEmpty &&
      deleteLocalKeys.isEmpty;

  @override
  String toString() =>
      'SyncPlan(up:${uploadKeys.length}, dl:${applyLocalKeys.length}, '
      'dr:${deleteRemoteKeys.length}, del:${deleteLocalKeys.length})';
}

/// Pure, deterministic last-write-wins reconciliation planner.
///
/// Given the local state, remote state and last-snapshotted remote view for a
/// single sync domain, decides which records to upload, pull, or delete on
/// either side. The service layer executes the plan and persists the
/// [SyncPlan.nextSnapshot] after a successful run.
///
/// When [deletionsEnabled] is `false` (currently the `alerts` domain) the
/// planner recreates records on the side that dropped them instead of deleting
/// from the other side — alerts are append-only in practice and local purge
/// is treated as cache hygiene, not an authoritative delete.
abstract final class SyncPlanner {
  static SyncPlan plan({
    required Map<String, DateTime> local,
    required Map<String, DateTime> remote,
    required Map<String, DateTime> snapshot,
    bool deletionsEnabled = true,
  }) {
    final keys = <String>{...local.keys, ...remote.keys, ...snapshot.keys};
    final upload = <String>[];
    final apply = <String>[];
    final delRemote = <String>[];
    final delLocal = <String>[];
    final next = <String, DateTime>{};

    for (final key in keys) {
      final hasLocal = local.containsKey(key);
      final hasRemote = remote.containsKey(key);
      final hasSnap = snapshot.containsKey(key);
      final lT = local[key];
      final rT = remote[key];
      final sT = snapshot[key];

      // Both sides present.
      if (hasLocal && hasRemote) {
        final l = lT!;
        final r = rT!;
        if (l.isAfter(r)) {
          upload.add(key);
          next[key] = l;
        } else if (r.isAfter(l)) {
          apply.add(key);
          next[key] = r;
        } else {
          // Equal timestamps — unchanged.
          next[key] = l;
        }
        continue;
      }

      // Local only.
      if (hasLocal) {
        final l = lT!;
        if (hasSnap && sT != null && !l.isAfter(sT)) {
          // Remote deleted and local unchanged since last snapshot.
          if (deletionsEnabled) {
            delLocal.add(key);
            // key omitted from next snapshot.
          } else {
            // Recreate in the cloud instead of deleting locally.
            upload.add(key);
            next[key] = l;
          }
        } else {
          // Local creation, local re-creation after remote delete,
          // or local updated after snapshot — upload.
          upload.add(key);
          next[key] = l;
        }
        continue;
      }

      // Remote only.
      if (hasRemote) {
        final r = rT!;
        if (hasSnap && sT != null && !r.isAfter(sT)) {
          // Local deleted and remote unchanged since last snapshot.
          if (deletionsEnabled) {
            delRemote.add(key);
            // key omitted from next snapshot.
          } else {
            // Reapply locally instead of deleting remotely.
            apply.add(key);
            next[key] = r;
          }
        } else {
          // Remote creation, remote re-creation after local delete,
          // or remote updated after snapshot — apply locally.
          apply.add(key);
          next[key] = r;
        }
        continue;
      }

      // Snapshot only — deleted on both sides; drop from snapshot.
    }

    return SyncPlan(
      uploadKeys: upload,
      applyLocalKeys: apply,
      deleteRemoteKeys: delRemote,
      deleteLocalKeys: delLocal,
      nextSnapshot: next,
    );
  }
}
