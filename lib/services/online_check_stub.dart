import 'dart:async';
import 'dart:io';

bool _last = true;

bool checkOnline() => _last;

void listenToConnectivity(void Function(bool) callback) {
  _poll(callback);
  Timer.periodic(const Duration(seconds: 6), (_) => _poll(callback));
}

void _poll(void Function(bool) callback) {
  Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 3)).then((s) {
    s.destroy();
    if (!_last) {
      _last = true;
      callback(true);
    }
  }).catchError((_) {
    if (_last) {
      _last = false;
      callback(false);
    }
  });
}
