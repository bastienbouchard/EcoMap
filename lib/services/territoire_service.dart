import 'dart:convert';
import 'dart:io' show Directory, File, GZipCodec;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'gzip_helper.dart';
import 'web_db.dart';

const _cdnBase = 'https://pub-5c51ef289e6943dbb647c2a2d1baa3bf.r2.dev';
const _dbStore = 'territoires';

class TerritoireService {
  static Future<String> _territoirePath(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/territoires/$id.geojson';
  }

  static String _tileName(double lat, double lon) {
    final latFloor = (lat * 2).floor() / 2;
    final lonFloor = (lon * 2).floor() / 2;
    final latInt = latFloor.floor();
    final latFrac = ((latFloor - latInt) * 10).round();
    final lonAbs = lonFloor.abs();
    final lonInt = lonAbs.floor();
    final lonFrac = ((lonAbs - lonInt) * 10).round();
    final lonSign = lon < 0 ? 'm' : '';
    return '${latInt}d${latFrac}_$lonSign${lonInt}d$lonFrac.geojson.gz';
  }

  static List<String> _tilesForBbox(
      double minLat, double minLon, double maxLat, double maxLon) {
    final tiles = <String>[];
    var lat = (minLat * 2).floor() / 2.0;
    while (lat <= maxLat) {
      var lon = (minLon * 2).floor() / 2.0;
      while (lon <= maxLon) {
        tiles.add(_tileName(lat, lon));
        lon += 0.5;
      }
      lat += 0.5;
    }
    return tiles;
  }

  static Future<List<Map<String, dynamic>>> listTerritoires() async {
    if (kIsWeb) {
      final keys = await webDbKeys(_dbStore);
      return keys.map((k) => {'id': k, 'taille_mb': '?'}).toList();
    }
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/territoires');
    if (!folder.existsSync()) return [];
    return folder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.geojson'))
        .map((f) {
          final nom = f.path.split('/').last.replaceAll('.geojson', '');
          final size = (f.lengthSync() / 1024 / 1024);
          return {'id': nom, 'taille_mb': size.toStringAsFixed(1)};
        })
        .toList();
  }

  static int estimateTileCount(
      double minLat, double minLon, double maxLat, double maxLon) {
    return _tilesForBbox(minLat, minLon, maxLat, maxLon).length;
  }

  static Future<Map<String, dynamic>?> loadTerritoire(String id) async {
    if (kIsWeb) {
      final raw = await webDbGet(_dbStore, id);
      if (raw == null) return null;
      return json.decode(raw) as Map<String, dynamic>;
    }
    final path = await _territoirePath(id);
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    String jsonStr;
    try {
      jsonStr = utf8.decode(GZipCodec().decode(bytes));
    } catch (_) {
      jsonStr = utf8.decode(bytes); // fallback : ancien fichier non compressé
    }
    return json.decode(jsonStr) as Map<String, dynamic>;
  }

  static bool _bboxIntersects(
    List coords,
    double minLat, double minLon, double maxLat, double maxLon,
  ) {
    double fMinLat = double.infinity, fMaxLat = double.negativeInfinity;
    double fMinLon = double.infinity, fMaxLon = double.negativeInfinity;
    for (final c in coords) {
      final cLon = (c[0] as num).toDouble();
      final cLat = (c[1] as num).toDouble();
      if (cLat < fMinLat) fMinLat = cLat;
      if (cLat > fMaxLat) fMaxLat = cLat;
      if (cLon < fMinLon) fMinLon = cLon;
      if (cLon > fMaxLon) fMaxLon = cLon;
    }
    return fMaxLat >= minLat && fMinLat <= maxLat &&
           fMaxLon >= minLon && fMinLon <= maxLon;
  }

