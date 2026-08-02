import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../providers/cached_satellite_provider.dart';

const _kSatUrl =
    'https://servicesmatriciels.mern.gouv.qc.ca/erdas-iws/ogc/wmts/Imagerie_Continue?layer=Imagerie_GQ&style=default&tilematrixset=GoogleMapsCompatibleExt2:epsg:3857&Service=WMTS&Request=GetTile&Version=1.0.0&Format=image/jpeg&TileMatrix={z}&TileCol={x}&TileRow={y}';

String _tileUrl(int z, int x, int y) => _kSatUrl
    .replaceAll('{z}', '$z')
    .replaceAll('{x}', '$x')
    .replaceAll('{y}', '$y');

(int x, int y) _toTile(double lat, double lon, int z) {
  final n = math.pow(2, z).toDouble();
  final x = ((lon + 180) / 360 * n).floor();
  final latRad = lat * math.pi / 180;
  final y = ((1 -
              math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
          2 *
          n)
      .floor();
  return (x, y);
}

class TileDownloadService {
  static int estimateTileCount(LatLngBounds bounds, int minZ, int maxZ) {
    int n = 0;
    for (int z = minZ; z <= maxZ; z++) {
      final (x0, y0) = _toTile(bounds.north, bounds.west, z);
      final (x1, y1) = _toTile(bounds.south, bounds.east, z);
      n += (x1 - x0 + 1).abs() * (y1 - y0 + 1).abs();
    }
    return n;
  }

  static Future<void> downloadRegion({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required void Function(int done, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final total = estimateTileCount(bounds, minZoom, maxZoom);
    int done = 0;
    final client = http.Client();
    try {
      for (int z = minZoom; z <= maxZoom; z++) {
        if (isCancelled()) break;
        final (x0, y0) = _toTile(bounds.north, bounds.west, z);
        final (x1, y1) = _toTile(bounds.south, bounds.east, z);
        final xMin = math.min(x0, x1);
        final xMax = math.max(x0, x1);
        final yMin = math.min(y0, y1);
        final yMax = math.max(y0, y1);

        // 4 téléchargements en parallèle
        final pending = <Future>[];
        for (int x = xMin; x <= xMax; x++) {
          for (int y = yMin; y <= yMax; y++) {
            if (isCancelled()) break;
            pending.add(_downloadOne(client, z, x, y).then((_) {
              done++;
              onProgress(done, total);
            }));
            if (pending.length >= 4) {
              await Future.wait(pending);
              pending.clear();
            }
          }
        }
        if (pending.isNotEmpty) await Future.wait(pending);
      }
    } finally {
      client.close();
    }
  }

  static Future<void> _downloadOne(http.Client client, int z, int x, int y) async {
    final file = CachedSatelliteTileProvider.fileForTile(z, x, y);
    if (file == null || await file.exists()) return;
    try {
      final res = await client
          .get(Uri.parse(_tileUrl(z, x, y)))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(res.bodyBytes);
      }
    } catch (_) {}
  }

  static Future<int> cachedTileCount() =>
      CachedSatelliteTileProvider.cachedTileCount();

  static Future<void> clearCache() =>
      CachedSatelliteTileProvider.clearCache();
}
