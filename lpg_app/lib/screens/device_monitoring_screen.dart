import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // For DocumentSnapshot
import 'package:intl/intl.dart'; // For date formatting

import 'package:lpg_app/services/firestore_service.dart';
import 'package:lpg_app/models/lpg_device.dart'; // Import LPGDevice model
import 'package:lpg_app/screens/history_screen.dart'; // Import HistoryScreen

class DeviceMonitoringScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  final double emptyWeight;
  final double fullWeight;

  const DeviceMonitoringScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.emptyWeight,
    required this.fullWeight,
  });

  @override
  State<DeviceMonitoringScreen> createState() => _DeviceMonitoringScreenState();
}

class _DeviceMonitoringScreenState extends State<DeviceMonitoringScreen> {
  late final FirestoreService _firestoreService;

  @override
  void initState() {
    super.initState();
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
  }

  /// Calculates the gas percentage based on current, empty, and full weights.
  /// Ensures the percentage is clamped between 0 and 100 to avoid invalid values.
  ///
  /// [currentWeightGrams]: The current weight of the cylinder (LPG + cylinder).
  /// [emptyWeight]: The weight of the empty cylinder.
  /// [fullWeight]: The weight of the full cylinder (LPG + cylinder).
  /// Returns the gas percentage as a double.
  double _calculateGasPercentage(double currentWeightGrams, double emptyWeight, double fullWeight) {
    final double actualGasWeight = currentWeightGrams - emptyWeight;
    final double gasCapacity = fullWeight - emptyWeight;

    if (gasCapacity <= 0) return 0.0;
    if (actualGasWeight <= 0) return 0.0;

    double percentage = (actualGasWeight / gasCapacity) * 100;
    return percentage.clamp(0.0, 100.0);
  }

  /// Determines the color of the gas level indicator based on the calculated percentage.
  ///
  /// [percentage]: The gas percentage (0-100).
  /// Returns a [Color] indicating the gas level.
  Color _getGasLevelColor(double percentage) {
    if (percentage > 75) {
      return Colors.green.shade600;
    } else if (percentage > 50) {
      return Colors.lightGreen.shade400;
    } else if (percentage > 25) {
      return Colors.orange.shade600;
    } else {
      return Colors.red.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deviceName),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => HistoryScreen(
                    deviceId: widget.deviceId,
                    deviceName: widget.deviceName,
                    emptyWeight: widget.emptyWeight,
                    fullWeight: widget.fullWeight,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<LPGDevice>( // Changed from DocumentSnapshot to LPGDevice
        stream: _firestoreService.getDeviceStream(widget.deviceId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            // Handle error, e.g., if the device document was not found
            return Center(child: Text('Error: ${snapshot.error}. Device may have been deleted.'));
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('No data for this device.'));
          }

          final LPGDevice device = snapshot.data!; // Now directly an LPGDevice object

          // Use device's properties
          final double currentWeightGrams = device.currentWeightGrams;
          final double emptyWeight = device.emptyWeight;
          final double fullWeight = device.fullWeight;
          // FIXED: timestamp is already DateTime? from the model
          final DateTime? lastUpdatedTimestamp = device.timestamp; 

          final double gasPercentage = _calculateGasPercentage(currentWeightGrams, emptyWeight, fullWeight);
          final Color gasLevelColor = _getGasLevelColor(gasPercentage);
          double gasRemainingGrams = (currentWeightGrams - emptyWeight).clamp(0.0, double.infinity);

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.propane_tank,
                          size: 150,
                          color: gasLevelColor,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '${gasPercentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: gasLevelColor,
                          ),
                        ),
                        Text(
                          '${(gasRemainingGrams / 1000).toStringAsFixed(2)} kg remaining',
                          style: TextStyle(
                            fontSize: 22,
                            color: gasLevelColor.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Display last updated timestamp
                        if (lastUpdatedTimestamp != null)
                          Text(
                            'Last updated: ${DateFormat('MMM dd, yyyy - HH:mm:ss').format(lastUpdatedTimestamp.toLocal())}',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          )
                        else
                          Text(
                            'Last updated: N/A', // Fallback if timestamp is null
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device Details:',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildDetailRow('Device Name:', device.name),
                        _buildDetailRow('Device ID:', device.id),
                        _buildDetailRow('Empty Weight:', '${(device.emptyWeight / 1000).toStringAsFixed(2)} kg'),
                        _buildDetailRow('Full Weight:', '${(device.fullWeight / 1000).toStringAsFixed(2)} kg'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}