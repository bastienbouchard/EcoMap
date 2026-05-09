import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PremiumService {
  static bool _isPremium = false;
  static bool get isPremium => _isPremium;

  static Future<void> load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _isPremium = false; return; }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      _isPremium = doc.data()?['premium'] == true;
    } catch (_) {
      _isPremium = false;
    }
  }
}
