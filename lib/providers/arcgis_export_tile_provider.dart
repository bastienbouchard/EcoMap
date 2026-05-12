import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

// Convertit les coordonnées z/x/y en bbox EPSG:3857 et appelle
// le endpoint export d'un MapServer ArcGIS dynamique.
class ArcGISExportTileProvider extends TileProvider {
  final String mapServerUrl;
  final String layers;

  const ArcGISExportTileProvider({
    required this.mapServerUrl,
    this.layers = 'show:0',
  });

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    final z = coords.z;
    final x = coords.x;
    final y = coords.y;
    final n = math.pow(2, z).toDouble();
    const earthHalf = 20037508.343;
    final xMin = x / n * 2 * earthHalf - earthHalf;
    final xMax = (x + 1) / n * 2 * earthHalf - earthHalf;
    final yMax = earthHalf - y / n * 2 * earthHalf;
    final yMin = earthHalf - (y + 1) / n * 2 * earthHalf;
    final url =
        '$mapServerUrl/export?bbox=$xMin,$yMin,$xMax,$yMax'
        '&bboxSR=3857&layers=$layers&transparent=true'
        '&format=png32&f=image&size=256,256';
    return NetworkImage(url);
  }
}
