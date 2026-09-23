import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import 'cloud_data_store.dart';
import 'firebase_availability.dart';

/// Equality / ordering criterion applied to a Firestore query.
class FirestoreWhere {
  const FirestoreWhere(this.field, this.isEqualTo);

  /// Operator is deliberately restricted: only `==` is allowed for client
  /// queries. Range queries are performed server-side only (Cloud Functions),
  /// keeping client access least-privileged and simple.
  final String field;
  final Object? isEqualTo;
}

/// Ordering clause for a Firestore query.
class FirestoreOrderBy {
  const FirestoreOrderBy(this.field, {this.descending = false});

  final String field;
  final bool descending;
}

/// Thin, guarded wrapper around Cloud Firestore.
///
/// All methods check [FirebaseAvailability] first and throw
/// [FirebaseUnavailableException] in local-only mode. Client writes are scoped
/// to data owned by the signed-in user (enforced by `firestore.rules`, this
/// class only routes documents under a caller-supplied `ownerId`).
class FirestoreService implements CloudDataStore {
  FirestoreService({required this.firebase, required this.logger});

  final FirebaseAvailability firebase;
  final AppLogger logger;

  @override
  bool get isAvailable => firebase.isAvailable;

  FirebaseFirestore get _db {
    _requireAvailable();
    return FirebaseFirestore.instance;
  }

  void requireAvailable() => _requireAvailable();

  void _requireAvailable() {
    if (!firebase.isAvailable) {
      throw const FirebaseUnavailableException();
    }
  }

  CollectionReference<Map<String, dynamic>> _ownerCollection(
    String ownerId,
    String collection,
  ) {
    return _db
        .collection('users')
        .doc(ownerId)
        .collection(collection);
  }

  /// Reads a single document. Returns null when it does not exist.
  @override
  Future<Map<String, dynamic>?> getDocument({
    required String ownerId,
    required String collection,
    required String documentId,
  }) async {
    try {
      final snapshot = await _ownerCollection(ownerId, collection)
          .doc(documentId)
          .get();
      return snapshot.data();
    } on FirebaseException catch (e) {
      throw _map(e);
    } on PlatformException catch (e) {
      throw _mapPlatform(e);
    }
  }

  /// Creates or merges a document under the owner's collection.
  @override
  Future<void> setDocument({
    required String ownerId,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    try {
      await _ownerCollection(ownerId, collection)
          .doc(documentId)
          .set(data, SetOptions(merge: merge));
    } on FirebaseException catch (e) {
      throw _map(e);
    } on PlatformException catch (e) {
      throw _mapPlatform(e);
    }
  }

  @override
  Future<void> deleteDocument({
    required String ownerId,
    required String collection,
    required String documentId,
  }) async {
    try {
      await _ownerCollection(ownerId, collection).doc(documentId).delete();
    } on FirebaseException catch (e) {
      throw _map(e);
    } on PlatformException catch (e) {
      throw _mapPlatform(e);
    }
  }

  /// Queries documents belonging to [ownerId].
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> queryDocuments({
    required String ownerId,
    required String collection,
    List<FirestoreWhere> wheres = const [],
    FirestoreOrderBy? orderBy,
    int? limit,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _ownerCollection(ownerId, collection);
      for (final w in wheres) {
        query = query.where(w.field, isEqualTo: w.isEqualTo);
      }
      if (orderBy != null) {
        query = query.orderBy(orderBy.field, descending: orderBy.descending);
      }
      if (limit != null && limit > 0) {
        query = query.limit(limit);
      }
      final snapshot = await query.get();
      return snapshot.docs;
    } on FirebaseException catch (e) {
      throw _map(e);
    } on PlatformException catch (e) {
      throw _mapPlatform(e);
    }
  }

  /// Lists every document (with its id) in the owner's sub-collection —
  /// the read surface used by the Phase 14 cloud sync.
  @override
  Future<List<CloudDoc>> queryData({
    required String ownerId,
    required String collection,
  }) async {
    try {
      final snapshot = await _ownerCollection(ownerId, collection).get();
      return snapshot.docs
          .map((d) => CloudDoc(id: d.id, data: d.data()))
          .toList(growable: false);
    } on FirebaseException catch (e) {
      throw _map(e);
    } on PlatformException catch (e) {
      throw _mapPlatform(e);
    }
  }

  /// Real-time stream for a single document.
  Stream<Map<String, dynamic>?> watchDocument({
    required String ownerId,
    required String collection,
    required String documentId,
  }) {
    _requireAvailable();
    return _ownerCollection(ownerId, collection)
        .doc(documentId)
        .snapshots()
        .map((snap) => snap.data())
        .handleError((Object e) {
      throw _mapAny(e);
    });
  }

  /// Real-time stream for a query.
  Stream<List<Map<String, dynamic>>> watchQuery({
    required String ownerId,
    required String collection,
    List<FirestoreWhere> wheres = const [],
    FirestoreOrderBy? orderBy,
    int? limit,
  }) {
    _requireAvailable();
    Query<Map<String, dynamic>> query = _ownerCollection(ownerId, collection);
    for (final w in wheres) {
      query = query.where(w.field, isEqualTo: w.isEqualTo);
    }
    if (orderBy != null) {
      query = query.orderBy(orderBy.field, descending: orderBy.descending);
    }
    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }
    return query.snapshots().map((snap) => snap.docs.map((d) => d.data()).toList()).handleError(
          (Object e) => throw _mapAny(e),
        );
  }

  FirebaseOperationException _map(FirebaseException e) {
    logger.warning('FirestoreService', 'operation failed: ${e.code}');
    return FirebaseOperationException(
      code: e.code,
      message: 'Cloud data operation could not be completed.',
      cause: e,
    );
  }

  FirebaseOperationException _mapPlatform(PlatformException e) {
    logger.warning('FirestoreService', 'operation failed: ${e.code}');
    return FirebaseOperationException(
      code: e.code,
      message: 'Cloud data operation could not be completed.',
      cause: e,
    );
  }

  AppException _mapAny(Object e) {
    if (e is AppException) return e;
    if (e is FirebaseException) return _map(e);
    if (e is PlatformException) return _mapPlatform(e);
    logger.warning('FirestoreService', 'unexpected failure ${e.runtimeType}');
    return const FirebaseOperationException(
      code: 'unknown',
      message: 'Cloud data operation could not be completed.',
    );
  }
}