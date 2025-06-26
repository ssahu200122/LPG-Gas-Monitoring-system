import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // For StreamSubscription
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:lpg_app/services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart'; // To get current user for Firestore linking

class ProvisioningInProgressScreen extends StatefulWidget {
  final String deviceName;
  final double emptyWeight;
  final double fullWeight;
  final String homeSsid;
  final String homePassword;
  final String esp32FirebaseEmail;
  final String esp32FirebasePassword;

  const ProvisioningInProgressScreen({
    super.key,
    required this.deviceName,
    required this.emptyWeight,
    required this.fullWeight,
    required this.homeSsid,
    required this.homePassword,
    required this.esp32FirebaseEmail,
    required this.esp32FirebasePassword,
  });

  @override
  State<ProvisioningInProgressScreen> createState() => _ProvisioningInProgressScreenState();
}

class _ProvisioningInProgressScreenState extends State<ProvisioningInProgressScreen> {
  String _statusMessage = 'Sending configuration to device...';
  IconData _statusIcon = Icons.settings_ethernet;
  Color _statusColor = Colors.blue;
  bool _isProvisioningComplete = false; // True after HTTP response is received
  String? _deviceIdFromEsp32; // Stores the device ID received from ESP32

  late final FirestoreService _firestoreService;
  late final User? _currentUser;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _hasNavigatedBack = false; // Flag to prevent multiple navigations

  @override
  void initState() {
    super.initState();
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _currentUser = FirebaseAuth.instance.currentUser;

    _sendConfigToEsp32(); // Start the provisioning process
    _startNetworkMonitoring(); // Start monitoring network for auto-pop
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel(); // Clean up network listener
    super.dispose();
  }

  /// Sends the collected configuration data via HTTP POST to the ESP32.
  /// Updates UI status based on the response.
  Future<void> _sendConfigToEsp32() async {
    try {
      final Uri esp32ConfigUrl = Uri.http('192.168.4.1', '/save_config');
      final Map<String, String> body = {
        'ssid': widget.homeSsid,
        'pass': widget.homePassword,
        'fb_email': widget.esp32FirebaseEmail,
        'fb_pass': widget.esp32FirebasePassword,
        'dev_name': widget.deviceName,
      };

      final response = await http.post(
        esp32ConfigUrl,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );

      if (!mounted) return; // Ensure widget is still mounted

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(response.body);
        if (responseBody['status'] == 'success') {
          _deviceIdFromEsp32 = responseBody['deviceId'];
          setState(() {
            _statusMessage = 'Configuration sent successfully! Device is connecting to home Wi-Fi.';
            _statusIcon = Icons.check_circle;
            _statusColor = Colors.green;
            _isProvisioningComplete = true; // Mark HTTP part as complete
          });

          // Link device to user in Firestore after successful HTTP config
          if (_currentUser != null) {
            await _firestoreService.linkDeviceToUser(
              _currentUser.uid,
              _deviceIdFromEsp32!,
              widget.deviceName,
              widget.emptyWeight,
              widget.fullWeight,
            );
            if (mounted) {
              setState(() {
                _statusMessage = 'Device linked to your account. Please switch Wi-Fi back to home network.';
              });
            }
          } else {
            if (mounted) {
              setState(() {
                _statusMessage = 'Configuration sent, but failed to link to app account (user not logged in).';
                _statusIcon = Icons.warning;
                _statusColor = Colors.orange;
              });
            }
          }
        } else {
          // ESP32 reported an error
          setState(() {
            _statusMessage = 'Device configuration failed: ${responseBody['message'] ?? 'Unknown error'}';
            _statusIcon = Icons.error;
            _statusColor = Colors.red;
            _isProvisioningComplete = true;
          });
        }
      } else {
        // HTTP request itself failed
        setState(() {
          _statusMessage = 'Failed to send configuration (HTTP ${response.statusCode}). Ensure connected to ESP32 Wi-Fi.';
          _statusIcon = Icons.error;
          _statusColor = Colors.red;
          _isProvisioningComplete = true;
        });
      }
    } on http.ClientException catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = "Network error: Make sure you are connected to the ESP32 Wi-Fi (LPG_ESP_XXXX). Error: ${e.message}";
          _statusIcon = Icons.wifi_off;
          _statusColor = Colors.red;
          _isProvisioningComplete = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'An unexpected error occurred: ${e.toString()}';
          _statusIcon = Icons.error_outline;
          _statusColor = Colors.red;
          _isProvisioningComplete = true;
        });
      }
    }
  }

  /// Monitors network connectivity and automatically navigates back.
  void _startNetworkMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      debugPrint('ProvisioningStatusScreen: Connectivity changed: $results');
      if (_hasNavigatedBack) return; // Prevent multiple navigations

      // We are waiting for the phone to *no longer* be connected to the ESP32's AP.
      // This means either connecting to a new Wi-Fi (home Wi-Fi) or temporarily having no connection.
      // The ESP32 reboots/reconfigures after getting the data, so its AP will disappear.
      // A simple check if *any* Wi-Fi is present OR if we are completely disconnected
      // is usually sufficient to indicate the provisioning AP is gone.

      if (_isProvisioningComplete) { // Only attempt to auto-pop if provisioning request was sent
        if (results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.none)) {
          // Add a small delay to ensure the network truly stabilizes
          Future.delayed(const Duration(seconds: 3), () { // Increased delay slightly
            if (mounted && !_hasNavigatedBack) {
              setState(() {
                _hasNavigatedBack = true;
              });
              // Pop this screen (ProvisioningInProgressScreen)
              Navigator.of(context).pop();
              // Pop the AddDeviceScreen as well, returning to LPGDeviceListScreen
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop(); 
              }
            }
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Provisioning Status'),
        centerTitle: true,
        automaticallyImplyLeading: false, // No back button until process finishes
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Card(
            elevation: 10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _statusIcon,
                    size: 80,
                    color: _statusColor,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _statusColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!_isProvisioningComplete) // Show spinner only while sending config
                    const CircularProgressIndicator(color: Colors.teal),
                  
                  // Show manual instruction button only after provisioning logic completed (success/fail)
                  if (_isProvisioningComplete)
                    Column(
                      children: [
                        const SizedBox(height: 20),
                        const Text(
                          'If automatic redirect does not occur, please manually switch your phone\'s Wi-Fi back to your regular home network.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, color: Colors.grey),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            // Manually pop both screens
                            if (!_hasNavigatedBack) {
                              setState(() {
                                _hasNavigatedBack = true; // Set flag
                              });
                              Navigator.of(context).pop(); // Pop this screen
                              if (mounted && Navigator.of(context).canPop()) {
                                Navigator.of(context).pop(); // Pop AddDeviceScreen
                              }
                            }
                          },
                          child: const Text('I\'ve Switched Wi-Fi (Manual)'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
