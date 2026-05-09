import 'dart:async';
import 'online_check.dart';

class ConnectivityService {
  static bool _isOnline = true;
  static bool get isOnline => _isOnline;

  static final _controller = StreamController<bool>.broadcast();
  static Stream<bool> get onStatusChange => _controller.stream;

  static Timer? _timer;

  static Future<void> init() async {
    _isOnline = checkOnline();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final online = checkOnline();
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(_isOnline);
      }
    });
  }

  static void dispose() => _timer?.cancel();
}
