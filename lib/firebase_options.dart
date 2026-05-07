import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyACM479_zu4rESc_e1J_o6lBs--WzMMTPc',
    authDomain: 'moosesense-a84cf.firebaseapp.com',
    projectId: 'moosesense-a84cf',
    storageBucket: 'moosesense-a84cf.firebasestorage.app',
    messagingSenderId: '115558656456',
    appId: '1:115558656456:web:a5c5362023fc9f2ec038fd',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCq9Uw19VVoHkYUIlFbc2dxcEX8mk3LWU8',
    projectId: 'moosesense-a84cf',
    storageBucket: 'moosesense-a84cf.firebasestorage.app',
    messagingSenderId: '115558656456',
    appId: '1:115558656456:ios:10c2785cda77235bc038fd',
  );
}
