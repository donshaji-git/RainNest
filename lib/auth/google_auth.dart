import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  static Future<UserCredential> signInWithGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn.instance;

    // Initialize the plugin (required for v7.x)
    await googleSignIn.initialize();

    // Start authentication (replaces signIn() in v7.x)
    final googleUser = await googleSignIn.authenticate();

    // Get auth details
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;

    // Create Firebase credential
    // Note: idToken is usually sufficient for Firebase Google Auth.
    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    // Sign in to Firebase
    UserCredential userCredential = await FirebaseAuth.instance
        .signInWithCredential(credential);
    return userCredential;
  }
}
