// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:lpg_app/models/lpg_device.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

   FirestoreService(); // Const constructor

  /// --- User Profile Management ---

  // Get user profile stream
  Stream<DocumentSnapshot<Map<String, dynamic>>> getUserProfileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  // Get user profile once
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  // Create or update user profile
  Future<void> createUserProfile(String uid, String email) async {
    await _db.collection('users').doc(uid).set({
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'devices': [],
      'defaultCylinderEmptyWeight': 14500.0,
      'defaultCylinderFullWeight': 28700.0,
      'lowGasThresholdPercent': 20.0,
    }, SetOptions(merge: true));
  }

  // Update user profile fields (general purpose)
  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  // Update default cylinder weights
  Future<void> updateDefaultCylinderWeights(String uid, double emptyWeight, double fullWeight) async {
    await _db.collection('users').doc(uid).update({
      'defaultCylinderEmptyWeight': emptyWeight,
      'defaultCylinderFullWeight': fullWeight,
    });
  }

  /// --- Device Management ---

  // Link a device to a user's profile
  Future<void> linkDeviceToUser(String userId, String deviceId, String deviceName, double emptyWeight, double fullWeight) async {
    final userRef = _db.collection('users').doc(userId);
    final deviceRef = _db.collection('devices').doc(deviceId);

    await deviceRef.set({
      'name': deviceName,
      'ownerId': userId,
      'emptyWeight': emptyWeight,
      'fullWeight': fullWeight,
      'current_weight_grams': fullWeight,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await userRef.update({
      'devices': FieldValue.arrayUnion([deviceId]),
    });
  }

  // Delete a device and unlink it from the user
  Future<void> deleteDevice(String userId, String deviceId) async {
    await _db.collection('users').doc(userId).update({
      'devices': FieldValue.arrayRemove([deviceId]),
    });
    await _db.collection('devices').doc(deviceId).delete();
  }

  // Get a single device stream
  Stream<LPGDevice> getDeviceStream(String deviceId) {
    return _db.collection('devices').doc(deviceId).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return LPGDevice.fromMap(snapshot.id, snapshot.data()!);
      }
      return LPGDevice(
        id: deviceId,
        name: 'Device Not Found',
        ownerId: '',
        emptyWeight: 0,
        fullWeight: 0,
        currentWeightGrams: 0,
      );
    });
  }

  // Get stream of multiple LPG devices based on their IDs
  Stream<List<LPGDevice>> streamLPGDevices(List<dynamic> deviceIds) {
    if (deviceIds.isEmpty) {
      return Stream.value([]);
    }
    return _db.collection('devices').where(FieldPath.documentId, whereIn: deviceIds).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => LPGDevice.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  // Get device history for a specific device within a date range
  Future<List<Map<String, dynamic>>> getDeviceHistory(String deviceId, DateTime startDate, DateTime endDate) async {
    final startTimestamp = Timestamp.fromDate(startDate.toUtc());
    final endTimestamp = Timestamp.fromDate(endDate.add(const Duration(days: 1)).toUtc());

    final querySnapshot = await _db
        .collection('devices')
        .doc(deviceId)
        .collection('history')
        .where('timestamp', isGreaterThanOrEqualTo: startTimestamp)
        .where('timestamp', isLessThan: endTimestamp)
        .get();

    return querySnapshot.docs.map((doc) => doc.data()).toList();
  }
}