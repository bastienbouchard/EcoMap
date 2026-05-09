// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool _online = true;
bool _initialized = false;

bool checkOnline() {
  if (!_initialized) {
    _initialized = true;
    _online = html.window.navigator.onLine ?? true;
    html.window.addEventListener('online', (_) { _online = true; });
    html.window.addEventListener('offline', (_) { _online = false; });
  }
  return _online;
}
