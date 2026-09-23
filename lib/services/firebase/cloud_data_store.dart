/// A document returned from the user's cloud sub-collection.
class CloudDoc {
  const CloudDoc({required this.id, required this.data});

  /// Firestore document id (the sync record key, e.g. `locationKey`,
  /// `fingerprint` or preference key).
  final String id;

  /// Raw document fields.
  final Map<String, dynamic> data;
}

/// Minimal, owner-scoped data plane used by the Phase 14 cloud sync.
///
/// Kept deliberately narrow (read/upsert/delete + list under a single owner
/// sub-collection) so the sync engine stays testable: fakes only implement
/// these five members instead of the full Firestore SDK surface.
///
/// [FirestoreService] is the production implementation; writes are scoped to
/// `users/{uid}/<collection>` and enforced by `firestore.rules`.
abstract interface class CloudDataStore {
  /// False when no cloud backend exists in this build.
  bool get isAvailable;

  /// Reads a single document, or null when it does not exist.
  Future<Map<String, dynamic>?> getDocument({
    required String ownerId,
    required String collection,
    required String documentId,
  });

  /// Creates or merges a document under the owner's collection.
  Future<void> setDocument({
    required String ownerId,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    bool merge = true,
  });

  /// Deletes a document under the owner's collection.
  Future<void> deleteDocument({
    required String ownerId,
    required String collection,
    required String documentId,
  });

  /// Lists every document in the owner's sub-collection with its id.
  Future<List<CloudDoc>> queryData({
    required String ownerId,
    required String collection,
  });
}