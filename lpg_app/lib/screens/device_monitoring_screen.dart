import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lpg_app/models/lpg_device.dart';
import 'package:lpg_app/services/firestore_service.dart';
import 'package:lpg_app/screens/history_screen.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Ensure Timestamp is recognized

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

  /// Calculates the gas percentage.
  double _calculateGasPercentage(double currentWeightGrams, double emptyWeight, double fullWeight) {
    currentWeightGrams = currentWeightGrams.clamp(0.0, double.infinity);
    emptyWeight = emptyWeight.clamp(0.0, double.infinity);
    fullWeight = fullWeight.clamp(0.0, double.infinity);

    final double actualGasWeight = currentWeightGrams - emptyWeight;
    final double gasCapacity = fullWeight - emptyWeight;

    if (gasCapacity <= 0) return 0.0;
    if (actualGasWeight <= 0) return 0.0;

    double percentage = (actualGasWeight / gasCapacity) * 100;
    return percentage.clamp(0.0, 100.0);
  }

  /// Calculates the estimated days remaining.
  String _getDaysRemainingString(LPGDevice device) {
    final double gasRemainingInCylinder = (device.currentWeightGrams - device.emptyWeight).clamp(0.0, double.infinity);
    final double avgDailyConsumptionApproximation = 500.0;

    if (gasRemainingInCylinder <= 0) return 'Empty';
    if (avgDailyConsumptionApproximation <= 0) return 'N/A (No consumption data)';

    final double estimatedDays = gasRemainingInCylinder / avgDailyConsumptionApproximation;
    if (estimatedDays < 1.0) {
      return '${(estimatedDays * 24).toStringAsFixed(0)} hours';
    } else {
      return '${estimatedDays.toStringAsFixed(0)} days';
    }
  }

  /// Determines the color of the gas level indicator based on the calculated percentage.
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

  /// Helper function to safely format a Timestamp or DateTime to a local string.
  String _formatTimestampForDisplay(dynamic dateInput, {String format = 'MMM dd, yyyy - HH:mm'}) {
    DateTime? dateTime;
    if (dateInput is Timestamp) {
      dateTime = dateInput.toDate();
    } else if (dateInput is DateTime) {
      dateTime = dateInput;
    }

    if (dateTime != null) {
      return DateFormat(format).format(dateTime.toLocal());
    }
    return 'N/A';
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
      body: StreamBuilder<LPGDevice>(
        stream: _firestoreService.getDeviceStream(widget.deviceId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Device data not found.'));
          }

          final LPGDevice device = snapshot.data!;
          final double gasPercentage = _calculateGasPercentage(
            device.currentWeightGrams,
            device.emptyWeight,
            device.fullWeight,
          );
          
          final double currentWeightKg = (device.currentWeightGrams / 1000).clamp(0.0, double.infinity);
          final String daysRemaining = _getDaysRemainingString(device);
          final Color gasLevelColor = _getGasLevelColor(gasPercentage);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                CircularPercentIndicator(
                  radius: 120.0,
                  lineWidth: 18.0,
                  percent: gasPercentage / 100.0,
                  center: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.propane_tank,
                        size: 70.0,
                        color: gasLevelColor,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${gasPercentage.toStringAsFixed(1)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 30.0),
                      ),
                    ],
                  ),
                  footer: Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Text(
                      'Gas Level for ${device.name}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.teal.shade800,
                      ),
                    ),
                  ),
                  backgroundColor: Colors.grey.shade300,
                  progressColor: gasLevelColor,
                  circularStrokeCap: CircularStrokeCap.round,
                ),
                const SizedBox(height: 30),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.symmetric(horizontal: 16.0),
                  color: Colors.teal.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(Icons.scale, color: Colors.teal.shade700, size: 30),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Text(
                            'Current Weight: ${currentWeightKg.toStringAsFixed(2)} kg',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.symmetric(horizontal: 16.0),
                  color: Colors.teal.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.teal.shade700, size: 30),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Text(
                            'Estimated Days Remaining: $daysRemaining',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  // Using the new helper for Last Updated
                  'Last Updated: ${_formatTimestampForDisplay(device.timestamp, format: 'MMM dd, yyyy - HH:mm:ss')}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                
                // Device Details Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.symmetric(horizontal: 16.0),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.teal.shade700, size: 30),
                            const SizedBox(width: 10),
                            Text(
                              'Device Details',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade900,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20, thickness: 1, color: Colors.grey),
                        _buildDetailRow('Device Name:', device.name),
                        _buildDetailRow('Device ID:', device.id),
                        _buildDetailRow('Owner ID:', device.ownerId),
                        _buildDetailRow('Empty Weight:', '${(device.emptyWeight / 1000).toStringAsFixed(2)} kg'),
                        _buildDetailRow('Full Weight:', '${(device.fullWeight / 1000).toStringAsFixed(2)} kg'),
                        // Using the new helper for Added On
                        _buildDetailRow('Added On:', _formatTimestampForDisplay(device.createdAt)),
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

  /// Helper widget to build a row for device details.
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120, // Fixed width for labels
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black54,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}