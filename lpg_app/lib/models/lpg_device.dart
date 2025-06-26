import 'package:cloud_firestore/cloud_firestore.dart';

// Represents an LPG device with its properties and current status.
class LPGDevice {
  final String id; // The unique ID of the device (typically ESP32 MAC address/Firestore Document ID)
  final String name; // A user-friendly name for the device
  final double emptyWeight; // Weight of the empty LPG cylinder in grams
  final double fullWeight; // Weight of the full LPG cylinder in grams
  final double currentWeightGrams; // Current weight reading from the load cell in grams
  final DateTime timestamp; // Timestamp of the last weight update

  // Constructor for the LPGDevice class. All fields are required.
  LPGDevice({
    required this.id,
    required this.name,
    required this.emptyWeight,
    required this.fullWeight,
    required this.currentWeightGrams,
    required this.timestamp,
  });

  /// Factory constructor to create an [LPGDevice] instance from a Firestore data map
  /// and the document ID.
  /// This is the primary way to deserialize device data coming from Firestore.
  ///
  /// [id]: The unique document ID (String) from Firestore.
  /// [data]: The map containing the document's fields (Map<String, dynamic>).
  factory LPGDevice.fromMap(String id, Map<String, dynamic> data) {
    return LPGDevice(
      id: id, // Assign the document ID passed separately
      name: data['name'] ?? 'Unnamed Device', // Provide a default if 'name' is null or missing
      emptyWeight: (data['emptyWeight'] ?? 0.0).toDouble(), // Convert to double, default 0.0
      fullWeight: (data['fullWeight'] ?? 0.0).toDouble(), // Convert to double, default 0.0
      currentWeightGrams: (data['current_weight_grams'] ?? 0.0).toDouble(), // Convert to double, default 0.0
      // Cast Firestore Timestamp to a Dart DateTime object.
      // It's safe to use `as Timestamp` because Firestore ensures 'timestamp' is a Timestamp.
      timestamp: (data['timestamp'] as Timestamp).toDate(), 
    );
  }

  /// Converts an [LPGDevice] object into a [Map<String, dynamic>]
  /// suitable for writing to Firestore.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'emptyWeight': emptyWeight,
      'fullWeight': fullWeight,
      'current_weight_grams': currentWeightGrams,
      // Convert Dart DateTime to Firestore Timestamp for storage.
      'timestamp': Timestamp.fromDate(timestamp), 
    };
  }
}
