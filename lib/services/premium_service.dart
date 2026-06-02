import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class PremiumService {
  static bool _isPremium = false;
  static bool get isPremium => _isPremium;

  static Future<void> activerPremium() async {
    final uid = AuthService.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'premium': true});
    _isPremium = true;
  }

  static Future<void> load() async {
    final uid = AuthService.uid;
    if (uid == null) { _isPremium = false; return; }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      _isPremium = doc.data()?['premium'] == true;
    } catch (_) {
      _isPremium = false;
    }
  }
}
