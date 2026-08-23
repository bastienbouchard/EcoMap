import 'dart:async';
import 'dart:io';

bool _lastOnline = true;

// DNS lookup peut retourner un résultat caché par iOS même en mode avion.
// On utilise une connexion TCP réelle : impossible de satisfaire depuis le cache.
Future<bool> _checkOnline() async {
  try {
    final socket = await Socket.connect(
      '8.8.8.8', 53,
      timeout: const Duration(seconds: 3),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

void listenToConnectivity(void Function(bool) callback) {
  _checkOnline().then((online) {
    _lastOnline = online;
    callback(online);
  });

  Timer.periodic(const Duration(seconds: 5), (_) async {
    final online = await _checkOnline();
    if (online != _lastOnline) {
      _lastOnline = online;
      callback(online);
    }
  });
}
