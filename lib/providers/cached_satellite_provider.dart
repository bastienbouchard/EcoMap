import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class CachedSatelliteTileProvider extends TileProvider {
  static Directory? _dir;
  static final http.Client _client = http.Client();

  static Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/tile_cache/sat');
    await _dir!.create(recursive: true);
  }

  static File? fileForTile(int z, int x, int y) {
    if (_dir == null) return null;
    return File('${_dir!.path}/$z/$x/$y.jpg');
  }

  static Future<int> cachedTileCount() async {
    if (_dir == null) return 0;
    int n = 0;
    await for (final e in _dir!.list(recursive: true)) {
      if (e is File) n++;
    }
    return n;
  }

  static Future<void> clearCache() async {
    if (_dir == null) return;
    await _dir!.delete(recursive: true);
    await _dir!.create();
  }

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    final url = getTileUrl(coords, options);
    return _CachedTileImage(
      url: url,
      cacheFile: fileForTile(coords.z, coords.x, coords.y),
      client: _client,
    );
  }
}

// Minimal 1×1 transparent JPEG — shown when tile is unavailable offline
final Uint8List _kFallback = Uint8List.fromList(const [
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
  0x00, 0x10, 0x0B, 0x0C, 0x0E, 0x0C, 0x0A, 0x10, 0x0E, 0x0D, 0x0E, 0x12,
  0x11, 0x10, 0x13, 0x18, 0x28, 0x1A, 0x18, 0x16, 0x16, 0x18, 0x31, 0x23,
  0x25, 0x1D, 0x28, 0x3A, 0x33, 0x3D, 0x3C, 0x39, 0x33, 0x38, 0x37, 0x40,
  0x48, 0x5C, 0x4E, 0x40, 0x44, 0x57, 0x45, 0x37, 0x38, 0x50, 0x6D, 0x51,
  0x57, 0x5F, 0x62, 0x67, 0x68, 0x67, 0x3E, 0x4D, 0x71, 0x79, 0x70, 0x64,
  0x78, 0x5C, 0x65, 0x67, 0x63, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
  0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
  0x7F, 0xFF, 0xD9,
]);

class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  final String url;
  final File? cacheFile;
  final http.Client client;

  const _CachedTileImage({
    required this.url,
    required this.cacheFile,
    required this.client,
  });

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration config) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _CachedTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    Uint8List bytes;
    final file = cacheFile;
    if (file != null && await file.exists()) {
      bytes = await file.readAsBytes();
    } else {
      try {
        final res = await client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          bytes = res.bodyBytes;
          if (file != null) {
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes);
          }
        } else {
          bytes = _kFallback;
        }
      } catch (_) {
        bytes = _kFallback;
      }
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CachedTileImage && url == other.url;

  @override
  int get hashCode => url.hashCode;
}
