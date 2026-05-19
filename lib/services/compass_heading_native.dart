import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';

Stream<double> compassHeadingStream() {
  return FlutterCompass.events!
      .where((e) => e.heading != null)
      .map((e) => e.heading!);
}

Future<bool> requestCompassPermission() async => true;
