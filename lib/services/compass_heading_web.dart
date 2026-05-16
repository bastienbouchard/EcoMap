import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

Stream<double> compassHeadingStream() {
  late StreamController<double> controller;
  void Function(html.Event)? _listener;
  controller = StreamController<double>(
    onListen: () {
      _listener = (html.Event event) {
        try {
          final heading = js_util.getProperty<num?>(event, 'webkitCompassHeading');
          if (heading != null && heading >= 0 && heading <= 360) {
            controller.add(heading.toDouble());
          }
        } catch (_) {}
      };
      html.window.addEventListener('deviceorientation', _listener!);
    },
    onCancel: () {
      if (_listener != null) {
        html.window.removeEventListener('deviceorientation', _listener!);
      }
      controller.close();
    },
  );
  return controller.stream;
}

Future<bool> requestCompassPermission() async {
  try {
    final doe = js_util.getProperty(html.window, 'DeviceOrientationEvent');
    if (js_util.hasProperty(doe, 'requestPermission')) {
      final result = await js_util.promiseToFuture<String>(
          js_util.callMethod(doe, 'requestPermission', []));
      return result == 'granted';
    }
    return true; // Android — pas de permission nécessaire
  } catch (_) {
    return false;
  }
}
