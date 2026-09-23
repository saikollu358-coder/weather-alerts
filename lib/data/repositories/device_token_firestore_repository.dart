import 'dart:async';

import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/device_token_record.dart';
import '../../domain/repositories/device_token_repository.dart';
import '../../services/firebase/firestore_service.dart';

/// Firestore-backed [DeviceTokenRepository] (Phase 12).
///
/// Tokens live under `users/{uid}/devices/{deviceId}` — a user-owned
/// sub-collection enforced by `firestore.rules`. The server-side push router
/// (`functions/src/server_alerts/push_router.ts`) reads this collection via
/// the Admin SDK.
class DeviceTokenFirestoreRepository implements DeviceTokenRepository {
  DeviceTokenFirestoreRepository({
    required this.firestore,
    required this.logger,
  });

  final FirestoreService firestore;
  final AppLogger logger;

  static const String _devicesCollection = 'devices';
  static const String _fieldToken = 'token';
  static const String _fieldDeviceId = 'deviceId';
  static const String _fieldUid = 'uid';
  static const String _fieldLocationKeys = 'locationKeys';
  static const String _fieldPlatform = 'platform';
  static const String _fieldCreatedAtUtc = 'createdAtUtc';
  static const String _fieldUpdatedAtUtc = 'updatedAtUtc';

  @override
  Future<void> registerToken(DeviceTokenRecord record) async {
    final now = DateTime.now().toUtc();
    final data = _toMap(record, now);
    try {
      await firestore.setDocument(
        ownerId: record.uid,
        collection: _devicesCollection,
        documentId: record.deviceId,
        data: data,
      );
    } on AppException catch (e) {
      logger.warning('DeviceTokenRepository', 'register failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<void> updateLocations({
    required String uid,
    required String deviceId,
    required List<String> locationKeys,
  }) async {
    final now = DateTime.now().toUtc();
    try {
      await firestore.setDocument(
        ownerId: uid,
        collection: _devicesCollection,
        documentId: deviceId,
        data: {
          _fieldLocationKeys: locationKeys,
          _fieldUpdatedAtUtc: now.millisecondsSinceEpoch,
        },
      );
    } on AppException catch (e) {
      logger.warning('DeviceTokenRepository', 'updateLocations failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<void> removeToken({
    required String uid,
    required String deviceId,
  }) async {
    try {
      await firestore.deleteDocument(
        ownerId: uid,
        collection: _devicesCollection,
        documentId: deviceId,
      );
    } on AppException catch (e) {
      logger.warning('DeviceTokenRepository', 'remove failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<void> removeAllTokens({required String uid}) async {
    try {
      final docs = await firestore.queryDocuments(
        ownerId: uid,
        collection: _devicesCollection,
      );
      for (final doc in docs) {
        await doc.reference.delete();
      }
    } on AppException catch (e) {
      logger.warning('DeviceTokenRepository', 'removeAll failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<List<DeviceTokenRecord>> tokensForUser(String uid) async {
    try {
      final docs = await firestore.queryDocuments(
        ownerId: uid,
        collection: _devicesCollection,
      );
      return docs.map((doc) => _fromMap(doc.id, uid, doc.data())).toList();
    } on AppException catch (e) {
      logger.warning('DeviceTokenRepository', 'tokensForUser failed: ${e.message}');
      rethrow;
    }
  }

  Map<String, dynamic> _toMap(DeviceTokenRecord record, DateTime now) {
    return {
      _fieldToken: record.token,
      _fieldDeviceId: record.deviceId,
      _fieldUid: record.uid,
      _fieldLocationKeys: record.locationKeys,
      _fieldPlatform: record.platform,
      _fieldCreatedAtUtc:
          (record.createdAtUtc ?? now).millisecondsSinceEpoch,
      _fieldUpdatedAtUtc: now.millisecondsSinceEpoch,
    };
  }

  DeviceTokenRecord _fromMap(String docId, String uid, Map<String, dynamic> data) {
    return DeviceTokenRecord(
      token: data[_fieldToken] as String? ?? '',
      deviceId: data[_fieldDeviceId] as String? ?? docId,
      uid: uid,
      locationKeys: _parseLocationKeys(data[_fieldLocationKeys]),
      platform: data[_fieldPlatform] as String?,
      createdAtUtc: _parseTimestamp(data[_fieldCreatedAtUtc]),
      updatedAtUtc: _parseTimestamp(data[_fieldUpdatedAtUtc]),
    );
  }

  List<String> _parseLocationKeys(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return null;
  }
}
