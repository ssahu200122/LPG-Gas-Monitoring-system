import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // For checking auth state
import 'package:lpg_app/screens/auth_screen.dart'; // Import AuthScreen
import 'package:lpg_app/screens/lpg_device_list_screen.dart'; // Import LPGDeviceListScreen

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  /// Handles the navigation logic after the splash screen.
  /// It combines a minimum display duration with checking the initial Firebase
  /// authentication state to decide whether to go to AuthScreen or LPGDeviceListScreen.
  Future<void> _navigateToNextScreen() async {
    // Use Future.wait to ensure both:
    // 1. A minimum display time for the splash screen (e.g., 3 seconds).
    // 2. The initial authentication state from Firebase is determined.
    await Future.wait([
      Future.delayed(const Duration(seconds: 3)), // Minimum display duration
      // Await the first (initial) auth state change. This is critical to ensure
      // Firebase has had a chance to check for an existing session.
      FirebaseAuth.instance.authStateChanges().first, 
    ]);

    if (!mounted) return; // Ensure the widget is still in the tree after the wait

    // After both futures complete, check the current user status.
    // `FirebaseAuth.instance.currentUser` will reflect the latest known state
    // after `authStateChanges().first` has provided its value.
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // No user is logged in, navigate to AuthScreen (login/signup)
      // `pushReplacement` replaces the current route (SplashScreen) with the new one.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    } else {
      // User is logged in, navigate directly to LPGDeviceListScreen
      // `pushReplacement` replaces the current route (SplashScreen) with the new one.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LPGDeviceListScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade700, // Deep teal background for the splash screen
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Icon
            Icon(
              Icons.propane_tank_rounded, // Using LPG tank icon
              size: 120,
              color: Colors.white, // White icon
            ),
            const SizedBox(height: 20),
            // App Title
            const Text(
              'LPG Gas Monitor',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'Inter', // Ensure this font is in pubspec.yaml if external
              ),
            ),
            const SizedBox(height: 10),
            // App Tagline (optional)
            const Text(
              'Smart Monitoring for Your Home',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white70,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 40),
            // Loading Indicator (optional, but good for visual feedback)
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white), // White spinner
            ),
          ],
        ),
      ),
    );
  }
}
