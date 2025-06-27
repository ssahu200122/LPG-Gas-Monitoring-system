import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lpg_app/models/lpg_device.dart';
import 'package:async/async.dart'; // Import StreamGroup for combining streams

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

   FirestoreService(); // Constructor

  /// Creates or updates a user profile document in Firestore.
  /// Used during user signup to store initial user data.
  Future<void> createUserProfile(String uid, String email) async {
    final userDocRef = _db.collection('users').doc(uid);
    await userDocRef.set({
      'email': email,
      'createdAt': FieldValue.serverTimestamp(), // Use server timestamp for consistency
      'devices': [], // Initialize with an empty array of device IDs
      'defaultCylinderEmptyWeight': 14500.0, // Example default empty weight in grams
      'defaultCylinderFullWeight': 28700.0,  // Example default full weight in grams
      'lowGasThresholdPercent': 20.0, // Default low gas threshold
    }, SetOptions(merge: true)); // Use merge to avoid overwriting existing fields
  }

  /// Updates specific fields in a user's profile document.
  /// [uid]: The UID of the user whose profile is to be updated.
  /// [data]: A map of fields to update (e.g., {'lowGasThresholdPercent': 15.0}).
  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    final userDocRef = _db.collection('users').doc(uid);
    await userDocRef.update(data); // Use .update() to merge specific fields
  }


  /// Retrieves a Future of a user's profile document.
  /// Used for one-time fetches of user data.
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  /// Retrieves a Stream of a user's profile document.
  /// Used for real-time updates to the user's profile (e.g., linked devices list).
  Stream<DocumentSnapshot<Map<String, dynamic>>> getUserProfileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  /// Links a new LPG device to a user's profile in Firestore.
  /// Also creates the initial device document.
  Future<void> linkDeviceToUser(
    String userId,
    String deviceId,
    String name,
    double emptyWeight,
    double fullWeight,
  ) async {
    // 1. Add deviceId to the user's document 'devices' array
    final userDocRef = _db.collection('users').doc(userId);
    await userDocRef.update({
      'devices': FieldValue.arrayUnion([deviceId]), // Add deviceId if not already present
    });

    // 2. Create/update the individual device document
    final deviceDocRef = _db.collection('devices').doc(deviceId);
    await deviceDocRef.set({
      'name': name,
      'ownerId': userId, // Link device to its owner
      'emptyWeight': emptyWeight,
      'fullWeight': fullWeight,
      'createdAt': FieldValue.serverTimestamp(),
      'current_weight_grams': emptyWeight, // Initialize current weight (can be 0 or emptyWeight)
      'timestamp': FieldValue.serverTimestamp(), // Initial timestamp
      // Add other relevant device properties here (e.g., thresholds, status)
    }, SetOptions(merge: true)); // Use merge to not overwrite if device already exists
  }

  /// Streams real-time updates for a list of LPG devices by their IDs.
  /// This method combines individual document streams into a single stream.
  ///
  /// [deviceIds]: A list of unique device IDs (strings).
  /// Returns a Stream that emits a List of [LPGDevice] objects whenever
  /// any of the specified devices' documents change in Firestore.
  Stream<List<LPGDevice>> streamLPGDevices(List<dynamic> deviceIds) {
    if (deviceIds.isEmpty) {
      return Stream.value([]);
    }

    final List<Stream<DocumentSnapshot<Map<String, dynamic>>>> individualDeviceStreams = deviceIds
        .cast<String>()
        .map((id) => _db.collection('devices').doc(id).snapshots())
        .toList();

    return StreamGroup.merge(individualDeviceStreams).map((_) {
      return Future.wait(deviceIds.cast<String>().map((id) async {
        final doc = await _db.collection('devices').doc(id).get();
        return doc.exists ? LPGDevice.fromMap(doc.id, doc.data()!) : null;
      })).then((list) {
        return list.whereType<LPGDevice>().toList();
      });
    }).asyncExpand((event) => Stream.fromFuture(event));
  }

  /// Streams real-time updates for a single LPG device document.
  /// This is used by DeviceMonitoringScreen to show live data for a specific device.
  ///
  /// [deviceId]: The ID of the device to stream.
  /// Returns a Stream of [LPGDevice] object for the specified device.
  Stream<LPGDevice> getDeviceStream(String deviceId) {
    return _db.collection('devices').doc(deviceId).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return LPGDevice.fromMap(snapshot.id, snapshot.data()!);
      } else {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          message: 'Device document not found or deleted: $deviceId',
          code: 'device-not-found',
        );
      }
    });
  }

  /// Deletes a specific LPG device document and removes its ID from the user's profile.
  /// Also deletes the associated history subcollection.
  ///
  /// [userId]: The Firebase UID of the user.
  /// [deviceId]: The ID of the device to delete.
  Future<void> deleteDevice(String userId, String deviceId) async {
    // 1. Remove deviceId from the user's document 'devices' array
    final userDocRef = _db.collection('users').doc(userId);
    await userDocRef.update({
      'devices': FieldValue.arrayRemove([deviceId]),
    });

    // 2. Delete the history subcollection (requires batch deletion for many documents)
    final historyCollectionRef = _db.collection('devices').doc(deviceId).collection('history');
    final historySnapshot = await historyCollectionRef.get();
    for (DocumentSnapshot doc in historySnapshot.docs) {
      await doc.reference.delete(); // Delete each history document
    }

    // 3. Delete the main device document
    final deviceDocRef = _db.collection('devices').doc(deviceId);
    await deviceDocRef.delete();
  }

  /// Updates the default empty and full cylinder weights in the user's profile.
  Future<void> updateDefaultCylinderWeights(String userId, double emptyWeight, double fullWeight) async {
    final userDocRef = _db.collection('users').doc(userId);
    await userDocRef.update({
      'defaultCylinderEmptyWeight': emptyWeight,
      'defaultCylinderFullWeight': fullWeight,
    });
  }

  /// Fetches historical weight data for a given device within a date range.
  Future<List<Map<String, dynamic>>> getDeviceHistory(String deviceId, DateTime startDate, DateTime endDate) async {
    final historyCollectionRef = _db.collection('devices').doc(deviceId).collection('history');
    final querySnapshot = await historyCollectionRef
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1))))
        .orderBy('timestamp', descending: true)
        .get();

    return querySnapshot.docs.map((doc) => doc.data()).toList();
  }
}