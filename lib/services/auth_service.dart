import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;

  static bool get isLoggedIn => _auth.currentUser != null;
  static String? get uid => _auth.currentUser?.uid;
  static String? get email => _auth.currentUser?.email;

  static Future<String?> getIdToken() => _auth.currentUser?.getIdToken() ?? Future.value(null);

  // firebase_auth restaure la session automatiquement — rien à faire
  static Future<void> restoreSession() async {}

  static Future<void> createWithEmail(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: password);
    await _auth.currentUser?.sendEmailVerification();
  }

  static Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }

  static Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  static Future<void> ensureUserDoc() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        'email': user.email,
        'premium': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
