export 'compass_heading_stub.dart'
    if (dart.library.io) 'compass_heading_native.dart'
    if (dart.library.html) 'compass_heading_web.dart';
