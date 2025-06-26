import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lpg_device.dart'; // Import the LPGDevice model

// Service class for handling all Firestore database operations related to the LPG app.
class FirestoreService {
  // Obtain an instance of the FirebaseFirestore database.
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Private constructor to enforce singleton pattern or allow const instantiation.
   FirestoreService();

  /// Links a new LPG device to a specific user in Firestore.
  /// This involves:
  /// 1. Creating/updating a document in the 'devices' collection with device details.
  /// 2. Adding the device ID to the 'devices' array in the user's profile document.
  ///
  /// [userId]: The Firebase UID of the current user.
  /// [deviceId]: The unique ID of the ESP32 device (e.g., its MAC address).
  /// [name]: A user-friendly name for the device.
  /// [emptyWeight]: The empty weight of the LPG cylinder in grams.
  /// [fullWeight]: The full weight of the LPG cylinder in grams.
  Future<void> linkDeviceToUser(String userId, String deviceId, String name, double emptyWeight, double fullWeight) async {
    // Reference to the specific device document in the 'devices' collection.
    DocumentReference deviceRef = _db.collection('devices').doc(deviceId);
    // Reference to the user's profile document in the 'users' collection.
    DocumentReference userRef = _db.collection('users').doc(userId);

    // Set (or merge) the device data into the 'devices' collection.
    // 'SetOptions(merge: true)' ensures that if the document already exists,
    // only the specified fields are updated, and others are left untouched.
    await deviceRef.set({
      'ownerId': userId, // Link device to the user
      'name': name,
      'emptyWeight': emptyWeight,
      'fullWeight': fullWeight,
      'current_weight_grams': 0.0, // Initialize current weight to 0.0
      'timestamp': FieldValue.serverTimestamp(), // Set server timestamp for creation
    }, SetOptions(merge: true));

    // Atomically add the deviceId to the 'devices' array in the user's document.
    // 'FieldValue.arrayUnion' adds the element only if it's not already present.
    await userRef.update({
      'devices': FieldValue.arrayUnion([deviceId]),
    });
  }

  /// Provides a real-time stream of [LPGDevice] objects associated with a specific user.
  /// This listens for changes in the 'devices' collection where 'ownerId' matches the [userId].
  ///
  /// [userId]: The Firebase UID of the current user.
  /// Returns a [Stream] of a [List] of [LPGDevice] objects.
  Stream<List<LPGDevice>> getLPGDevicesStreamForUser(String userId) {
    return _db
        .collection('devices')
        .where('ownerId', isEqualTo: userId) // Filter devices by the current user's ID
        .snapshots() // Get real-time updates as a stream of QuerySnapshot
        .map((snapshot) => snapshot.docs // Map each QueryDocumentSnapshot
            .map((doc) => LPGDevice.fromMap(doc.id, doc.data())) // Convert to LPGDevice using fromMap
            .toList()); // Convert the iterable to a List
  }

