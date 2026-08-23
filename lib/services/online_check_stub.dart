import 'dart:async';
import 'dart:io';

bool _lastOnline = true;

Future<bool> _checkOnline() async {
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

void listenToConnectivity(void Function(bool) callback) {
  // Vérification immédiate au démarrage
  _checkOnline().then((online) {
    _lastOnline = online;
    callback(online);
  });

  // Sondage toutes les 5 secondes
  Timer.periodic(const Duration(seconds: 5), (_) async {
    final online = await _checkOnline();
    if (online != _lastOnline) {
      _lastOnline = online;
      callback(online);
    }
  });
}
