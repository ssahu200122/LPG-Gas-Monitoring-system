import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Authentication

// A service class to handle all Firebase Authentication related operations.
class AuthService {
  // Get an instance of FirebaseAuth to interact with the authentication service.
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  // Constructor for AuthService. Made `const` as it has no mutable state.
   AuthService();

  /// Signs in a user with the given email and password.
  ///
  /// [email]: The user's email address.
  /// [password]: The user's password.
  /// Returns the [User] object if successful.
  /// Throws [FirebaseAuthException] on authentication errors (e.g., wrong password, user not found).
  /// Throws a generic [Exception] for other unexpected errors.
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user; // Return the authenticated user
    } on FirebaseAuthException {
      rethrow; // Re-throw the FirebaseAuthException for the UI to handle specifically.
    } catch (e) {
      // Catch any other unexpected errors during the sign-in process.
      throw Exception('Failed to sign in: $e');
    }
  }

  /// Signs up a new user with the given email and password.
  ///
  /// [email]: The new user's email address.
  /// [password]: The new user's password.
  /// Returns the newly created [User] object if successful.
  /// Throws [FirebaseAuthException] on sign-up errors (e.g., weak password, email already in use).
  /// Throws a generic [Exception] for other unexpected errors.
  Future<User?> signUp(String email, String password) async {
    try {
      UserCredential result = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user; // Return the newly created user
    } on FirebaseAuthException {
      rethrow; // Re-throw the FirebaseAuthException for the UI to handle specifically.
    } catch (e) {
      // Catch any other unexpected errors during the sign-up process.
      throw Exception('Failed to sign up: $e');
    }
  }

  /// Signs out the current authenticated user.
  /// This will clear the user's session.
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  /// Retrieves the current authenticated [User].
  ///
  /// Returns the [User] object if a user is currently signed in, otherwise returns `null`.
  User? getCurrentUser() {
    return _firebaseAuth.currentUser;
  }
}
