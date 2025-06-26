import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // To monitor WiFi connection
import 'dart:async'; // For StreamSubscription

class ProvisioningStatusScreen extends StatefulWidget {
  final String deviceName;
  final String homeSsid;
  final String deviceId;

  const ProvisioningStatusScreen({
    super.key,
    required this.deviceName,
    required this.homeSsid,
    required this.deviceId,
  });

  @override
  State<ProvisioningStatusScreen> createState() => _ProvisioningStatusScreenState();
}

class _ProvisioningStatusScreenState extends State<ProvisioningStatusScreen> {
  // Stream subscription to listen for network changes
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isNavigatingBack = false; // Flag to prevent multiple navigation attempts

  @override
  void initState() {
    super.initState();
    _startNetworkMonitoring();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel(); // Cancel subscription to prevent memory leaks
    super.dispose();
  }

  /// Starts listening for network connectivity changes.
  /// Automatically navigates back once the phone is no longer connected to the ESP32's AP.
  void _startNetworkMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      debugPrint('Connectivity changed: $results');
      // If we are already navigating back, do nothing to prevent multiple pops
      if (_isNavigatingBack) return;

      // The key indicator that provisioning is likely complete is when the phone is
      // no longer on the ESP32's SoftAP and connects to *any* other Wi-Fi, or even goes to `none`
      // before connecting to home Wi-Fi.
      // We will assume that if *any* Wi-Fi connection is detected, the user has likely switched back
      // or the phone has reconnected to a known network after the ESP32 disappeared.
      // A more robust check might involve trying to get the new SSID and confirming it's NOT the ESP32's.
      // However, for simplicity and typical user flow, detecting *any* stable Wi-Fi should be sufficient
      // to trigger navigation back to the main app.
      
      // Check if we are now on a Wi-Fi network (implying we've left the ESP32's AP)
      // or if we've temporarily lost connection (which often happens when an AP disappears).
      // We want to navigate away once the provisioning is done and the phone is attempting to get back online.
      if (results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.none)) {
        // Add a small delay to ensure the network truly stabilizes
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_isNavigatingBack) { // Re-check mounted and flag
            setState(() {
              _isNavigatingBack = true; // Set flag to prevent multiple pops
            });
            // Pop this screen
            Navigator.of(context).pop();
            // Pop the AddDeviceScreen as well, returning to LPGDeviceListScreen
            if (mounted && Navigator.of(context).canPop()) { // Check if there's a screen to pop
              Navigator.of(context).pop(); 
            }
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Provisioning'),
        centerTitle: true,
        // No back button to force user to read instructions or press "I've Switched Wi-Fi"
        automaticallyImplyLeading: false, 
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
                    Icons.check_circle_outline,
                    size: 80,
                    color: Colors.green.shade600,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${widget.deviceName} Configured!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  Text(
                    'Your device "${widget.deviceName}" (ID: ${widget.deviceId}) has received its configuration and is now attempting to connect to your home Wi-Fi: "${widget.homeSsid}".',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    'IMPORTANT: Please manually switch your phone\'s Wi-Fi back to your regular home Wi-Fi network to continue using the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 30),
                  // This button allows manual dismissal if automatic doesn't happen for some reason
                  ElevatedButton(
                    onPressed: () {
                      if (!_isNavigatingBack) {
                        setState(() {
                          _isNavigatingBack = true;
                        });
                        Navigator.of(context).pop(); // Pop this screen
                        if (mounted && Navigator.of(context).canPop()) {
                          Navigator.of(context).pop(); // Pop the AddDeviceScreen as well
                        }
                      }
                    },
                    child: const Text('I\'ve Switched Wi-Fi'),
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
