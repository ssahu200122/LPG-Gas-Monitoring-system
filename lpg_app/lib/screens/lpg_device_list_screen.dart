import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // For DocumentSnapshot and Timestamp
import 'package:provider/provider.dart'; // For Provider.of

import 'package:lpg_app/services/auth_service.dart';
import 'package:lpg_app/services/firestore_service.dart';
import 'package:lpg_app/models/lpg_device.dart';
import 'package:lpg_app/screens/add_device_screen.dart'; // Screen to add new device
import 'package:lpg_app/screens/device_monitoring_screen.dart'; // Screen to monitor a specific device
import 'package:lpg_app/screens/settings_screen.dart'; // Settings screen
import 'package:lpg_app/screens/auth_screen.dart'; // Import AuthScreen for navigation after logout

class LPGDeviceListScreen extends StatefulWidget {
  const LPGDeviceListScreen({super.key});

  @override
  State<LPGDeviceListScreen> createState() => _LPGDeviceListScreenState();
}

class _LPGDeviceListScreenState extends State<LPGDeviceListScreen> {
  // Lazily initialized services, accessed via Provider.of.
  late final AuthService _authService;
  late final FirestoreService _firestoreService;
  User? _currentUser; // Holds the currently logged-in Firebase user.

  @override
  void initState() {
    super.initState();
    // Initialize services from the Provider. `listen: false` as we only need the instance.
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    
    // Get the current authenticated user. This should not be null if navigated correctly from main.dart.
    _currentUser = _authService.getCurrentUser();
  }

  /// Calculates the gas percentage based on current, empty, and full weights.
  /// Ensures the percentage is clamped between 0 and 100 to avoid invalid values.
  ///
  /// [currentWeightGrams]: The current weight of the cylinder (LPG + cylinder).
  /// [emptyWeight]: The weight of the empty cylinder.
  /// [fullWeight]: The weight of the full cylinder (LPG + cylinder).
  /// Returns the gas percentage as a double.
  double _calculateGasPercentage(double currentWeightGrams, double emptyWeight, double fullWeight) {
    // Calculate the actual weight of the LPG gas.
    final double actualGasWeight = currentWeightGrams - emptyWeight;
    // Calculate the total capacity of the gas in the cylinder.
    final double gasCapacity = fullWeight - emptyWeight;

    // Handle edge cases to prevent division by zero or negative percentages.
    if (gasCapacity <= 0) return 0.0; // If capacity is non-positive, assume 0%
    if (actualGasWeight <= 0) return 0.0; // If no gas or negative weight, assume 0%

    // Calculate percentage and clamp it between 0 and 100.
    double percentage = (actualGasWeight / gasCapacity) * 100;
    return percentage.clamp(0.0, 100.0);
  }

  /// Determines the color of the gas level indicator based on the calculated percentage.
  ///
  /// [percentage]: The gas percentage (0-100).
  /// Returns a [Color] indicating the gas level (Green for high, Orange for medium, Red for low).
  Color _getGasLevelColor(double percentage) {
    if (percentage > 75) {
      return Colors.green.shade600; // High level
    } else if (percentage > 50) {
      return Colors.lightGreen.shade400; // Medium-high level
    } else if (percentage > 25) {
      return Colors.orange.shade600; // Medium-low level
    } else {
      return Colors.red.shade600; // Critically low level
    }
  }