  /// Fetches a single user profile document.
  /// Used for retrieving user-specific settings like default cylinder weights.
  ///
  /// [userId]: The Firebase UID of the user.
  /// Returns a [Future] containing a [Map] of user data, or `null` if not found.
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    DocumentSnapshot doc = await _db.collection('users').doc(userId).get();
    return doc.data() as Map<String, dynamic>?; // Cast to Map<String, dynamic>
  }

  /// Provides a real-time stream for a single [LPGDevice]'s data.
  /// This is useful for a detail screen that focuses on one device.
  ///
  /// [deviceId]: The unique ID of the device to listen to.
  /// Returns a [Stream] of an [LPGDevice] object.
  Stream<LPGDevice> getDeviceStream(String deviceId) {
    return _db.collection('devices').doc(deviceId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        // If the document doesn't exist, throw an exception.
        throw Exception("Device with ID $deviceId does not exist.");
      }
      // Convert the DocumentSnapshot data to an LPGDevice object using fromMap.
      return LPGDevice.fromMap(snapshot.id, snapshot.data()!);
    });
  }

  /// Provides a real-time stream of weight history for a specific device.
  ///
  /// [deviceId]: The unique ID of the device whose history is to be retrieved.
  /// Returns a [Stream] of a [List] of [Map], each containing 'weight_grams' and 'timestamp'.
  Stream<List<Map<String, dynamic>>> getLPGDeviceHistoryStream(String deviceId) {
    return _db
        .collection('devices')
        .doc(deviceId)
        .collection('history') // Access the 'history' sub-collection
        .orderBy('timestamp', descending: true) // Order by latest timestamp first
        .limit(100) // Limit the number of history entries for performance
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
                  Map<String, dynamic> data = doc.data();
                  return {
                    'weight_grams': (data['weight_grams'] ?? 0.0).toDouble(),
                    'timestamp': (data['timestamp'] as Timestamp).toDate(),
                  };
                }).toList());
  }

  /// Deletes a device from Firestore, including its history sub-collection,
  /// and removes its reference from the user's device list.
  ///
  /// This operation is crucial for data cleanliness and privacy.
  /// [userId]: The Firebase UID of the user who owns the device.
  /// [deviceId]: The unique ID of the device to be deleted.
  Future<void> deleteDevice(String userId, String deviceId) async {
    // 1. Delete all documents in the 'history' sub-collection
    // Firestore does not have a single operation to delete a subcollection directly.
    // We must read all documents within the subcollection and delete them individually in a batch.
    CollectionReference historyRef = _db.collection('devices').doc(deviceId).collection('history');
    QuerySnapshot historySnapshot = await historyRef.get();

    WriteBatch batch = _db.batch();
    for (DocumentSnapshot doc in historySnapshot.docs) {
      batch.delete(doc.reference); // Add each history document to the batch for deletion
    }
    await batch.commit(); // Commit the batch operation to delete all history documents

    // 2. Delete the main device document from the 'devices' collection.
    await _db.collection('devices').doc(deviceId).delete();

    // 3. Remove the deviceId from the 'devices' array in the user's profile document.
    // 'FieldValue.arrayRemove' removes all instances of the specified element from the array.
    DocumentReference userRef = _db.collection('users').doc(userId);
    await userRef.update({
      'devices': FieldValue.arrayRemove([deviceId]),
    });
  }

  /// Get historical weight data for a specific device within a date range.
  /// Data is ordered by timestamp descending.
  ///
  /// [deviceId]: The ID of the device.
  /// [startDate]: The start date for the history range (inclusive).
  /// [endDate]: The end date for the history range (inclusive).
  /// Returns a [Future] of a [List] of [Map] where each map represents a history entry.
  Future<List<Map<String, dynamic>>> getDeviceHistory(String deviceId, DateTime startDate, DateTime endDate) async {
    try {
      // Create a timestamp for the start of the start date.
      Timestamp startTimestamp = Timestamp.fromDate(DateTime(startDate.year, startDate.month, startDate.day));
      // Create a timestamp for the end of the end date (just before the next day starts).
      Timestamp endTimestamp = Timestamp.fromDate(DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999));

      QuerySnapshot<Map<String, dynamic>> querySnapshot = await _db
          .collection('devices')
          .doc(deviceId)
          .collection('history')
          .where('timestamp', isGreaterThanOrEqualTo: startTimestamp)
          .where('timestamp', isLessThanOrEqualTo: endTimestamp)
          .orderBy('timestamp', descending: true) // Order to easily calculate usage or display latest first
          .get();

      return querySnapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      throw Exception('Failed to get device history: $e');
    }
  }

  /// Creates a new user profile document in the 'users' collection.
  /// This is called immediately after a user successfully signs up.
  ///
  /// [uid]: The Firebase User ID (UID).
  /// [email]: The user's email address.
  Future<void> createUserProfile(String uid, String email) async {
    try {
      await _db
          .collection('users')
          .doc(uid) // Use the user's unique ID as the document ID
          .set({
            'email': email,
            'devices': [], // Initialize with an empty array of device IDs
            'defaultCylinderEmptyWeight': 14500.0, // Default empty weight for new devices (in grams)
            'defaultCylinderFullWeight': 28700.0,  // Default full weight for new devices (in grams)
            'createdAt': FieldValue.serverTimestamp(), // Use server timestamp for consistency
          });
    } catch (e) {
      throw Exception('Failed to create user profile: $e');
    }
  }

  /// Get a stream of the current user's profile document.
  /// This allows real-time updates to the UI if the user's data (like linked devices) changes.
  ///
  /// [uid]: The Firebase User ID (UID).
  /// Returns a [Stream] of a [DocumentSnapshot] containing the user's profile data.
  Stream<DocumentSnapshot<Map<String, dynamic>>> getUserProfileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  /// Fetches multiple device documents based on a list of device IDs.
  /// This is used by the device list screen to get details for each linked device.
  /// This method performs individual GET requests for each deviceId.
  /// For very large lists of deviceIds, consider using a single query with 'whereIn'
  /// if applicable to your security rules and indexing, or a Cloud Function.
  ///
  /// [deviceIds]: A [List] of device IDs (Strings).
  /// Returns a [Future] of a [List] of [Map] where each map represents a device document's data.
  Future<List<Map<String, dynamic>>> getDevicesByIds(List<dynamic> deviceIds) async {
    if (deviceIds.isEmpty) {
      return [];
    }
    List<Map<String, dynamic>> devicesData = [];
    // Cast deviceIds to String to ensure correct type for doc() method
    for (String deviceId in deviceIds.cast<String>()) {
      DocumentSnapshot<Map<String, dynamic>> doc = await _db.collection('devices').doc(deviceId).get();
      if (doc.exists) {
        devicesData.add(doc.data()!); // Add data if document exists
      }
    }
    return devicesData;
  }
  
  /// Updates the default cylinder weights in the user's profile.
  /// This is used in the SettingsScreen.
  ///
  /// [userId]: The Firebase UID of the current user.
  /// [emptyWeight]: The new default empty weight in grams.
  /// [fullWeight]: The new default full weight in grams.
  Future<void> updateDefaultCylinderWeights(String userId, double emptyWeight, double fullWeight) async {
    await _db.collection('users').doc(userId).update({
      'defaultCylinderEmptyWeight': emptyWeight,
      'defaultCylinderFullWeight': fullWeight,
    });
  }
}
