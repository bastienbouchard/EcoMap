import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _apiKey = 'AIzaSyACM479_zu4rESc_e1J_o6lBs--WzMMTPc';
  static const _baseUrl = 'https://identitytoolkit.googleapis.com/v1/accounts';
  static const _keyUid = 'auth_uid';
  static const _keyEmail = 'auth_email';
  static const _keyToken = 'auth_token';
  static const _keyRefresh = 'auth_refresh_token';

  static String? _uid;
  static String? _email;

  static bool get isLoggedIn => _uid != null;
  static String? get uid => _uid;
  static String? get email => _email;

  static bool _isExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map;
      final exp = payload['exp'] as int?;
      if (exp == null) return true;
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 > exp - 300;
    } catch (_) {
      return true;
    }
  }

  static Future<String?> getIdToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    if (token != null && !_isExpired(token)) return token;
    final refresh = prefs.getString(_keyRefresh);
    if (refresh == null) return token;
    try {
      final resp = await http.post(
        Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'grant_type=refresh_token&refresh_token=$refresh',
      );
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final newToken = data['id_token'] as String?;
      final newRefresh = data['refresh_token'] as String?;
      if (newToken != null) await prefs.setString(_keyToken, newToken);
      if (newRefresh != null) await prefs.setString(_keyRefresh, newRefresh);
      return newToken;
    } catch (_) {
      return token;
    }
  }

  static Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_keyUid);
    if (uid == null || uid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) {
        await prefs.remove(_keyUid);
        await prefs.remove(_keyEmail);
        await prefs.remove(_keyToken);
        return;
      }
    } catch (_) {}
    _uid = uid;
    _email = prefs.getString(_keyEmail);
  }

  static Future<void> createWithEmail(String email, String password) async {
    await _post('signUp', email, password);
    await _sendVerificationEmail();
  }

  static Future<void> signInWithEmail(String email, String password) async {
    await _post('signInWithPassword', email, password);
  }

  static Future<void> signOut() async {
    _uid = null;
    _email = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUid);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyToken);
  }

  static Future<void> resetPassword(String email) async {
    await http.post(
      Uri.parse('$_baseUrl:sendOobCode?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'requestType': 'PASSWORD_RESET', 'email': email}),
    );
  }

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

  static Future<void> _sendVerificationEmail() async {
    if (_uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final idToken = prefs.getString(_keyToken);
    if (idToken == null) return;
    await http.post(
      Uri.parse('$_baseUrl:sendOobCode?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'requestType': 'VERIFY_EMAIL', 'idToken': idToken}),
    );
  }

  static Future<void> _post(String endpoint, String email, String password) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl:$endpoint?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password, 'returnSecureToken': true}),
    );
    final data = json.decode(resp.body) as Map<String, dynamic>;
    if (data.containsKey('error')) throw data['error']['message'] as String;
    _uid = data['localId'] as String?;
    _email = data['email'] as String?;
    final token = data['idToken'] as String?;
    final refresh = data['refreshToken'] as String?;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUid, _uid ?? '');
    await prefs.setString(_keyEmail, _email ?? '');
    if (token != null) await prefs.setString(_keyToken, token);
    if (refresh != null) await prefs.setString(_keyRefresh, refresh);
  }
}
