import 'dart:async';
import 'online_check.dart';

class ConnectivityService {
  static bool _isOnline = true;
  static bool get isOnline => _isOnline;

  static final _controller = StreamController<bool>.broadcast();
  static Stream<bool> get onStatusChange => _controller.stream;

  static Future<void> init() async {
    listenToConnectivity((online) {
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(_isOnline);
      }
    });
  }

  static void dispose() {}
}
