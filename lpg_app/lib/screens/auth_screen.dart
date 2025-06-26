import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart'; // Import Provider for accessing services
import 'package:lpg_app/services/auth_service.dart'; // Import AuthService
import 'package:lpg_app/services/firestore_service.dart'; // Import FirestoreService
import 'package:lpg_app/screens/lpg_device_list_screen.dart'; // Import LPGDeviceListScreen

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // GlobalKey for managing the form state, used for validation.
  final _formKey = GlobalKey<FormState>();
  // Controllers for text input fields (email and password).
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  // Boolean to toggle between login and signup modes.
  bool _isLogin = true;
  // Boolean to show/hide a loading indicator during async operations.
  bool _isLoading = false;
  // String to store and display authentication error messages.
  String? _errorMessage;

  // Lazily initialized services, accessed via Provider.of.
  late final AuthService _authService;
  late final FirestoreService _firestoreService;

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
  }

  @override
  void dispose() {
    // Dispose controllers to free up resources when the widget is removed from the tree.
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Asynchronous function to handle form submission (login or signup).
  Future<void> _submitAuthForm() async {
    // Set loading state to true and clear any previous error messages.
    setState(() {
      _isLoading = true;
      _errorMessage = null; // Clear any existing error message
    });

    // Validate the form fields. If invalid, stop loading and return.
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    _formKey.currentState!.save(); // Save the current state of the form fields

    try {
      User? user;
      if (_isLogin) {
        // Attempt to log in an existing user using AuthService.
        user = await _authService.signIn(_emailController.text.trim(), _passwordController.text.trim());
      } else {
        // Attempt to sign up a new user using AuthService.
        user = await _authService.signUp(_emailController.text.trim(), _passwordController.text.trim());
        
        // If signup is successful, create the user's profile in Firestore.
        if (user != null) {
          await _firestoreService.createUserProfile(user.uid, user.email!);
        }
      }

      if (user != null && context.mounted) {
        // IMPORTANT: Navigate to LPGDeviceListScreen after successful auth.
        // pushReplacement removes AuthScreen from the navigation stack.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LPGDeviceListScreen()),
        );
      } else if (user == null) {
        // This case should ideally only occur if a specific Firebase Auth Exception
        // was caught and rethrown, or if the user object inexplicably came back null.
        // Provide a generic error if it somehow falls through.
        setState(() {
          _errorMessage = "Authentication failed. Please try again.";
        });
      }

    } on FirebaseAuthException catch (e) {
      // Catch specific Firebase authentication exceptions and provide user-friendly messages.
      String message;
      if (e.code == 'weak-password') {
        message = 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        message = 'An account already exists for that email.';
      } else if (e.code == 'user-not-found') {
        message = 'No user found for that email.';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password provided.';
      } else {
        message = 'Authentication failed: ${e.message}'; // Generic message for other errors
      }
      setState(() {
        _errorMessage = message; // Update error message to be displayed in the UI
      });
    } catch (e) {
      // Catch any other unexpected errors during the process.
      setState(() {
        _errorMessage = 'An unexpected error occurred: ${e.toString()}';
      });
    } finally {
      // Ensure loading state is reset regardless of success or failure.
      // Only set to false if we haven't navigated away.
      if (context.mounted && _isLoading) {
         setState(() {
           _isLoading = false;
         });
      }
    }
  }

  // The _showMessage function is not explicitly called anywhere.
  // It can be removed if not intended for future use.
  // void _showMessage(String title, String message, BuildContext context) {
  //   showDialog(
  //     context: context,
  //     builder: (BuildContext context) {
  //       return AlertDialog(
  //         title: Text(title, style: const TextStyle(color: Colors.teal)),
  //         content: Text(message),
  //         actions: <Widget>[
  //           TextButton(
  //             child: const Text('OK', style: TextStyle(color: Colors.teal)),
  //             onPressed: () {
  //               Navigator.of(context).pop();
  //             },
  //           ),
  //         ],
  //       );
  //     },
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade50, // Light teal background color for the screen
      body: Center(
        child: SingleChildScrollView( // Allows content to scroll if it exceeds screen height (e.g., on small devices)
          padding: const EdgeInsets.all(20.0), // Padding around the central content
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // Center column content vertically on the screen
            children: [
              // App Icon/Logo
              Icon(
                Icons.propane_tank_rounded, // LPG tank icon
                size: 100, // Icon size
                color: Colors.teal.shade600, // Icon color
              ),
              const SizedBox(height: 20), // Spacer below the icon
              // Dynamic title based on current mode (Login or Sign Up)
              Text(
                _isLogin ? 'Welcome Back!' : 'Join Us!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade800,
                ),
              ),
              const SizedBox(height: 30), // Spacer below the title
              Card(
                elevation: 10, // Card shadow
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20), // Rounded corners for the card
                ),
                child: Padding(
                  padding: const EdgeInsets.all(25.0), // Inner padding for the card
                  child: Form(
                    key: _formKey, // Assign the global key to the Form for validation
                    child: Column(
                      mainAxisSize: MainAxisSize.min, // Make column only take necessary vertical space
                      children: [
                        TextFormField(
                          controller: _emailController, // Controller for email input
                          keyboardType: TextInputType.emailAddress, // Optimized keyboard for email
                          decoration: const InputDecoration(
                            labelText: 'Email Address', // Label for the input field
                            prefixIcon: Icon(Icons.email_outlined, color: Colors.teal), // Email icon
                          ),
                          validator: (value) { // Validation logic for email input
                            if (value == null || value.trim().isEmpty || !value.contains('@')) {
                              return 'Please enter a valid email address.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20), // Spacer
                        TextFormField(
                          controller: _passwordController, // Controller for password input
                          obscureText: true, // Hide password characters
                          decoration: const InputDecoration(
                            labelText: 'Password', // Label for the input field
                            prefixIcon: Icon(Icons.lock_outline, color: Colors.teal), // Lock icon
                          ),
                          validator: (value) { // Validation logic for password input
                            if (value == null || value.trim().length < 6) {
                              return 'Password must be at least 6 characters long.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 25), // Spacer
                        // Display error message if present (e.g., from Firebase Auth)
                        if (_errorMessage != null)
                          Text(
                            _errorMessage!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 20), // Spacer
                        _isLoading
                            ? const CircularProgressIndicator(color: Colors.teal) // Show loading spinner if busy
                            : ElevatedButton(
                                onPressed: _submitAuthForm, // Call submit function on button press
                                child: Text(_isLogin ? 'LOGIN' : 'SIGN UP'), // Dynamic button text
                              ),
                        const SizedBox(height: 15), // Spacer
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isLogin = !_isLogin; // Toggle between login and signup mode
                              _errorMessage = null; // Clear error message when toggling modes
                            });
                          },
                          child: Text(
                            _isLogin
                                ? 'Need an account? Sign Up'
                                : 'Already have an account? Login',
                            style: TextStyle(color: Colors.teal.shade700), // Text button with teal color
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
