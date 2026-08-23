import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class MbtilesZone {
  final String name;
  final String path;
  final double sizeMb;
  final int maxZoom;
  const MbtilesZone({
    required this.name,
    required this.path,
    required this.sizeMb,
    required this.maxZoom,
  });
}

class MbtilesService {
  static const _kActiveZone = 'offline_zone_name';
  static final Map<String, Database> _dbs = {};

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/mbtiles');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<String> pathFor(String name) async {
    final d = await _dir();
    return '${d.path}/$name.mbtiles';
  }

  static Future<Database> _openDb(String path, {bool create = false}) async {
    if (_dbs.containsKey(path)) return _dbs[path]!;
    final db = await openDatabase(
      path,
      readOnly: !create,
      version: 1,
      onCreate: create
          ? (db, _) async {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS tiles (
                  zoom_level INTEGER NOT NULL,
                  tile_column INTEGER NOT NULL,
                  tile_row INTEGER NOT NULL,
                  tile_data BLOB NOT NULL,
                  PRIMARY KEY (zoom_level, tile_column, tile_row)
                )''');
              await db.execute(
                  'CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT)');
            }
          : null,
    );
    _dbs[path] = db;
    return db;
  }

  static void closeDb(String path) {
    _dbs.remove(path)?.close();
  }

  // TMS Y-flip : MBTiles numérote Y depuis le bas, XYZ depuis le haut
  static int _tmsY(int xyzY, int z) => (1 << z) - 1 - xyzY;

  static int _lonToX(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor();
  static int _latToY(double lat, int z) {
    final r = lat * math.pi / 180;
    return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z)).floor();
  }

  static int estimateTileCount(
    double minLat,
    double minLon,
    double maxLat,
    double maxLon, {
    int minZoom = 10,
    int maxZoom = 16,
  }) {
    int total = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final x0 = _lonToX(minLon, z), x1 = _lonToX(maxLon, z);
      final y0 = _latToY(maxLat, z), y1 = _latToY(minLat, z);
      total += (x1 - x0 + 1) * (y1 - y0 + 1);
    }
    return total;
  }

  static Future<Uint8List?> readTile(String dbPath, int z, int x, int y) async {
    if (!File(dbPath).existsSync()) return null;
    try {
      final db = await _openDb(dbPath);
      final rows = await db.query(
        'tiles',
        columns: ['tile_data'],
        where: 'zoom_level=? AND tile_column=? AND tile_row=?',
        whereArgs: [z, x, _tmsY(y, z)],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['tile_data'] as Uint8List?;
    } catch (_) {
      return null;
    }
  }

  // Télécharge un template URL dans le fichier .mbtiles de la zone.
  // Plusieurs appels successifs avec des templates différents fusionnent les tuiles
  // dans le même fichier (INSERT OR REPLACE).
  static Future<void> downloadZone({
    required String name,
    required String urlTemplate,
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    int minZoom = 10,
    int maxZoom = 16,
    void Function(int done, int total, String status)? onProgress,
  }) async {
    final path = await pathFor(name);
    closeDb(path);
    final db = await _openDb(path, create: true);

    await db.insert('metadata', {'name': 'name', 'value': name},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('metadata', {'name': 'minzoom', 'value': '$minZoom'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('metadata', {'name': 'maxzoom', 'value': '$maxZoom'},
        conflictAlgorithm: ConflictAlgorithm.replace);

    final tiles = <(int, int, int)>[];
    for (int z = minZoom; z <= maxZoom; z++) {
      final x0 = _lonToX(minLon, z), x1 = _lonToX(maxLon, z);
      final y0 = _latToY(maxLat, z), y1 = _latToY(minLat, z);
      for (int x = x0; x <= x1; x++) {
        for (int y = y0; y <= y1; y++) tiles.add((z, x, y));
      }
    }

    int done = 0, errors = 0;
    final total = tiles.length;
    final client = http.Client();
    try {
      var batch = db.batch();
      int batchCount = 0;

      for (final (z, x, y) in tiles) {
        final url = urlTemplate
            .replaceAll('{z}', '$z')
            .replaceAll('{x}', '$x')
            .replaceAll('{y}', '$y');
        try {
          final resp =
              await client.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            batch.insert(
              'tiles',
              {
                'zoom_level': z,
                'tile_column': x,
                'tile_row': _tmsY(y, z),
                'tile_data': resp.bodyBytes,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            batchCount++;
            if (batchCount >= 100) {
              await batch.commit(noResult: true);
              batch = db.batch();
              batchCount = 0;
            }
          } else {
            errors++;
          }
        } catch (_) {
          errors++;
        }
        done++;
        onProgress?.call(
          done,
          total,
          errors > 0 ? '$done/$total ($errors erreurs)' : '$done/$total',
        );
      }
      if (batchCount > 0) await batch.commit(noResult: true);
    } finally {
      client.close();
    }
  }

  static Future<List<MbtilesZone>> listZones() async {
    final d = await _dir();
    if (!d.existsSync()) return [];
    // Exclure les variantes _topo et _base — elles appartiennent à leur zone principale
    final files = d.listSync().whereType<File>().where((f) =>
        f.path.endsWith('.mbtiles') &&
        !f.path.endsWith('_topo.mbtiles') &&
        !f.path.endsWith('_base.mbtiles'));
    final zones = <MbtilesZone>[];
    for (final f in files) {
      final name = f.path.split('/').last.replaceAll('.mbtiles', '');
      final sizeMb = f.lengthSync() / 1024 / 1024;
      int maxZoom = 16;
      try {
        final db = await _openDb(f.path);
        final rows = await db.query('metadata', where: 'name=?', whereArgs: ['maxzoom']);
        if (rows.isNotEmpty) {
          maxZoom = int.tryParse(rows.first['value'] as String? ?? '') ?? 16;
        }
      } catch (_) {}
      zones.add(MbtilesZone(name: name, path: f.path, sizeMb: sizeMb, maxZoom: maxZoom));
    }
    zones.sort((a, b) => a.name.compareTo(b.name));
    return zones;
  }

  static Future<void> deleteZone(String name) async {
    final path = await pathFor(name);
    closeDb(path);
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kActiveZone) == name) await prefs.remove(_kActiveZone);
  }

  static Future<int> getMaxZoom(String path) async {
    if (!File(path).existsSync()) return 16;
    try {
      final db = await _openDb(path);
      final rows = await db.query('metadata', where: 'name=?', whereArgs: ['maxzoom']);
      if (rows.isNotEmpty) {
        return int.tryParse(rows.first['value'] as String? ?? '') ?? 16;
      }
    } catch (_) {}
    return 16;
  }

  static Future<void> setActiveZone(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveZone, name);
  }

  static Future<String?> getActiveZone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kActiveZone);
  }
}
