import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Connexion email/mot de passe ──
  static Future<UserCredential> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  static Future<UserCredential> createWithEmail(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  static Future<void> signOut() async {
    await _auth.signOut();
  }

  static Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  // ── Crée le document utilisateur s'il n'existe pas encore ──
  static Future<void> ensureUserDoc() async {
    final user = currentUser;
    if (user == null) return;
    final ref = _db.collection('users').doc(user.uid);
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        'email': user.email,
        'displayName': user.displayName ?? '',
        'premium': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
