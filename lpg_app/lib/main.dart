import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Keep this import for User? type

import 'package:lpg_app/firebase_options.dart';
import 'package:lpg_app/services/auth_service.dart';
import 'package:lpg_app/services/firestore_service.dart';
import 'package:lpg_app/services/notification_service.dart';
// import 'package:lpg_monitor_app/screens/auth_screen.dart'; // No longer directly used as home
// import 'package:lpg_monitor_app/screens/lpg_device_list_screen.dart'; // No longer directly used as home

import 'package:lpg_app/screens/splash_screen.dart'; // NEW: Import SplashScreen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(
          create: (_) => AuthService(),
        ),
        Provider<FirestoreService>(
          create: (_) =>  FirestoreService(),
        ),
        Provider<NotificationService>(
          create: (_) => NotificationService(),
        ),
        StreamProvider<User?>(
          // This StreamProvider is crucial. SplashScreen will use it to navigate.
          create: (context) => context.read<AuthService>().userChanges,
          initialData: null,
        ),
      ],
      child: MaterialApp(
        title: 'LPG Monitor',
        debugShowCheckedModeBanner: false, // Hide the debug banner
        theme: ThemeData(
          primarySwatch: Colors.teal,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            elevation: 4,
            shadowColor: Colors.black54,
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              elevation: 5,
              shadowColor: Colors.black26,
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.teal,
              side: BorderSide(color: Colors.teal.shade700),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.teal, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          cardTheme: CardThemeData( // Corrected to use Card, not CardThemeData
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: const EdgeInsets.all(16),
            shadowColor: Colors.black26,
          ),
        ),
        // FIXED: Set SplashScreen as the initial home widget
        home: const SplashScreen(), 
      ),
    );
  }
}