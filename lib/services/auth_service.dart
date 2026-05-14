import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Authentification via Firebase REST API — pas de plugin natif, fonctionne sur web
class AuthService {
  static const _apiKey = 'AIzaSyACM479_zu4rESc_e1J_o6lBs--WzMMTPc';
  static const _baseUrl = 'https://identitytoolkit.googleapis.com/v1/accounts';
  static const _keyUid = 'auth_uid';
  static const _keyEmail = 'auth_email';
  static const _keyToken = 'auth_token';

  static String? _uid;
  static String? _email;

  static bool get isLoggedIn => _uid != null;
  static String? get uid => _uid;
  static String? get email => _email;

  static Future<String?> getIdToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  // ── Restaure la session depuis le stockage local ──
  static Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_keyUid);
    if (uid == null || uid.isEmpty) return;
    // Vérifie que le document Firestore existe encore
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) {
        await prefs.remove(_keyUid);
        await prefs.remove(_keyEmail);
        await prefs.remove(_keyToken);
        return;
      }
    } catch (_) {
      // Pas de réseau — on accepte la session locale
    }
    _uid = uid;
    _email = prefs.getString(_keyEmail);
  }

  // ── Créer un compte ──
  static Future<void> createWithEmail(String email, String password) async {
    await _post('signUp', email, password);
    await _sendVerificationEmail();
  }

  // ── Envoie un courriel de confirmation d'inscription ──
  static Future<void> _sendVerificationEmail() async {
    if (_uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final idToken = prefs.getString('auth_token');
    if (idToken == null) return;
    await http.post(
      Uri.parse('$_baseUrl:sendOobCode?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'requestType': 'VERIFY_EMAIL', 'idToken': idToken}),
    );
  }

  // ── Se connecter ──
  static Future<void> signInWithEmail(String email, String password) async {
    await _post('signInWithPassword', email, password);
  }

  // ── Se déconnecter ──
  static Future<void> signOut() async {
    _uid = null;
    _email = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUid);
    await prefs.remove(_keyEmail);
  }

  // ── Réinitialiser mot de passe ──
  static Future<void> resetPassword(String email) async {
    await http.post(
      Uri.parse('$_baseUrl:sendOobCode?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'requestType': 'PASSWORD_RESET', 'email': email}),
    );
  }

  // ── Crée le document Firestore si pas encore là ──
  static Future<void> ensureUserDoc() async {
    if (_uid == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(_uid);
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        'email': _email,
        'premium': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Appel REST ──
  static Future<void> _post(String endpoint, String email, String password) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl:$endpoint?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );
    final data = json.decode(resp.body) as Map<String, dynamic>;
    if (data.containsKey('error')) {
      throw data['error']['message'] as String;
    }
    _uid = data['localId'] as String?;
    _email = data['email'] as String?;
    final token = data['idToken'] as String?;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUid, _uid ?? '');
    await prefs.setString(_keyEmail, _email ?? '');
    if (token != null) await prefs.setString(_keyToken, token);
  }
}
