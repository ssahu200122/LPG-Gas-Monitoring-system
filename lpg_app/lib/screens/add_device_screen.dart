import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
// import 'package:http/http.dart' as http; // Still needed for http.ClientException type
// import 'dart:convert'; // Still needed for json.decode type
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:lpg_app/services/firestore_service.dart';
// Import the new provisioning in progress screen
import 'package:lpg_app/screens/provisioning_in_progress_screen.dart'; 

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emptyWeightController = TextEditingController();
  final TextEditingController _fullWeightController = TextEditingController();

  final TextEditingController _homeSsidController = TextEditingController();
  final TextEditingController _homePasswordController = TextEditingController();
  final TextEditingController _esp32FirebaseEmailController = TextEditingController();
  final TextEditingController _esp32FirebasePasswordController = TextEditingController();

  late final FirestoreService _firestoreService;
  User? currentUser;

  bool _isLoading = false; // Still used for initial validation phase
  String? _errorMessage;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    currentUser = FirebaseAuth.instance.currentUser;
    _loadDefaultCylinderWeights();

    _checkWifiConnection();
    // Listen for connectivity changes to update the info message dynamically
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _checkWifiConnection();
    });
  }

  /// Checks the current WiFi connection state and updates the informational message.
  /// This message guides the user on whether they need to connect to the ESP32's AP.
  Future<void> _checkWifiConnection() async {
    final connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.wifi)) {
      if (mounted) {
        setState(() {
          _infoMessage = "Connected to Wi-Fi. Ensure it's your ESP32's 'LPG_ESP_XXXX' network.";
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _infoMessage = "Please connect to your ESP32's Wi-Fi network (SSID: LPG_ESP_XXXX, Password: password) from your phone's Wi-Fi settings.";
        });
      }
    }
  }

  /// Loads default empty and full cylinder weights from the user's Firestore profile.
  /// These values are then used to pre-fill the input fields.
  Future<void> _loadDefaultCylinderWeights() async {
    if (currentUser == null) return;
    try {
      final userProfile = await _firestoreService.getUserProfile(currentUser!.uid);
      if (userProfile != null) {
        if (mounted) {
          _emptyWeightController.text = (userProfile['defaultCylinderEmptyWeight'] ?? 14500.0).toString();
          _fullWeightController.text = (userProfile['defaultCylinderFullWeight'] ?? 28700.0).toString();
        }
      }
    } catch (e) {
      debugPrint('Error loading default weights: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load default weights: ${e.toString()}')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emptyWeightController.dispose();
    _fullWeightController.dispose();
    _homeSsidController.dispose();
    _homePasswordController.dispose();
    _esp32FirebaseEmailController.dispose();
    _esp32FirebasePasswordController.dispose();
    super.dispose();
  }

  /// Handles the initial validation and then navigates to the provisioning screen.
  Future<void> _initiateProvisioning() async {
    setState(() {
      _isLoading = true; // Show loading for initial validation
      _errorMessage = null;
    });

    // 1. Validate form fields
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    _formKey.currentState!.save();

    // 2. Check if user is logged in
    if (currentUser == null) {
      setState(() {
        _errorMessage = 'User not logged in. Please log in again.';
        _isLoading = false;
      });
      return;
    }

    // 3. CRITICAL: Check if phone is connected to any Wi-Fi network.
    // We cannot reliably determine the exact SSID (LPG_ESP_XXXX) across all platforms
    // without additional setup (e.g., location permissions, network_info_plus).
    // However, checking if *any* Wi-Fi is connected is a strong indicator.
    final connectivityResult = await (Connectivity().checkConnectivity());
    if (!connectivityResult.contains(ConnectivityResult.wifi)) {
      setState(() {
        _errorMessage = "Please connect to your ESP32's Wi-Fi network ('LPG_ESP_XXXX') first.";
        _isLoading = false;
      });
      // Also show a SnackBar for more direct feedback
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please connect to ESP32 Wi-Fi first.")),
        );
      }
      return; // STOP here if not connected to Wi-Fi
    }

    // If all validations and checks pass, immediately navigate to the
    // ProvisioningInProgressScreen, passing all collected data.
    if (mounted) {
      setState(() {
        _isLoading = false; // Dismiss loading before navigating to the next screen
      });
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProvisioningInProgressScreen(
            deviceName: _nameController.text.trim(),
            emptyWeight: double.parse(_emptyWeightController.text.trim()),
            fullWeight: double.parse(_fullWeightController.text.trim()),
            homeSsid: _homeSsidController.text.trim(),
            homePassword: _homePasswordController.text.trim(),
            esp32FirebaseEmail: _esp32FirebaseEmailController.text.trim(),
            esp32FirebasePassword: _esp32FirebasePasswordController.text.trim(),
          ),
        ),
      );
      // This screen (AddDeviceScreen) will remain on the navigation stack until
      // ProvisioningInProgressScreen successfully completes and pops both.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New LPG Device'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(25.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Configure New LPG Device',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // Info/Guidance message for Wi-Fi connection
                  if (_infoMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi, color: Colors.blue.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _infoMessage!,
                              style: TextStyle(color: Colors.blue.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 25),

                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Friendly Name (e.g., Kitchen Cylinder)',
                      prefixIcon: Icon(Icons.label_important_outline, color: Colors.teal),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a friendly name.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _emptyWeightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Empty Cylinder Weight (grams)',
                      hintText: 'e.g., 14500',
                      prefixIcon: Icon(Icons.line_weight, color: Colors.teal),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter empty weight.';
                      }
                      if (double.tryParse(value) == null || double.parse(value) < 0) {
                        return 'Please enter a valid positive number.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _fullWeightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Full Cylinder Weight (grams)',
                      hintText: 'e.g., 28700',
                      prefixIcon: Icon(Icons.scale, color: Colors.teal),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter full weight.';
                      }
                      final double? empty = double.tryParse(_emptyWeightController.text.trim());
                      final double? full = double.tryParse(value);
                      if (full == null || full < 0) {
                        return 'Please enter a valid positive number.';
                      }
                      if (empty != null && full <= empty) {
                        return 'Full weight must be greater than empty weight.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Home WiFi Credentials (for ESP32)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: _homeSsidController,
                    decoration: const InputDecoration(
                      labelText: 'WiFi Network Name (SSID)',
                      hintText: 'e.g., MyHomeWiFi',
                      prefixIcon: Icon(Icons.wifi_rounded, color: Colors.teal),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your home WiFi SSID.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _homePasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'WiFi Password',
                      prefixIcon: Icon(Icons.lock_open_rounded, color: Colors.teal),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your home WiFi password.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Firebase Account Credentials (for ESP32)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: _esp32FirebaseEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Firebase Account Email',
                      hintText: 'e.g., esp32_device@example.com',
                      prefixIcon: Icon(Icons.email_outlined, color: Colors.teal),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty || !value.contains('@')) {
                        return 'Please enter a valid Firebase email for ESP32.';
                      }
                      return null;
                      },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _esp32FirebasePasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Firebase Account Password',
                      prefixIcon: Icon(Icons.password_rounded, color: Colors.teal),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().length < 6) {
                        return 'Password must be at least 6 characters long.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),

                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 15.0),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  
                  _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                      : ElevatedButton.icon(
                          onPressed: _initiateProvisioning, // Call the new initiating function
                          icon: const Icon(Icons.add_to_queue, color: Colors.white),
                          label: const Text('Provision & Add Device'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
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
