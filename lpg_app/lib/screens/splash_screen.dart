import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Needed for FirebaseAuth.instance.currentUser

import 'package:lpg_app/screens/auth_screen.dart';
import 'package:lpg_app/screens/root_screen.dart';

class SplashScreen extends StatefulWidget { // Keep as StatefulWidget
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  void _checkAuthAndNavigate() async {
    // Give a brief delay for Firebase to potentially auto-login/initialize its state
    // and for the splash screen UI to be visible for a moment.
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return; // Ensure widget is still in the tree before navigating

    // CRITICAL FIX: Check currentUser synchronously AFTER the delay.
    // This is more reliable for initial navigation than listening to a stream
    // which might emit before the UI is fully stable or the delay completes.
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // User is not logged in, navigate to AuthScreen
      // Using pushReplacementNamed is good practice for initial navigation
      Navigator.of(context).pushReplacementNamed('/auth');
    } else {
      // User is logged in, navigate to RootScreen (which contains the bottom nav bar)
      Navigator.of(context).pushReplacementNamed('/root');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor, // Use primaryColor as defined in theme
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.propane_tank,
              size: 100,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            const Text(
              'LPG Gas Monitor',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}