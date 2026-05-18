import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;

dynamic _db;

Future<dynamic> _open() async {
  if (_db != null) return _db;
  final idb = js_util.getProperty(html.window, 'indexedDB');
  final req = js_util.callMethod(idb, 'open', ['ecomap_db', 1]);

  final completer = Completer<dynamic>();
  js_util.setProperty(req, 'onupgradeneeded', js_util.allowInterop((e) {
    final db = js_util.getProperty(req, 'result');
    final names = js_util.getProperty(db, 'objectStoreNames');
    final contains = js_util.callMethod(names, 'contains', ['territoires']);
    if (contains == false) {
      js_util.callMethod(db, 'createObjectStore', ['territoires']);
    }
  }));
  js_util.setProperty(req, 'onsuccess', js_util.allowInterop((_) {
    _db = js_util.getProperty(req, 'result');
    completer.complete(_db);
  }));
  js_util.setProperty(req, 'onerror', js_util.allowInterop((_) {
    completer.completeError('IndexedDB open failed');
  }));
  return completer.future;
}

Future<void> webDbPut(String store, String key, String value) async {
  final db = await _open();
  final txn = js_util.callMethod(db, 'transaction', [store, 'readwrite']);
  final os = js_util.callMethod(txn, 'objectStore', [store]);
  js_util.callMethod(os, 'put', [value, key]);
  final completer = Completer<void>();
  js_util.setProperty(txn, 'oncomplete', js_util.allowInterop((_) => completer.complete()));
  js_util.setProperty(txn, 'onerror', js_util.allowInterop((_) => completer.complete()));
  return completer.future;
}

Future<String?> webDbGet(String store, String key) async {
  final db = await _open();
  final txn = js_util.callMethod(db, 'transaction', [store, 'readonly']);
  final os = js_util.callMethod(txn, 'objectStore', [store]);
  final req = js_util.callMethod(os, 'get', [key]);
  final completer = Completer<String?>();
  js_util.setProperty(req, 'onsuccess', js_util.allowInterop((_) {
    final result = js_util.getProperty(req, 'result');
    completer.complete(result as String?);
  }));
  js_util.setProperty(req, 'onerror', js_util.allowInterop((_) => completer.complete(null)));
  return completer.future;
}

Future<void> webDbDelete(String store, String key) async {
  final db = await _open();
  final txn = js_util.callMethod(db, 'transaction', [store, 'readwrite']);
  final os = js_util.callMethod(txn, 'objectStore', [store]);
  js_util.callMethod(os, 'delete', [key]);
  final completer = Completer<void>();
  js_util.setProperty(txn, 'oncomplete', js_util.allowInterop((_) => completer.complete()));
  js_util.setProperty(txn, 'onerror', js_util.allowInterop((_) => completer.complete()));
  return completer.future;
}

Future<List<String>> webDbKeys(String store) async {
  final db = await _open();
  final txn = js_util.callMethod(db, 'transaction', [store, 'readonly']);
  final os = js_util.callMethod(txn, 'objectStore', [store]);
  final req = js_util.callMethod(os, 'getAllKeys', []);
  final completer = Completer<List<String>>();
  js_util.setProperty(req, 'onsuccess', js_util.allowInterop((_) {
    final result = js_util.getProperty(req, 'result');
    try {
      final list = (result as List).cast<String>();
      completer.complete(list);
    } catch (_) {
      completer.complete([]);
    }
  }));
  js_util.setProperty(req, 'onerror', js_util.allowInterop((_) => completer.complete([])));
  return completer.future;
}
