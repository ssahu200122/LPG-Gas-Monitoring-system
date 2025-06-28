import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  /// Stream of authentication state changes.
  /// Emits a [User] when the user signs in or out, or null if no user is signed in.
  Stream<User?> get userChanges => _firebaseAuth.authStateChanges();

  /// Get the current authenticated [User].
  /// Returns null if no user is currently signed in.
  User? getCurrentUser() {
    return _firebaseAuth.currentUser;
  }

  /// Sign in with email and password.
  Future<UserCredential> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } on FirebaseAuthException {
      rethrow; // Rethrow FirebaseAuthException to be caught by the UI
    } catch (e) {
      // Handle other potential errors during sign-in
      throw Exception('Failed to sign in: $e');
    }
  }

  /// Sign up with email and password.
  Future<UserCredential> signUpWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } on FirebaseAuthException {
      rethrow; // Rethrow FirebaseAuthException to be caught by the UI
    } catch (e) {
      // Handle other potential errors during sign-up
      throw Exception('Failed to sign up: $e');
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
    } catch (e) {
      throw Exception('Failed to sign out: $e');
    }
  }
}