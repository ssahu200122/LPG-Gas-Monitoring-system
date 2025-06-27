import 'package:cloud_firestore/cloud_firestore.dart'; // Required for Timestamp type in fromMap

class LPGDevice {
  final String id;
  final String name;
  final String ownerId; // Owner's Firebase UID
  final double emptyWeight; // grams
  final double fullWeight; // grams
  final double currentWeightGrams; // Last reported weight in grams
  final DateTime? timestamp; // Last updated timestamp, converted to DateTime

  LPGDevice({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.emptyWeight,
    required this.fullWeight,
    required this.currentWeightGrams,
    this.timestamp,
  });

  /// Factory constructor to create an LPGDevice instance from a Firestore DocumentSnapshot data map.
  factory LPGDevice.fromMap(String id, Map<String, dynamic> data) {
    return LPGDevice(
      id: id,
      name: data['name'] ?? 'Unnamed Device',
      ownerId: data['ownerId'] ?? '',
      emptyWeight: (data['emptyWeight'] ?? 0.0).toDouble(),
      fullWeight: (data['fullWeight'] ?? 0.0).toDouble(),
      currentWeightGrams: (data['current_weight_grams'] ?? 0.0).toDouble(),
      // Convert Firestore Timestamp to Dart DateTime
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(), 
    );
  }

  /// Converts the LPGDevice instance to a map for Firestore storage.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ownerId': ownerId,
      'emptyWeight': emptyWeight,
      'fullWeight': fullWeight,
      'current_weight_grams': currentWeightGrams,
      // Store DateTime as Firestore Timestamp
      'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : FieldValue.serverTimestamp(), 
    };
  }
}