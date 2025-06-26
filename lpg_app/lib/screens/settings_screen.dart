import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart'; // For accessing services
import 'package:lpg_app/services/firestore_service.dart'; // Import FirestoreService

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _defaultEmptyWeightController = TextEditingController();
  final TextEditingController _defaultFullWeightController = TextEditingController();

  late final FirestoreService _firestoreService;
  User? currentUser;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    currentUser = FirebaseAuth.instance.currentUser;
    _loadDefaultCylinderWeights(); // Load existing default weights
  }

  /// Loads the current default empty and full cylinder weights from the user's profile.
  Future<void> _loadDefaultCylinderWeights() async {
    if (currentUser == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userProfile = await _firestoreService.getUserProfile(currentUser!.uid);
      if (userProfile != null) {
        _defaultEmptyWeightController.text = (userProfile['defaultCylinderEmptyWeight'] ?? 0.0).toString();
        _defaultFullWeightController.text = (userProfile['defaultCylinderFullWeight'] ?? 0.0).toString();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load settings: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Saves the updated default empty and full cylinder weights to the user's profile.
  Future<void> _saveDefaultCylinderWeights() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    _formKey.currentState!.save();

    if (currentUser == null) {
      setState(() {
        _errorMessage = 'User not logged in. Please log in again.';
        _isLoading = false;
      });
      return;
    }

    try {
      final double newEmptyWeight = double.parse(_defaultEmptyWeightController.text.trim());
      final double newFullWeight = double.parse(_defaultFullWeightController.text.trim());

      await _firestoreService.updateDefaultCylinderWeights(
        currentUser!.uid,
        newEmptyWeight,
        newFullWeight,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Default cylinder weights updated successfully!')),
        );
        // Optionally, navigate back or simply update UI
      }
    } on FormatException {
      setState(() {
        _errorMessage = 'Please enter valid numbers for weights.';
      });
    } on Exception catch (e) {
      setState(() {
        _errorMessage = 'Failed to update weights: ${e.toString()}';
      });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
                    'Default Cylinder Weights',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 25),
                  TextFormField(
                    controller: _defaultEmptyWeightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Default Empty Weight (grams)',
                      hintText: 'e.g., 14500',
                      prefixIcon: Icon(Icons.line_weight, color: Colors.teal),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a default empty weight.';
                      }
                      if (double.tryParse(value) == null || double.parse(value) < 0) {
                        return 'Please enter a valid positive number.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _defaultFullWeightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Default Full Weight (grams)',
                      hintText: 'e.g., 28700',
                      prefixIcon: Icon(Icons.scale, color: Colors.teal),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a default full weight.';
                      }
                      final double? empty = double.tryParse(_defaultEmptyWeightController.text.trim());
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
                          onPressed: _saveDefaultCylinderWeights,
                          icon: const Icon(Icons.save, color: Colors.white),
                          label: const Text('Save Defaults'),
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
