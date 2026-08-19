import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

class SatelliteCacheService {
  static Database? _db;

  static Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      '$dir/sat_tiles.db',
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE tiles(url TEXT PRIMARY KEY, data BLOB, ts INTEGER)',
      ),
    );
    return _db!;
  }

  static Future<Uint8List?> getTile(String url) async {
    final db = await _database;
    final rows = await db.query('tiles', columns: ['data'], where: 'url = ?', whereArgs: [url]);
    if (rows.isEmpty) return null;
    return rows.first['data'] as Uint8List;
  }

  static Future<void> putTile(String url, Uint8List data) async {
    final db = await _database;
    await db.insert(
      'tiles',
      {'url': url, 'data': data, 'ts': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static int _lonToX(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor();
  static int _latToY(double lat, int z) {
    final r = lat * math.pi / 180;
    return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z)).floor();
  }

  static int estimateTileCount(
    double minLat, double minLon, double maxLat, double maxLon, {
    int minZoom = 10, int maxZoom = 14,
  }) {
    int total = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final x0 = _lonToX(minLon, z), x1 = _lonToX(maxLon, z);
      final y0 = _latToY(maxLat, z), y1 = _latToY(minLat, z);
      total += (x1 - x0 + 1) * (y1 - y0 + 1);
    }
    return total;
  }

  static Future<void> downloadTiles({
    required String urlTemplate,
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    int minZoom = 10,
    int maxZoom = 14,
    void Function(int done, int total, String status)? onProgress,
  }) async {
    final urls = <String>[];
    for (int z = minZoom; z <= maxZoom; z++) {
      final x0 = _lonToX(minLon, z), x1 = _lonToX(maxLon, z);
      final y0 = _latToY(maxLat, z), y1 = _latToY(minLat, z);
      for (int x = x0; x <= x1; x++) {
        for (int y = y0; y <= y1; y++) {
          urls.add(urlTemplate
              .replaceAll('{z}', '$z')
              .replaceAll('{x}', '$x')
              .replaceAll('{y}', '$y'));
        }
      }
    }

    final total = urls.length;
    int done = 0;
    int errors = 0;
    final client = http.Client();
    try {
      for (final url in urls) {
        final existing = await getTile(url);
        if (existing != null) {
          done++;
          onProgress?.call(done, total, 'Tuile $done/$total');
          continue;
        }
        try {
          final resp = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            await putTile(url, resp.bodyBytes);
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
          errors > 0 ? 'Tuile $done/$total ($errors erreurs)' : 'Tuile $done/$total',
        );
      }
    } finally {
      client.close();
    }
  }

  static Future<int> countCachedTiles() async {
    final db = await _database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM tiles');
    return (r.first['c'] as int?) ?? 0;
  }

  static Future<void> clearCache() async {
    final db = await _database;
    await db.delete('tiles');
  }
}

// ── Semaphore pour limiter les requêtes réseau simultanées ──────────────────

class _Semaphore {
  final int _max;
  int _available;
  final _queue = <Completer<void>>[];

  _Semaphore(int max)
      : _max = max,
        _available = max;

  Future<void> acquire() async {
    if (_available > 0) {
      _available--;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _available++;
    }
  }
}

// ── Custom TileProvider qui sert les tuiles pré-chargées hors-ligne ─────────

class SatelliteTileProvider extends TileProvider {
  SatelliteTileProvider();

  @override
  ImageProvider<Object> getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImageProvider(getTileUrl(coordinates, options));
  }
}

class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  final String url;
  const _CachedTileImageProvider(this.url);

  static final _sem = _Semaphore(6);

  static Future<ui.Codec> _emptyCodec() async {
    final bytes = Uint8List(4); // 1×1 pixel RGBA transparent
    final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.raw(
      buf,
      width: 1,
      height: 1,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    return desc.instantiateCodec();
  }

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _CachedTileImageProvider key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _loadAsync(decode),
        scale: 1.0,
        debugLabel: url,
      );

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    try {
      final cached = await SatelliteCacheService.getTile(url);
      if (cached != null) {
        final buffer = await ui.ImmutableBuffer.fromUint8List(cached);
        return decode(buffer);
      }
      await _sem.acquire();
      Uint8List? tileData;
      try {
        final client = http.Client();
        try {
          final resp = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 6));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            tileData = resp.bodyBytes;
          }
        } finally {
          client.close();
        }
      } finally {
        _sem.release();
      }
      if (tileData != null) {
        SatelliteCacheService.putTile(url, tileData);
        final buffer = await ui.ImmutableBuffer.fromUint8List(tileData);
        return decode(buffer);
      }
    } catch (_) {}
    return _emptyCodec();
  }

  @override
  bool operator ==(Object other) => other is _CachedTileImageProvider && url == other.url;

  @override
  int get hashCode => url.hashCode;
}
