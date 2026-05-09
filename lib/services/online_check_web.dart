// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool checkOnline() => html.window.navigator.onLine ?? true;

void listenToConnectivity(void Function(bool) callback) {
  html.window.addEventListener('online', (_) => callback(true));
  html.window.addEventListener('offline', (_) => callback(false));
}
