import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ecomap/services/mbtiles_service.dart';

// Miroir des fonctions privées de MbtilesService pour les tester directement
int _tmsY(int xyzY, int z) => (1 << z) - 1 - xyzY;
int _lonToX(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor();
int _latToY(double lat, int z) {
  final r = lat * math.pi / 180;
  return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z)).floor();
}

// Miroir de _squareBounds() de territoire_download_page.dart
({double minLat, double minLon, double maxLat, double maxLon}) _squareBounds({
  required double mapWidth,
  required double mapHeight,
  required double visNorth,
  required double visSouth,
  required double visEast,
  required double visWest,
  required double centerLat,
  required double centerLon,
}) {
  final sqSide = math.min(mapWidth, mapHeight) - 80.0;
  final fracW = mapWidth > 0 ? sqSide / mapWidth : 0.8;
  final fracH = mapHeight > 0 ? sqSide / mapHeight : 0.8;
  final halfLat = (visNorth - visSouth) * fracH / 2;
  final halfLon = (visEast - visWest) * fracW / 2;
  return (
    minLat: centerLat - halfLat,
    maxLat: centerLat + halfLat,
    minLon: centerLon - halfLon,
    maxLon: centerLon + halfLon,
  );
}

void main() {
  group('TMS Y-flip', () {
    test('est sa propre inverse (flip(flip(y)) == y)', () {
      for (int z = 10; z <= 17; z++) {
        final maxY = (1 << z) - 1;
        for (final y in [0, 1, 100, maxY ~/ 2, maxY - 1, maxY]) {
          expect(_tmsY(_tmsY(y, z), z), y,
              reason: 'TMS flip doit être son propre inverse à z=$z, y=$y');
        }
      }
    });

    test('retourne 0 pour y=maxY', () {
      for (int z = 10; z <= 16; z++) {
        final maxY = (1 << z) - 1;
        expect(_tmsY(maxY, z), 0);
      }
    });

    test('retourne maxY pour y=0', () {
      for (int z = 10; z <= 16; z++) {
        final maxY = (1 << z) - 1;
        expect(_tmsY(0, z), maxY);
      }
    });
  });

  group('Coordonnées de tuiles (Québec)', () {
    test('lonToX produit des valeurs valides pour le Québec', () {
      // Québec: longitudes ~-53 à -80
      for (final lon in [-53.0, -65.0, -72.0, -79.0]) {
        for (int z = 10; z <= 16; z++) {
          final x = _lonToX(lon, z);
          expect(x, greaterThanOrEqualTo(0));
          expect(x, lessThan(1 << z));
        }
      }
    });

    test('latToY produit des valeurs valides pour le Québec', () {
      // Québec: latitudes ~45 à 62
      for (final lat in [45.0, 47.5, 52.0, 58.0, 61.0]) {
        for (int z = 10; z <= 16; z++) {
          final y = _latToY(lat, z);
          expect(y, greaterThanOrEqualTo(0));
          expect(y, lessThan(1 << z));
        }
      }
    });

    test('Lac Pikauba (47.5, -72.0) à z=12 donne des coords raisonnables', () {
      const lat = 47.5, lon = -72.0, z = 12;
      final x = _lonToX(lon, z);
      final y = _latToY(lat, z);
      // lon=-72 → x = floor(108/360 * 4096) = floor(1228.8) = 1228
      // lat=47.5 → y ≈ 1430 (calcul Mercator)
      expect(x, inInclusiveRange(1100, 1400));
      expect(y, inInclusiveRange(1300, 1600));
    });
  });

  group('estimateTileCount', () {
    test('zone ~5×5km (ZEC typique) à zoom 16 donne < 5000 tuiles', () {
      // 0.045°×0.060° ≈ 5km×5km au Québec
      final count = MbtilesService.estimateTileCount(
        47.47, -72.03, 47.52, -71.97,
        maxZoom: 16,
      );
      expect(count, greaterThan(10));
      expect(count, lessThan(5000));
    });

    test('zone 1°×1° à zoom 16 donne < 100000 tuiles', () {
      final count = MbtilesService.estimateTileCount(
        47.0, -73.0, 48.0, -72.0,
        maxZoom: 16,
      );
      expect(count, greaterThan(1000));
      expect(count, lessThan(100000));
    });

    test('croît avec le maxZoom', () {
      const args = (47.45, -72.06, 47.55, -71.94);
      final c14 = MbtilesService.estimateTileCount(args.$1, args.$2, args.$3, args.$4, maxZoom: 14);
      final c16 = MbtilesService.estimateTileCount(args.$1, args.$2, args.$3, args.$4, maxZoom: 16);
      final c17 = MbtilesService.estimateTileCount(args.$1, args.$2, args.$3, args.$4, maxZoom: 17);
      expect(c14, lessThan(c16));
      expect(c16, lessThan(c17));
    });
  });

  group('_squareBounds (cadre de téléchargement)', () {
    // iPhone typique : map = 390×420px
    // visible à z=12 : ~0.14°lat × 0.17°lon
    const args = (
      mapWidth: 390.0, mapHeight: 420.0,
      visNorth: 47.57, visSouth: 47.43,
      visEast: -71.915, visWest: -72.085,
      centerLat: 47.5, centerLon: -72.0,
    );

    test('le centre des bounds = centre de la carte', () {
      final b = _squareBounds(
        mapWidth: args.mapWidth, mapHeight: args.mapHeight,
        visNorth: args.visNorth, visSouth: args.visSouth,
        visEast: args.visEast, visWest: args.visWest,
        centerLat: args.centerLat, centerLon: args.centerLon,
      );
      expect((b.maxLat + b.minLat) / 2, closeTo(47.5, 0.0001));
      expect((b.maxLon + b.minLon) / 2, closeTo(-72.0, 0.0001));
    });

    test('les bounds sont strictement intérieures au viewport', () {
      final b = _squareBounds(
        mapWidth: args.mapWidth, mapHeight: args.mapHeight,
        visNorth: args.visNorth, visSouth: args.visSouth,
        visEast: args.visEast, visWest: args.visWest,
        centerLat: args.centerLat, centerLon: args.centerLon,
      );
      expect(b.maxLat, lessThan(args.visNorth));
      expect(b.minLat, greaterThan(args.visSouth));
      expect(b.maxLon, lessThan(args.visEast));
      expect(b.minLon, greaterThan(args.visWest));
    });

    test('maxLat > minLat et maxLon > minLon', () {
      final b = _squareBounds(
        mapWidth: args.mapWidth, mapHeight: args.mapHeight,
        visNorth: args.visNorth, visSouth: args.visSouth,
        visEast: args.visEast, visWest: args.visWest,
        centerLat: args.centerLat, centerLon: args.centerLon,
      );
      expect(b.maxLat, greaterThan(b.minLat));
      expect(b.maxLon, greaterThan(b.minLon));
    });

    test('les bounds restent au Québec', () {
      final b = _squareBounds(
        mapWidth: args.mapWidth, mapHeight: args.mapHeight,
        visNorth: args.visNorth, visSouth: args.visSouth,
        visEast: args.visEast, visWest: args.visWest,
        centerLat: args.centerLat, centerLon: args.centerLon,
      );
      expect(b.minLat, greaterThan(44.0)); // pas en dehors du Québec
      expect(b.maxLat, lessThan(63.0));
      expect(b.minLon, greaterThan(-81.0));
      expect(b.maxLon, lessThan(-52.0));
    });

    test('zoom élevé → bounds plus petites que zoom faible', () {
      // Zoom élevé (z~15) : viewport visible très petit
      final bHigh = _squareBounds(
        mapWidth: 390, mapHeight: 420,
        visNorth: 47.503, visSouth: 47.497,
        visEast: -71.996, visWest: -72.004,
        centerLat: 47.5, centerLon: -72.0,
      );
      // Zoom faible (z~10) : viewport visible très grand
      final bLow = _squareBounds(
        mapWidth: 390, mapHeight: 420,
        visNorth: 47.8, visSouth: 47.2,
        visEast: -71.7, visWest: -72.3,
        centerLat: 47.5, centerLon: -72.0,
      );
      expect(bHigh.maxLat - bHigh.minLat, lessThan(bLow.maxLat - bLow.minLat));
      expect(bHigh.maxLon - bHigh.minLon, lessThan(bLow.maxLon - bLow.minLon));
    });

    test('les bounds à z=15 produisent un nombre raisonnable de tuiles', () {
      // À z=15 visible : ~0.006°lat × 0.008°lon
      final b = _squareBounds(
        mapWidth: 390, mapHeight: 420,
        visNorth: 47.503, visSouth: 47.497,
        visEast: -71.996, visWest: -72.004,
        centerLat: 47.5, centerLon: -72.0,
      );
      final count = MbtilesService.estimateTileCount(
        b.minLat, b.minLon, b.maxLat, b.maxLon,
        maxZoom: 16,
      );
      // Devrait télécharger au moins quelques tuiles, mais pas des millions
      expect(count, greaterThan(0));
      expect(count, lessThan(500));
    });
  });
}
