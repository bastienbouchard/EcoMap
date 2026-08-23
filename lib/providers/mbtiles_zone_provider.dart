import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/mbtiles_service.dart';

class MbtilesZoneTileProvider extends TileProvider {
  final String dbPath;
  MbtilesZoneTileProvider(this.dbPath);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _MbtilesZoneImageProvider(dbPath: dbPath, coords: coordinates);
  }
}

class _MbtilesZoneImageProvider extends ImageProvider<_MbtilesZoneImageProvider> {
  final String dbPath;
  final TileCoordinates coords;
  const _MbtilesZoneImageProvider({required this.dbPath, required this.coords});

  @override
  Future<_MbtilesZoneImageProvider> obtainKey(ImageConfiguration config) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _MbtilesZoneImageProvider key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes =
          await MbtilesService.readTile(dbPath, coords.z, coords.x, coords.y);
      if (bytes != null && bytes.isNotEmpty) {
        final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
        return decode(buf);
      }
    } catch (_) {}
    return _emptyCodec();
  }

  static Future<ui.Codec> _emptyCodec() async {
    final bytes = Uint8List(4);
    final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = ui.ImageDescriptor.raw(
      buf,
      width: 1,
      height: 1,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    return desc.instantiateCodec();
  }

  @override
  bool operator ==(Object other) =>
      other is _MbtilesZoneImageProvider &&
      dbPath == other.dbPath &&
      coords == other.coords;

  @override
  int get hashCode => Object.hash(dbPath, coords);
}
