import 'dart:js_interop';

@JS('navigator.onLine')
external bool get _navigatorOnLine;

bool checkOnline() => _navigatorOnLine;
