import 'dart:async';
import 'package:http/http.dart' as http;

class ConnectivityService {
  static bool _isOnline = true;
  static bool get isOnline => _isOnline;

  static final _controller = StreamController<bool>.broadcast();
  static Stream<bool> get onStatusChange => _controller.stream;

  static Timer? _timer;

  static Future<void> init() async {
    _isOnline = await _check();
    // Vérifie toutes les 15 secondes
    _timer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final online = await _check();
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(_isOnline);
      }
    });
  }

  static void dispose() => _timer?.cancel();

  static Future<bool> _check() async {
    try {
      final resp = await http
          .head(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 4));
      return resp.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}
