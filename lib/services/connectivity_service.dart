import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final _connectivity = Connectivity();
  static bool _isOnline = true;
  static bool get isOnline => _isOnline;

  static final _controller = StreamController<bool>.broadcast();
  static Stream<bool> get onStatusChange => _controller.stream;

  static Future<void> init() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = _isConnected(result);
    _connectivity.onConnectivityChanged.listen((result) {
      final online = _isConnected(result);
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(_isOnline);
      }
    });
  }

  static bool _isConnected(List<ConnectivityResult> result) =>
      result.any((r) => r != ConnectivityResult.none);
}
