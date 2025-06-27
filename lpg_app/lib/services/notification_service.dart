// lib/services/notification_service.dart
import 'package:flutter/foundation.dart'; // For defaultTargetPlatform and debugPrint
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart'; // For requesting notification permission

class NotificationService {
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  NotificationService() {
    _initializeNotifications();
  }

  /// Initializes the notification plugin settings.
  Future<void> _initializeNotifications() async {
    // Request notification permissions for Android 13+ and iOS.
    // Call this before initializing the plugin on relevant platforms.
    await _requestPermissions();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher'); // Use your app icon

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap here if needed.
        debugPrint('Notification tapped: ${response.payload}');
      },
    );
    debugPrint('FlutterLocalNotificationsPlugin initialized.');
  }

  /// Requests necessary notification permissions.
  Future<void> _requestPermissions() async {
    debugPrint('Attempting to request notification permissions...');
    if (defaultTargetPlatform == TargetPlatform.android) {
      final statusBefore = await Permission.notification.status;
      debugPrint('Android Notification Permission Status (before request): $statusBefore');

      if (statusBefore.isDenied || statusBefore.isPermanentlyDenied) {
        final statusAfterRequest = await Permission.notification.request();
        debugPrint('Android Notification Permission Status (after request): $statusAfterRequest');

        if (statusAfterRequest.isDenied) {
          debugPrint('Notification permission explicitly denied by user.');
          // Optionally, show a dialog explaining why permission is needed
          // and guide them to app settings.
        } else if (statusAfterRequest.isPermanentlyDenied) {
          debugPrint('Notification permission permanently denied. User needs to enable from app settings.');
          // Show a dialog that guides user to app settings.
          // Example: openAppSettings();
        } else if (statusAfterRequest.isGranted) {
          debugPrint('Notification permission granted!');
        }
      } else if (statusBefore.isGranted) {
        debugPrint('Notification permission already granted.');
      } else {
        debugPrint('Android Notification Permission Status is unexpected: $statusBefore');
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      debugPrint('Requesting iOS/macOS notification permissions...');
      final iosResult = await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      debugPrint('iOS Notification Permission Result: $iosResult');

      final macosResult = await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
       debugPrint('macOS Notification Permission Result: $macosResult');
    } else {
      debugPrint('No specific notification permission handling needed/implemented for platform: $defaultTargetPlatform');
    }
  }

  /// Shows a simple text notification.
  /// [id]: Unique ID for the notification.
  /// [title]: Title of the notification.
  /// [body]: Content/body of the notification.
  /// [payload]: Optional data to be passed with the notification.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    // Check if permission is granted before showing notification
    if (defaultTargetPlatform == TargetPlatform.android) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        debugPrint('Cannot show notification: Permission not granted.');
        return;
      }
    }
    
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'lpg_low_gas_channel', // ID of the channel
      'LPG Low Gas Alerts', // Name of the channel
      channelDescription: 'Notifications for low LPG gas levels',
      importance: Importance.high, // High importance for critical alerts
      priority: Priority.high,
      ticker: 'ticker',
    );

    const DarwinNotificationDetails darwinPlatformChannelSpecifics =
        DarwinNotificationDetails();

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: darwinPlatformChannelSpecifics,
      macOS: darwinPlatformChannelSpecifics,
    );

    debugPrint('Attempting to show notification: $title - $body');
    await _flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
    debugPrint('Notification shown successfully (or attempted).');
  }

  /// Cancels a specific notification by its ID.
  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
    debugPrint('Notification with ID $id cancelled.');
  }

  /// Cancels all pending notifications.
  Future<void> cancelAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
    debugPrint('All notifications cancelled.');
  }
}