  static Future<void> downloadTerritoire({
    required String nom,
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    void Function(String)? onStatus,
  }) async {
    final tiles = _tilesForBbox(minLat, minLon, maxLat, maxLon);
    const maxPolygons = 80000;
    final allFeatures = <dynamic>[];
    int done = 0;
    final errors = <String>[];
    int tilesOk = 0, tiles404 = 0, tilesErr = 0, totalParsed = 0;

    for (final tile in tiles) {
      onStatus?.call('Secteur ${done + 1}/${tiles.length} — téléchargement...');
      try {
        final url = Uri.parse('$_cdnBase/$tile');
        final resp = await http.get(url).timeout(const Duration(seconds: 30));
        if (resp.statusCode == 404) { tiles404++; done++; continue; }
        if (resp.statusCode != 200) {
          tilesErr++;
          errors.add('$tile: HTTP ${resp.statusCode}');
          done++;
          continue;
        }

        String jsonStr;
        bool usedFallback = false;
        try {
          jsonStr = await decompressGzip(resp.bodyBytes);
        } catch (_) {
          jsonStr = resp.body;
          usedFallback = true;
        }

        final data = json.decode(jsonStr) as Map<String, dynamic>;
        final features = data['features'] as List? ?? [];
        totalParsed += features.length;
        int inBbox = 0;

        for (final feat in features) {
          try {
            final geom = feat['geometry'];
            if (geom == null) continue;
            final geomMap = geom as Map;
            final type = geomMap['type'] as String?;
            if (type == null) continue;
            List rings;
            if (type == 'Polygon') {
              rings = [(geomMap['coordinates'] as List)[0] as List];
            } else if (type == 'MultiPolygon') {
              rings = (geomMap['coordinates'] as List)
                  .map((p) => (p as List)[0] as List)
                  .toList();
            } else {
              continue;
            }
            bool ok = rings.any((r) => _bboxIntersects(r, minLat, minLon, maxLat, maxLon));
            if (ok) { allFeatures.add(feat); inBbox++; }
          } catch (_) {}
        }

        tilesOk++;
        onStatus?.call(
          'Tuile ${done + 1}/${tiles.length}: ${features.length} polygones'
          ' → $inBbox sélectionnés${usedFallback ? " (fallback)" : ""}',
        );

        if (allFeatures.length > maxPolygons) {
          throw Exception(
            'Zone trop grande — ${allFeatures.length} polygones dépassent la limite de $maxPolygons.\n\n'
            'Zoome sur un secteur de chasse précis (2–3 tuiles max) et réessaie.',
          );
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('trop grande')) rethrow;
        tilesErr++;
        errors.add('$tile: $e');
      }
      done++;
    }

    if (allFeatures.isEmpty) {
      throw Exception(
        'Aucune donnée écoforestière dans ce secteur.\n'
        'Tuiles: $tilesOk OK, $tiles404 absentes, $tilesErr erreurs. '
        'Polygones parsés: $totalParsed, dans la zone: 0.\n'
        'Essaie de dézoomer ou de te déplacer vers une zone plus forestière.',
      );
    }

    onStatus?.call('Sauvegarde (${allFeatures.length} polygones)...');
    final geojson = {
      'type': 'FeatureCollection',
      'features': allFeatures,
    };

    if (kIsWeb) {
      await webDbPut(_dbStore, nom, json.encode(geojson));
    } else {
      final path = await _territoirePath(nom);
      final file = File(path);
      await file.parent.create(recursive: true);
      final compressed = GZipCodec().encode(utf8.encode(json.encode(geojson)));
      await file.writeAsBytes(compressed);
    }
    onStatus?.call(
      'Terminé — ${allFeatures.length} polygones, '
      '$tilesOk tuiles, $tiles404 absentes'
      '${tilesErr > 0 ? ", $tilesErr erreurs" : ""}',
    );
  }

  static Future<void> deleteTerritoire(String id) async {
    if (kIsWeb) {
      await webDbDelete(_dbStore, id);
      return;
    }
    final path = await _territoirePath(id);
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}
