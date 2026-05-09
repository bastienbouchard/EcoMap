// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool checkOnline() => html.window.navigator.onLine ?? true;
