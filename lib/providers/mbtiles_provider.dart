import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../app_globals.dart';

class MBTilesProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    return MBTilesImageProvider(coords);
  }
}

class MBTilesImageProvider extends ImageProvider<MBTilesImageProvider> {
  final TileCoordinates coords;
  const MBTilesImageProvider(this.coords);

  @override
  Future<MBTilesImageProvider> obtainKey(ImageConfiguration config) async => this;

  @override
  ImageStreamCompleter loadImage(MBTilesImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_loadTile(decode));
  }

  Future<ImageInfo> _loadTile(ImageDecoderCallback decode) async {
    final z = coords.z;
    final x = coords.x;
    final y = (1 << z) - 1 - coords.y;
    final result = await db.query(
      'tiles',
      columns: ['tile_data'],
      where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
      whereArgs: [z, x, y],
    );
    if (result.isEmpty) throw Exception('Tuile introuvable');
    final bytes = result.first['tile_data'] as Uint8List;
    final buffer = await ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is MBTilesImageProvider && coords == other.coords;

  @override
  int get hashCode => coords.hashCode;
}
