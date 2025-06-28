// lib/services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart'; // Still needed for Theme.of(_context).platform and openAppSettings
import 'package:permission_handler/permission_handler.dart';


// NEW: Top-level function for background notification response
// This function must be a top-level function (not inside any class)
// and must be annotated with @pragma('vm:entry-point') to ensure it's not stripped by the Dart compiler.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  debugPrint('Background notification tapped: ${notificationResponse.payload}');
  // You can add logic here to handle background taps, e.g., navigate to a specific screen
  // if the app is opened from a background notification.
  // Note: Access to context or providers from here is complex as this runs on a separate isolate.
}


class NotificationService {
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  BuildContext? _context; 

  NotificationService({BuildContext? context}) {
    _context = context; // Assign context if provided directly
    debugPrint('NotificationService: Constructor called.');
    _initializeNotifications();
  }

  // Method to set context (useful if not provided in constructor, e.g., in main.dart)
  void setContext(BuildContext context) {
    _context = context;
    debugPrint('NotificationService: Context set.');
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        debugPrint('Notification tapped: ${response.payload}');
      },
      // FIXED: Referencing the top-level function here
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    debugPrint('NotificationService: Initialization complete.');
  }

  /// Request notification permissions for iOS and Android 13+.
  Future<bool> requestPermissions() async {
    if (_context == null) {
      debugPrint('Warning: NotificationService: Context not set. Cannot request platform-specific permissions.');
      return false;
    }

    if (Theme.of(_context!).platform == TargetPlatform.android) {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        final result = await Permission.notification.request();
        debugPrint('NotificationService: Android permission request result: ${result.isGranted}');
        return result.isGranted;
      } else if (status.isGranted) {
        debugPrint('NotificationService: Android permission already granted.');
        return true;
      }
    }

    final bool? result = await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
    debugPrint('NotificationService: iOS permission request result: $result');
    return result ?? false;
  }

  /// Check current notification permission status.
  Future<PermissionStatus> getPermissionStatus() async {
    if (_context == null) {
      debugPrint('Warning: NotificationService: Context not set. Cannot check platform-specific permission status.');
      return PermissionStatus.denied;
    }

    if (Theme.of(_context!).platform == TargetPlatform.android) {
      final status = await Permission.notification.status;
      debugPrint('NotificationService: Android getPermissionStatus: $status');
      return status;
    }
    final IOSFlutterLocalNotificationsPlugin? iosPlugin = _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final NotificationsEnabledOptions? options = await iosPlugin.checkPermissions();
      debugPrint('NotificationService: iOS getPermissionStatus options: isAlertEnabled=${options?.isAlertEnabled}, isSoundEnabled=${options?.isSoundEnabled}');
      if (options != null && options.isAlertEnabled && options.isSoundEnabled) {
        return PermissionStatus.granted;
      } else if (options != null && (!options.isAlertEnabled || !options.isSoundEnabled)) {
        return PermissionStatus.denied;
      }
    }
    return PermissionStatus.denied;
  }

  /// Show a simple notification.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    debugPrint('NotificationService: Attempting to show notification ID: $id, Title: $title');
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'lpg_channel_id',
      'LPG Alerts',
      channelDescription: 'Notifications for low LPG gas levels',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails();

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    try {
      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );
      debugPrint('NotificationService: Notification ID $id shown successfully.');
    } catch (e) {
      debugPrint('NotificationService: Error showing notification ID $id: $e');
    }
  }

  /// Cancel a specific notification by its ID.
  Future<void> cancelNotification(int id) async {
    debugPrint('NotificationService: Attempting to cancel notification ID: $id');
    await _flutterLocalNotificationsPlugin.cancel(id);
  }

  /// Cancel all notifications.
  Future<void> cancelAllNotifications() async {
    debugPrint('NotificationService: Attempting to cancel all notifications.');
    await _flutterLocalNotificationsPlugin.cancelAll();
  }
}