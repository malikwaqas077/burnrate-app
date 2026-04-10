import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _googleInitialized = false;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUpWithEmail(String email, String password) {
    return _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential?> signInWithGoogle() async {
    final gsi = GoogleSignIn.instance;

    if (!_googleInitialized) {
      await gsi.initialize();
      _googleInitialized = true;
    }

    final completer = Completer<UserCredential?>();
    late StreamSubscription<GoogleSignInAuthenticationEvent> sub;

    sub = gsi.authenticationEvents.listen((event) async {
      try {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          final account = event.user;
          final googleAuth = account.authentication;
          final credential = GoogleAuthProvider.credential(
            idToken: googleAuth.idToken,
          );
          final result = await _auth.signInWithCredential(credential);
          if (!completer.isCompleted) completer.complete(result);
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          if (!completer.isCompleted) completer.complete(null);
        }
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      } finally {
        sub.cancel();
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
      sub.cancel();
    });

    if (gsi.supportsAuthenticate()) {
      await gsi.authenticate();
    }

    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        sub.cancel();
        return null;
      },
    );
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {}
    await _auth.signOut();
  }
}
