import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'package:lpg_app/models/lpg_device.dart';
import 'package:lpg_app/screens/device_monitoring_screen.dart';
import 'package:lpg_app/screens/settings_screen.dart';
import 'package:lpg_app/services/auth_service.dart';
import 'package:lpg_app/services/firestore_service.dart';
import 'package:lpg_app/services/notification_service.dart';
import 'package:lpg_app/screens/add_device_screen.dart';

class LPGDeviceListScreen extends StatefulWidget {
  const LPGDeviceListScreen({super.key});

  @override
  State<LPGDeviceListScreen> createState() => _LPGDeviceListScreenState();
}

class _LPGDeviceListScreenState extends State<LPGDeviceListScreen> {
  late final AuthService _authService;
  late final FirestoreService _firestoreService;
  late final NotificationService _notificationService;
  User? _currentUser;

  double _userLowGasThreshold = 20.0;
  Map<String, bool> _notifiedDevices = {};

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _notificationService = Provider.of<NotificationService>(context, listen: false);
    _currentUser = _authService.getCurrentUser();

    if (_currentUser == null) {
      debugPrint('LPGDeviceListScreen initialized with null user. This might indicate a routing issue.');
      return;
    }

    _listenForUserProfileChanges();
  }

  /// Listens for real-time updates to the user's profile to get the latest low gas threshold.
  void _listenForUserProfileChanges() {
    _firestoreService.getUserProfileStream(_currentUser!.uid).listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final userData = snapshot.data()!;
        setState(() {
          _userLowGasThreshold = (userData['lowGasThresholdPercent'] as num?)?.toDouble() ?? 20.0;
        });
        debugPrint('User low gas threshold updated to: $_userLowGasThreshold%');
      } else {
        debugPrint('User profile snapshot data is null or does not exist.');
      }
    });
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

  /// Checks if a device is low on gas and triggers a notification if needed.
  /// Prevents spamming notifications for the same low-gas event.
  void _checkAndNotifyLowGas(LPGDevice device) async {
    final double gasPercentage = _calculateGasPercentage(
      device.currentWeightGrams,
      device.emptyWeight,
      device.fullWeight,
    );

    final String notificationId = 'low_gas_${device.id}'; // Unique ID for each device's notification

    if (gasPercentage <= _userLowGasThreshold) {
      if (!(_notifiedDevices[notificationId] ?? false)) { // If not already notified for this low state
        debugPrint('Gas level for ${device.name} is ${gasPercentage.toStringAsFixed(1)}%, which is below $_userLowGasThreshold%. Sending notification.');
        await _notificationService.showNotification(
          id: device.id.hashCode, // Use device ID's hash code for unique notification ID
          title: 'Low Gas Alert: ${device.name}',
          body: 'Your LPG cylinder for ${device.name} is at ${gasPercentage.toStringAsFixed(1)}%.'
                ' Estimated ${_getDaysRemainingString(device)} remaining.', // Add days remaining to body
        );
        setState(() {
          _notifiedDevices[notificationId] = true; // Mark as notified
        });
      }
    } else {
      // If gas level is above threshold, clear notification state for this device
      if (_notifiedDevices[notificationId] ?? false) {
        debugPrint('Gas level for ${device.name} is ${gasPercentage.toStringAsFixed(1)}%, which is above $_userLowGasThreshold%. Cancelling notification state.');
        await _notificationService.cancelNotification(device.id.hashCode); // Cancel active notification if applicable
        setState(() {
          _notifiedDevices[notificationId] = false; // Reset notified state
        });
      }
    }
  }

  /// Helper to get the days remaining string for notification body.
  String _getDaysRemainingString(LPGDevice device) {
      final double gasRemainingInCylinder = (device.currentWeightGrams - device.emptyWeight).clamp(0.0, double.infinity);
      final double avgDailyConsumptionApproximation = 500; // Example: 500 grams/day if no historical average is directly accessible here

      if (gasRemainingInCylinder <= 0) return 'Empty';
      if (avgDailyConsumptionApproximation <= 0) return 'N/A (No consumption data)';

      final double estimatedDays = gasRemainingInCylinder / avgDailyConsumptionApproximation;
      if (estimatedDays < 1.0) {
        return '${(estimatedDays * 24).toStringAsFixed(0)} hours';
      } else {
        return '${estimatedDays.toStringAsFixed(0)} days';
      }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My LPG Devices'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _firestoreService.getUserProfileStream(_currentUser!.uid),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (userSnapshot.hasError) {
            return Center(child: Text('Error loading user profile: ${userSnapshot.error}'));
          }
          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return const Center(child: Text('User profile not found.'));
          }

          final userDevices = (userSnapshot.data!.data()?['devices'] as List<dynamic>?) ?? [];

          if (userDevices.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.device_hub_outlined, size: 80, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No LPG devices linked yet!\nTap the + button to add one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          return StreamBuilder<List<LPGDevice>>(
            stream: _firestoreService.streamLPGDevices(userDevices),
            builder: (context, deviceListSnapshot) {
              if (deviceListSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (deviceListSnapshot.hasError) {
                return Center(child: Text('Error loading devices: ${deviceListSnapshot.error}'));
              }
              if (!deviceListSnapshot.hasData || deviceListSnapshot.data!.isEmpty) {
                return const Center(child: Text('No device data available.'));
              }

              final devices = deviceListSnapshot.data!;

              WidgetsBinding.instance.addPostFrameCallback((_) {
                 for (var device in devices) {
                   _checkAndNotifyLowGas(device);
                 }
              });
             
              return ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  final double gasPercentage = _calculateGasPercentage(
                    device.currentWeightGrams,
                    device.emptyWeight,
                    device.fullWeight,
                  );
                  final Color gasLevelColor = _getGasLevelColor(gasPercentage);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    elevation: 5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => DeviceMonitoringScreen(
                              deviceId: device.id,
                              deviceName: device.name,
                              emptyWeight: device.emptyWeight,
                              fullWeight: device.fullWeight,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(Icons.propane_tank, size: 40, color: gasLevelColor),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device.name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Current Weight: ${(device.currentWeightGrams / 1000).toStringAsFixed(2)} kg',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    // FIXED: Corrected DateFormat pattern to use 'yyyy'
                                    'Last Updated: ${device.timestamp != null ? DateFormat('MMM dd, yyyy - HH:mm').format(device.timestamp!.toDate().toLocal()) : 'N/A'}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.grey),
                              onPressed: () => _confirmDeleteDevice(context, device),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const AddDeviceScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
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

  /// Shows a dialog to confirm device deletion.
  void _confirmDeleteDevice(BuildContext context, LPGDevice device) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Device'),
          content: Text('Are you sure you want to delete "${device.name}"? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog
                if (_currentUser != null) {
                  try {
                    await _firestoreService.deleteDevice(_currentUser!.uid, device.id);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${device.name} deleted successfully!')),
                      );
                    }
                    // Cancel any pending low gas notification for this device
                    await _notificationService.cancelNotification(device.id.hashCode);
                    // Remove from notified devices map
                    _notifiedDevices.remove('low_gas_${device.id}');
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to delete ${device.name}: ${e.toString()}')),
                      );
                    }
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
}