  /// Function to display a confirmation dialog before deleting a device.
  /// If confirmed, it calls the FirestoreService to delete the device and its history.
  ///
  /// [context]: The BuildContext for showing the dialog and SnackBar.
  /// [device]: The [LPGDevice] object to be deleted.
  /// [userId]: The Firebase UID of the user who owns the device.
  Future<void> _confirmAndDeleteDevice(BuildContext context, LPGDevice device, String userId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Device?'),
          content: Text('Are you sure you want to delete "${device.name}"?\nThis action cannot be undone and will permanently remove all historical data.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false), // User cancels
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red), // Red delete button
              onPressed: () => Navigator.of(context).pop(true), // User confirms
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      // User confirmed deletion, proceed with deletion.
      try {
        await _firestoreService.deleteDevice(userId, device.id); // Call FirestoreService to delete
        if (context.mounted) { // Check if widget is still in tree before showing SnackBar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Device "${device.name}" deleted successfully!')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete device: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Defensive check: If current user is null, this screen should not be displayed.
    if (_currentUser == null) {
      // If for some reason currentUser is null here, navigate to AuthScreen
      // This can happen if the user logs out from another part of the app or their session expires.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const AuthScreen()),
          );
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()), // Show loading while redirecting
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My LPG Devices'),
        centerTitle: true,
        actions: [
          // Settings button in the AppBar.
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          // Logout button in the AppBar.
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.signOut(); // Call AuthService to sign out.
              // IMPORTANT: Navigate immediately after signing out.
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        // Stream the current user's profile document from Firestore.
        // This allows the device list to update in real-time if devices are added/removed from the user's profile.
        stream: _firestoreService.getUserProfileStream(_currentUser!.uid),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            // Show a loading indicator while fetching user profile.
            return const Center(child: CircularProgressIndicator());
          }
          if (userSnapshot.hasError) {
            // Display an error if fetching user profile fails.
            // This might be the permission-denied error if the user somehow logged out
            // without being redirected.
            return Center(child: Text('Error: ${userSnapshot.error}'));
          }
          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            // If user profile doesn't exist, this indicates a data inconsistency; prompt re-login.
            // Or if user data becomes null after logout, this will catch it.
            // We should still redirect to AuthScreen.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                );
              }
            });
            return const Center(
              child: Text(
                'User profile not found or session ended. Redirecting...',
                textAlign: TextAlign.center,
              ),
            );
          }

          final userData = userSnapshot.data!.data();
          // Extract the list of device IDs from the user's profile, defaulting to an empty list if null.
          final List<dynamic> deviceIds = userData?['devices'] ?? [];

          if (deviceIds.isEmpty) {
            // Display a friendly message if no devices are linked to the user's account.
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.devices_other, size: 80, color: Colors.teal.shade300),
                  const SizedBox(height: 20),
                  Text(
                    'No LPG devices linked yet!',
                    style: TextStyle(fontSize: 20, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Tap the "+" button below to add your first device.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // If there are device IDs, fetch the detailed data for each device.
          // `FutureBuilder` is used here because `getDevicesByIds` returns a Future (single fetch).
          // Real-time updates for *individual device sensor data* will be handled on the `DeviceMonitoringScreen`.
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _firestoreService.getDevicesByIds(deviceIds),
            builder: (context, devicesFutureSnapshot) {
              if (devicesFutureSnapshot.connectionState == ConnectionState.waiting) {
                // Show a loading indicator while fetching device details.
                return const Center(child: CircularProgressIndicator());
              }
              if (devicesFutureSnapshot.hasError) {
                // Display an error if loading device details fails.
                return Center(child: Text('Error loading devices: ${devicesFutureSnapshot.error}'));
              }
              if (!devicesFutureSnapshot.hasData || devicesFutureSnapshot.data!.isEmpty) {
                // This case handles if deviceIds exist in user profile but actual device documents are missing.
                return const Center(child: Text('No device data found for linked IDs.'));
              }

              final List<Map<String, dynamic>> devices = devicesFutureSnapshot.data!;

              return ListView.builder(
                padding: const EdgeInsets.all(16.0), // Padding around the list
                itemCount: devices.length, // Number of devices to display
                itemBuilder: (context, index) {
                  final deviceData = devices[index]; // Raw data map for the device
                  final String deviceId = deviceIds[index].toString(); // Get the actual device ID from the user's list
                  
                  // Extract and cast device properties with null-checks and defaults.
                  final String name = deviceData['name'] ?? 'Unnamed Device';
                  final double currentWeightGrams = (deviceData['current_weight_grams'] ?? 0.0).toDouble();
                  final double emptyWeight = (deviceData['emptyWeight'] ?? 14500.0).toDouble(); // Default empty weight
                  final double fullWeight = (deviceData['fullWeight'] ?? 28700.0).toDouble(); // Default full weight
                  final Timestamp? timestamp = deviceData['timestamp'] as Timestamp?; // Last update timestamp

                  // Calculate gas percentage using the helper method.
                  final double gasPercentage = _calculateGasPercentage(currentWeightGrams, emptyWeight, fullWeight);
                  // Get appropriate color for the gas level.
                  final Color gasLevelColor = _getGasLevelColor(gasPercentage);
                  // Calculate remaining LPG in grams, clamped to 0 (no negative values).
                  double gasRemainingGrams = (currentWeightGrams - emptyWeight).clamp(0.0, double.infinity);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8.0), // Margin between cards
                    elevation: 6, // Card shadow
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // Rounded corners
                    child: InkWell( // Makes the card tappable with a ripple effect
                      onTap: () {
                        // Navigate to the DeviceMonitoringScreen for detailed view.
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => DeviceMonitoringScreen(
                              deviceId: deviceId,
                              deviceName: name,
                              emptyWeight: emptyWeight,
                              fullWeight: fullWeight,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(15), // Match Card's border radius
                      child: Padding(
                        padding: const EdgeInsets.all(16.0), // Inner padding for the card content
                        child: Row(
                          children: [
                            // Icon representing the gas tank, colored by level.
                            Icon(Icons.propane_tank, size: 40, color: gasLevelColor),
                            const SizedBox(width: 16), // Spacer
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, // Align text to the start
                                children: [
                                  // Device friendly name.
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal,
                                    ),
                                  ),
                                  // Device ID for debugging/reference.
                                  Text(
                                    'ID: $deviceId',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 8), // Spacer
                                  // Linear progress indicator for gas level.
                                  LinearProgressIndicator(
                                    value: gasPercentage / 100, // Value between 0.0 and 1.0 for progress bar
                                    backgroundColor: Colors.grey[300], // Background of the bar
                                    valueColor: AlwaysStoppedAnimation<Color>(gasLevelColor), // Color of the progress
                                    minHeight: 10, // Height of the bar
                                    borderRadius: BorderRadius.circular(5), // Rounded corners for the bar
                                  ),
                                  const SizedBox(height: 8), // Spacer
                                  // Display gas percentage and current remaining LPG in kg.
                                  Text(
                                    '${gasPercentage.toStringAsFixed(1)}% (${(gasRemainingGrams / 1000).toStringAsFixed(2)} kg remaining)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: gasLevelColor,
                                    ),
                                  ),
                                  // Display last updated timestamp if available.
                                  if (timestamp != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        'Last updated: ${timestamp.toDate().toLocal().toString().split('.')[0]}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Delete button (IconButton for device deletion).
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.grey),
                              onPressed: () {
                                // Call confirmation dialog for deletion.
                                _confirmAndDeleteDevice(
                                  context,
                                  LPGDevice.fromMap(deviceId, deviceData), // Pass LPGDevice object
                                  _currentUser!.uid, // Pass current user's UID
                                );
                              },
                            ),
                            // Navigation arrow.
                            const Icon(Icons.arrow_forward_ios, size: 20, color: Colors.grey),
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
          // Navigate to the AddDeviceScreen when the FAB is pressed.
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const AddDeviceScreen()),
          );
        },
        backgroundColor: Colors.teal, // FAB background color
        child: const Icon(Icons.add, color: Colors.white), // Add icon
      ),
    );
  }
}
