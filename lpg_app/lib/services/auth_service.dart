// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lpg_app/services/firestore_service.dart'; // Import FirestoreService

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirestoreService _firestoreService =  FirestoreService(); // Use const constructor

  // Stream of authenticated user changes
  // This is the getter that `main.dart` will now correctly use
  Stream<User?> get userChanges => _firebaseAuth.authStateChanges();

  // Get current user (synchronous check)
  User? getCurrentUser() {
    return _firebaseAuth.currentUser;
  }

  /// Sign up with email and password
  Future<User?> signUp(String email, String password) async {
    try {
      UserCredential result = await _firebaseAuth.createUserWithEmailAndPassword(email: email, password: password);
      User? user = result.user;

      if (user != null) {
        // Create user profile in Firestore immediately after successful signup
        await _firestoreService.createUserProfile(user.uid, user.email ?? '');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      // Handle Firebase specific errors
      throw Exception(e.message);
    } catch (e) {
      // Handle other generic errors
      throw Exception('Failed to sign up: $e');
    }
  }

  /// Sign in with email and password
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
      return result.user;
    } on FirebaseAuthException catch (e) {
      // Handle Firebase specific errors
      throw Exception(e.message);
    } catch (e) {
      // Handle other generic errors
      throw Exception('Failed to sign in: $e');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
    } catch (e) {
      throw Exception('Failed to sign out: $e');
    }
  }
}