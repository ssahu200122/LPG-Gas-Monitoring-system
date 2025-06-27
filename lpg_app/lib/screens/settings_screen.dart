import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart'; // Import permission_handler

import 'package:lpg_app/services/auth_service.dart';
import 'package:lpg_app/services/firestore_service.dart';
import 'package:lpg_app/screens/auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AuthService _authService;
  late final FirestoreService _firestoreService;
  User? _currentUser;

  final TextEditingController _defaultEmptyWeightController = TextEditingController();
  final TextEditingController _defaultFullWeightController = TextEditingController();
  final TextEditingController _lowGasThresholdController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  PermissionStatus _notificationPermissionStatus = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _currentUser = _authService.getCurrentUser();
    _loadUserSettings();
    _checkNotificationPermissionStatus(); // Only check notification permission
  }

  /// Checks and updates the notification permission status.
  Future<void> _checkNotificationPermissionStatus() async {
    final status = await Permission.notification.status;
    setState(() {
      _notificationPermissionStatus = status;
    });
  }

  /// Handles the permission request flow for a given permission type.
  Future<void> _requestPermission(Permission permissionType) async {
    setState(() {
      _isLoading = true; // Show loading indicator during permission request
    });
    try {
      PermissionStatus status = await permissionType.status;

      if (status.isPermanentlyDenied) {
        // If permanently denied, direct user to app settings
        bool opened = await openAppSettings();
        if (opened) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enable permission in app settings.')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open app settings.')),
            );
          }
        }
      } else if (status.isDenied || status.isRestricted || status.isLimited || status.isProvisional) {
        // Request permission if not granted
        status = await permissionType.request();
      }
      // If already granted, do nothing as the UI will reflect it.

      // After request/opening settings, recheck status to update UI
      await _checkNotificationPermissionStatus(); // Recheck only notification status

    } catch (e) {
      _errorMessage = 'Error requesting permission: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  /// Loads user-specific settings (default weights, low gas threshold) from Firestore.
  Future<void> _loadUserSettings() async {
    if (_currentUser == null) {
      _errorMessage = 'No user logged in.';
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userData = await _firestoreService.getUserProfile(_currentUser!.uid);
      if (userData != null) {
        _defaultEmptyWeightController.text = (userData['defaultCylinderEmptyWeight'] ?? '').toString();
        _defaultFullWeightController.text = (userData['defaultCylinderFullWeight'] ?? '').toString();
        _lowGasThresholdController.text = (userData['lowGasThresholdPercent'] ?? '').toString();
      }
    } catch (e) {
      _errorMessage = 'Failed to load settings: $e';
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Saves user-specific settings (default weights, low gas threshold) to Firestore.
  Future<void> _saveUserSettings() async {
    if (_currentUser == null) {
      _errorMessage = 'No user logged in. Please log in to save settings.';
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final double? emptyWeight = double.tryParse(_defaultEmptyWeightController.text);
      final double? fullWeight = double.tryParse(_defaultFullWeightController.text);
      final double? lowGasThreshold = double.tryParse(_lowGasThresholdController.text);

      if (emptyWeight == null || fullWeight == null || lowGasThreshold == null) {
        throw Exception('Please enter valid numbers for all weight and threshold fields.');
      }
      if (emptyWeight < 0 || fullWeight < 0 || lowGasThreshold < 0 || lowGasThreshold > 100) {
        throw Exception('Weights must be positive. Threshold must be between 0 and 100.');
      }
      if (emptyWeight >= fullWeight) {
        throw Exception('Empty weight must be less than full weight.');
      }

      await _firestoreService.updateDefaultCylinderWeights(
        _currentUser!.uid,
        emptyWeight,
        fullWeight,
      );
      await _firestoreService.updateUserProfile(
        _currentUser!.uid,
        {'lowGasThresholdPercent': lowGasThreshold},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully!')),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save settings: ${e.toString()}';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: ${e.toString()}')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _defaultEmptyWeightController.dispose();
    _defaultFullWeightController.dispose();
    _lowGasThresholdController.dispose();
    super.dispose();
  }

  /// Helper widget to build a permission status and action button.
  Widget _buildPermissionChecker({
    required String title,
    required String description,
    required PermissionStatus status,
    required VoidCallback onPressed,
  }) {
    Color iconColor;
    IconData iconData;
    String statusText;

    if (status.isGranted) {
      iconColor = Colors.green;
      iconData = Icons.check_circle_outline;
      statusText = 'Granted';
    } else if (status.isDenied) {
      iconColor = Colors.orange;
      iconData = Icons.error_outline;
      statusText = 'Denied';
    } else if (status.isPermanentlyDenied) {
      iconColor = Colors.red;
      iconData = Icons.cancel_outlined;
      statusText = 'Permanently Denied';
    } else { // unknown, restricted, limited, provisional
      iconColor = Colors.grey;
      iconData = Icons.help_outline;
      statusText = 'Unknown/Pending';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconData, color: iconColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Status: $statusText',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: iconColor,
                  ),
                ),
                ElevatedButton(
                  onPressed: status.isGranted ? null : onPressed, // Disable button if granted
                  style: ElevatedButton.styleFrom(
                    backgroundColor: status.isGranted ? Colors.grey : Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: Text(status.isGranted ? 'Granted' : (status.isPermanentlyDenied ? 'Open Settings' : 'Request')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Default Cylinder Weights (grams)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _defaultEmptyWeightController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Default Empty Weight (grams)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.line_weight),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _defaultFullWeightController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Default Full Weight (grams)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.straighten),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Low Gas Notification Threshold',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _lowGasThresholdController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Threshold Percentage (%)',
                      hintText: 'e.g., 20 for 20%',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.notifications_active),
                      suffixText: '%',
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Section for Notification Permission Checker (only one now)
                  Text(
                    'App Permissions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildPermissionChecker(
                    title: 'Notification Permission',
                    description: 'Required to send you alerts about low gas levels.',
                    status: _notificationPermissionStatus,
                    onPressed: () => _requestPermission(Permission.notification),
                  ),
                  const SizedBox(height: 30),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveUserSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.save),
                      label: const Text(
                        'Save Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _authService.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (context) => const AuthScreen()),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text(
                        'Logout',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}