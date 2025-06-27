// lib/models/lpg_device.dart
import 'package:cloud_firestore/cloud_firestore.dart'; // Ensure this is imported for Timestamp

class LPGDevice {
  final String id;
  final String name;
  final String ownerId;
  final double emptyWeight;
  final double fullWeight;
  final double currentWeightGrams;
  final Timestamp? timestamp; // Last updated timestamp
  final Timestamp? createdAt; // NEW: Timestamp for when the device was added

  LPGDevice({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.emptyWeight,
    required this.fullWeight,
    required this.currentWeightGrams,
    this.timestamp,
    this.createdAt, // Ensure this is in the constructor
  });

  // Factory constructor to create an LPGDevice instance from a Firestore map
  factory LPGDevice.fromMap(String id, Map<String, dynamic> data) {
    return LPGDevice(
      id: id,
      name: data['name'] as String? ?? 'Unknown Device',
      ownerId: data['ownerId'] as String? ?? '',
      emptyWeight: (data['emptyWeight'] as num?)?.toDouble() ?? 0.0,
      fullWeight: (data['fullWeight'] as num?)?.toDouble() ?? 0.0,
      currentWeightGrams: (data['current_weight_grams'] as num?)?.toDouble() ?? 0.0,
      timestamp: data['timestamp'] as Timestamp?, // Correctly cast as Timestamp?
      createdAt: data['createdAt'] as Timestamp?, // Ensure createdAt is parsed here
    );
  }

  // Method to convert an LPGDevice instance to a map (useful for updating Firestore)
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ownerId': ownerId,
      'emptyWeight': emptyWeight,
      'fullWeight': fullWeight,
      'current_weight_grams': currentWeightGrams,
      'timestamp': timestamp,
      'createdAt': createdAt, // Ensure createdAt is included here
    };
  }
}