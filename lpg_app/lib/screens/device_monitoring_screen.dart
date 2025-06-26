import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // Needed for Timestamp type
import 'package:provider/provider.dart'; // For accessing FirestoreService
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // For local notifications
import 'package:permission_handler/permission_handler.dart'; // For requesting notification permissions

import 'package:lpg_app/services/firestore_service.dart'; // Import FirestoreService
import 'package:lpg_app/models/lpg_device.dart'; // Import LPGDevice model
import 'package:lpg_app/screens/history_screen.dart'; // Import the HistoryScreen

// Global instance of the notification plugin.
// It's initialized in main.dart or a similar high-level place.
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class DeviceMonitoringScreen extends StatefulWidget {
  final String deviceId; // The unique ID of the device to monitor
  final String deviceName; // The friendly name of the device
  final double emptyWeight; // Empty weight of the cylinder (grams)
  final double fullWeight; // Full weight of the cylinder (grams)

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
  late final FirestoreService _firestoreService; // Firestore service instance
  
  // State variables for notification logic
  double _lastNotifiedPercentage = 100.0; // Tracks the last percentage at which a notification was sent
  final double _lowGasThreshold = 20.0; // Percentage threshold for triggering low gas notifications

  @override
  void initState() {
    super.initState();
    // Access FirestoreService from the Provider. `listen: false` because we only need the instance.
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    // Initialize local notifications and request necessary permissions.
    _initializeLocalNotifications();
  }

  /// Initializes the flutter_local_notifications plugin and requests necessary permissions
  /// for displaying notifications. Also creates the Android notification channel.
  void _initializeLocalNotifications() async {
    // Request notification permission specifically for Android 13 (API 33) and above.
    if (Theme.of(context).platform == TargetPlatform.android) {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        // If permission is denied, request it from the user.
        final result = await Permission.notification.request();
        if (result.isGranted) {
          debugPrint('Notification permission granted!');
        } else if (result.isDenied) {
          debugPrint('Notification permission denied by user.');
        } else if (result.isPermanentlyDenied) {
          debugPrint('Notification permission permanently denied. Guiding user to settings.');
          // If permission is permanently denied, inform the user and offer to open app settings.
          if (mounted) { // Check if the widget is still mounted before showing UI
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Notification permission denied. Please enable in app settings.'),
                action: SnackBarAction(
                  label: 'Open Settings',
                  onPressed: () {
                    openAppSettings(); // Opens the app's settings page
                  },
                ),
              ),
            );
          }
        }
      } else if (status.isGranted) {
        debugPrint('Notification permission already granted.');
      }
    }

    // Android-specific initialization settings. Uses app launcher icon.
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/Darwin-specific initialization settings. Requests permissions for alert, badge, and sound.
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Combine settings for all platforms.
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    // Initialize the plugin with the defined settings.
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      // Callback for when a notification is tapped while the app is in the foreground.
      onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
        debugPrint('Notification tapped: ${notificationResponse.payload}');
        // You can add navigation or other logic here based on payload.
      },
      // Callback for when a notification is tapped while the app is in the background/terminated.
      // This requires `@pragma('vm:entry-point')` on the function in `main.dart` if using older Flutter versions.
      onDidReceiveBackgroundNotificationResponse: (NotificationResponse notificationResponse) async {
        debugPrint('Background notification tapped: ${notificationResponse.payload}');
        // You can add navigation or other logic here.
      },
    );

    // Create the Android notification channel. This is mandatory for Android 8.0 (Oreo) and above.
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'lpg_low_gas_channel', // Unique ID for the channel
      'LPG Gas Alerts', // User-visible name of the channel
      description: 'Notifications for critically low LPG gas levels', // User-visible description
      importance: Importance.high, // Set high importance for prominent notifications
      playSound: true, // Play sound for notifications from this channel
    );

    // Create the notification channel.
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Displays a local notification when the gas level is low.
  ///
  /// [deviceName]: The friendly name of the device.
  /// [gasPercentage]: The current gas percentage.
  Future<void> _showLowGasNotification(String deviceName, double gasPercentage) async {
    // Android-specific notification details, linking to the channel created in _initializeLocalNotifications.
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'lpg_low_gas_channel', // Channel ID MUST match the one created.
      'LPG Gas Alerts',
      channelDescription: 'Notifications for low LPG gas levels',
      importance: Importance.max, // Max importance for this specific notification
      priority: Priority.high, // High priority
      showWhen: false, // Don't show timestamp in notification (already in body)
      icon: '@mipmap/ic_launcher', // Icon for the notification
      playSound: true, // Play sound for this notification
    );

    // iOS/Darwin-specific notification details.
    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true, // Show alert
      presentBadge: true, // Update app badge count
      presentSound: true, // Play sound
    );

    // Combined platform-specific notification details.
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    // Show the notification.
    await flutterLocalNotificationsPlugin.show(
      0, // Notification ID (0 means it will overwrite previous notifications with ID 0)
      'LPG Gas Low! (${deviceName})', // Notification Title
      'Your ${deviceName} cylinder is at ${gasPercentage.toStringAsFixed(1)}% gas. Time to refill!', // Notification Body
      platformChannelSpecifics,
      payload: 'low_gas_alert_${widget.deviceId}', // Custom data that can be retrieved on tap
    );
  }

  /// Calculates the gas percentage based on current, empty, and full weights.
  /// Ensures the percentage is clamped between 0 and 100.
  ///
  /// [currentWeightGrams]: The current total weight of the cylinder.
  /// Returns the calculated gas percentage.
  double _calculateGasPercentage(double currentWeightGrams) {
    final double actualGasWeight = currentWeightGrams - widget.emptyWeight;
    final double gasCapacity = widget.fullWeight - widget.emptyWeight;

    // Handle edge cases: if capacity is non-positive or actual gas weight is non-positive.
    if (gasCapacity <= 0) return 0.0;
    if (actualGasWeight <= 0) return 0.0;

    double percentage = (actualGasWeight / gasCapacity) * 100;
    return percentage.clamp(0.0, 100.0); // Clamp to ensure valid percentage range.
  }

  /// Determines the color of the gas level indicator based on the percentage.
  ///
  /// [percentage]: The gas percentage (0-100).
  /// Returns a [Color] corresponding to the gas level (e.g., green for high, red for low).
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
        title: Text(widget.deviceName), // Display the friendly device name in the AppBar
        centerTitle: true,
        actions: [
          // History button in the AppBar.
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              // Navigate to the HistoryScreen for the current device.
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
      body: StreamBuilder<LPGDevice>( // StreamBuilder specifically for LPGDevice objects
        // Listen to the real-time stream of a single device's data from FirestoreService.
        stream: _firestoreService.getDeviceStream(widget.deviceId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Show a circular progress indicator while waiting for data.
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            // Display an error message if the stream encounters an error.
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            // If no data is available (e.g., document doesn't exist yet).
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_rounded, size: 60, color: Colors.orange.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'No real-time data for device: ${widget.deviceName}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ensure the ESP32 is sending data to this Device ID.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final LPGDevice device = snapshot.data!; // Directly access the LPGDevice object
          final double currentWeightGrams = device.currentWeightGrams;
          final DateTime timestamp = device.timestamp;

          final double gasPercentage = _calculateGasPercentage(currentWeightGrams);
          final Color gasLevelColor = _getGasLevelColor(gasPercentage);

          // Low gas notification logic:
          // Notify if gas is above 0, below or at threshold, and was previously above threshold.
          if (gasPercentage > 0 && gasPercentage <= _lowGasThreshold && _lastNotifiedPercentage > _lowGasThreshold) {
            _showLowGasNotification(widget.deviceName, gasPercentage);
          }
          // Update the last notified percentage to the current value.
          _lastNotifiedPercentage = gasPercentage;

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0), // Padding around the main card
              child: Card(
                elevation: 10, // Card shadow
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20), // Rounded corners for the card
                ),
                color: Colors.white, // Card background color
                child: Padding(
                  padding: const EdgeInsets.all(25.0), // Inner padding for the card content
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Column takes minimum space
                    children: [
                      // Device Name
                      Text(
                        widget.deviceName,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      // Device ID
                      Text(
                        'ID: ${widget.deviceId}',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30), // Spacer
                      // Gas Tank Icon
                      Icon(
                        Icons.local_fire_department, // Icon representing LPG
                        size: 120, // Icon size
                        color: gasLevelColor, // Icon color based on gas level
                      ),
                      const SizedBox(height: 24), // Spacer
                      // LPG Level Percentage
                      Text(
                        'LPG Level: ${gasPercentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: gasLevelColor,
                        ),
                      ),
                      const SizedBox(height: 20), // Spacer
                      // Linear Progress Indicator for Gas Level
                      SizedBox(
                        width: 300, // Fixed width for the progress bar
                        child: LinearProgressIndicator(
                          value: gasPercentage / 100, // Value (0.0 to 1.0)
                          backgroundColor: Colors.grey[300], // Background color of the bar
                          valueColor: AlwaysStoppedAnimation<Color>(gasLevelColor), // Color of the progress
                          minHeight: 20, // Height of the bar
                          borderRadius: BorderRadius.circular(10), // Rounded corners
                        ),
                      ),
                      const SizedBox(height: 20), // Spacer
                      // Current Weight Display
                      Text(
                        'Current Weight: ${(currentWeightGrams / 1000).toStringAsFixed(2)} kg',
                        style: TextStyle(
                          fontSize: 22,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      // Empty and Full Weight Information
                      Text(
                        'Empty: ${(widget.emptyWeight / 1000).toStringAsFixed(2)} kg, Full: ${(widget.fullWeight / 1000).toStringAsFixed(2)} kg',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      // Last Updated Timestamp
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Text(
                          // Format DateTime to string, splitting to remove microseconds.
                          'Last Updated: ${timestamp.toLocal().toString().split('.')[0]}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30), // Spacer
                      // Low Gas Warning Message
                      if (gasPercentage > 0 && gasPercentage < _lowGasThreshold)
                        Column(
                          children: [
                            Icon(Icons.battery_alert_rounded, color: Colors.red.shade700, size: 40),
                            const SizedBox(height: 10),
                            Text(
                              'WARNING: LPG level is critically low!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              'Refill or replace cylinder soon.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.red.shade500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
