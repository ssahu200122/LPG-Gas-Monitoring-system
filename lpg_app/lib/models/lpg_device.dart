// lib/models/lpg_device.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class LPGDevice {
  final String id;
  final String name;
  final String ownerId;
  final double emptyWeight;
  final double fullWeight;
  final double currentWeightGrams;
  final Timestamp? timestamp;
  final Timestamp? createdAt;

  LPGDevice({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.emptyWeight,
    required this.fullWeight,
    required this.currentWeightGrams,
    this.timestamp,
    this.createdAt,
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
      timestamp: data['timestamp'] as Timestamp?,
      createdAt: data['createdAt'] as Timestamp?,
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
      'createdAt': createdAt,
    };
  }

  // NEW: Override equality (==) and hashCode for proper object comparison, especially in DropdownButton
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true; // If they are the exact same instance

    // Check if 'other' is an LPGDevice and if their 'id's are equal
    return other is LPGDevice &&
           other.id == id;
  }

  @override
  int get hashCode => id.hashCode; // Hash code based on the unique 'id'
}