import 'dart:convert';
import 'dart:io' show Directory, File;
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

  static Future<Map<String, dynamic>?> loadTerritoire(String id) async {
    if (kIsWeb) {
      final raw = await webDbGet(_dbStore, id);
      if (raw == null) return null;
      return json.decode(raw) as Map<String, dynamic>;
    }
    final path = await _territoirePath(id);
    final file = File(path);
    if (!file.existsSync()) return null;
    return json.decode(await file.readAsString());
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
    final allFeatures = <dynamic>[];
    int done = 0;
    final errors = <String>[];

    for (final tile in tiles) {
      onStatus?.call('Secteur ${done + 1} sur ${tiles.length} — téléchargement...');
      try {
        final url = Uri.parse('$_cdnBase/$tile');
        final resp = await http.get(url).timeout(const Duration(seconds: 30));
        if (resp.statusCode == 404) { done++; continue; }
        if (resp.statusCode != 200) {
          errors.add('$tile: HTTP ${resp.statusCode}');
          done++;
          continue;
        }

        String jsonStr;
        try {
          jsonStr = await decompressGzip(resp.bodyBytes);
        } catch (_) {
          jsonStr = resp.body;
        }

        final data = json.decode(jsonStr) as Map<String, dynamic>;
        final features = data['features'] as List? ?? [];

        for (final feat in features) {
          try {
            final geom = feat['geometry'] as Map;
            final coords = geom['type'] == 'Polygon'
                ? (geom['coordinates'] as List)[0] as List
                : ((geom['coordinates'] as List)[0] as List)[0] as List;
            // Inclut si au moins une coordonnée est dans le bbox (gère les polygones à cheval sur 2 tuiles)
            bool inBbox = false;
            for (final c in coords) {
              final cLon = (c[0] as num).toDouble();
              final cLat = (c[1] as num).toDouble();
              if (cLat >= minLat && cLat <= maxLat &&
                  cLon >= minLon && cLon <= maxLon) {
                inBbox = true;
                break;
              }
            }
            if (inBbox) allFeatures.add(feat);
          } catch (_) {
            // ignore les features avec géométrie invalide
          }
        }
      } catch (e) {
        errors.add('$tile: $e');
      }
      done++;
    }

    if (allFeatures.isEmpty) {
      throw Exception(
        'Aucune donnée écoforestière dans ce secteur.\n'
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
      await file.writeAsString(json.encode(geojson));
    }
    onStatus?.call('Terminé !');
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
