import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';

Stream<double> compassHeadingStream() {
  final events = FlutterCompass.events;
  if (events == null) return const Stream.empty();
  return events.where((e) => e.heading != null).map((e) => e.heading!);
}

Future<bool> requestCompassPermission() async => true;
