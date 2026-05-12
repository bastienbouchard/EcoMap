import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

// Proxy Firebase pour éviter le CORS sur les serveurs ArcGIS du gouvernement QC.
// La Cloud Function tile_proxy reçoit (layer, z, x, y) et retourne un PNG 256×256.
class ArcGISExportTileProvider extends TileProvider {
  final String layer; // 'patp' ou 'cadastre'

  static const _proxy =
      'https://us-central1-moosesense-a84cf.cloudfunctions.net/tile_proxy';

  const ArcGISExportTileProvider({required this.layer});

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    final url = '$_proxy?layer=$layer&z=${coords.z}&x=${coords.x}&y=${coords.y}';
    return NetworkImage(url);
  }
}
