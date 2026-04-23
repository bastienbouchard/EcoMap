import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ── SCORING ────────────────────────────────────────────────────────────────

int scoreOrignal(Map props) {
  int score = 0;
  final couv = (props['type_couv'] ?? '').toString().toUpperCase();
  final ess = (props['gr_ess'] ?? '').toString().toUpperCase();
  final origine = (props['origine'] ?? '').toString().toUpperCase();
  final age = (props['cl_age'] ?? '').toString().toUpperCase();
  final drai = (props['cl_drai'] ?? '').toString();

  if (couv == 'F') score += 4;
  if (couv == 'M') score += 3;
  if (couv == 'R') score += 2;

  if (ess.contains('PE')) score += 5;
  if (ess.contains('AU')) score += 4;
  if (ess.contains('SA')) score += 4;
  if (ess.contains('BP')) score += 3;
  if (ess.contains('EB')) score += 1;

  if (origine == 'CP') score += 5;
  if (origine == 'BR') score += 4;
  if (origine == 'EP') score += 2;

  if (age == 'J') score += 5;
  if (age == '10' || age == '20') score += 4;
  if (age == 'JIN') score += 2;
  if (age == '30') score += 2;

  if (drai == '4' || drai == '5') score += 4;

  final depSur = (props['dep_sur'] ?? '').toString();
  final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
  if (depSur.startsWith('3') || depSur.startsWith('4') ||
      typeEco.contains('RIV') || drai == '6') {
    score += 3;
  }

  final codeCouv = (props['code_couv'] ?? '').toString().toUpperCase();
  final milieu = (props['milieu'] ?? '').toString().toUpperCase();
  if (couv == 'ANT' || typeEco.contains('URB') ||
      codeCouv.contains('ANT') || milieu.contains('URB')) {
    score -= 5;
  }
  if (typeEco.contains('AGR') || codeCouv.contains('AGR') || milieu.contains('AGR')) {
    score -= 3;
  }
  if (typeEco.contains('IMP') || codeCouv == 'EE' || typeEco.contains('EAU')) {
    return 0;
  }

  return score.clamp(0, 999);
}

Color scoreColor(int score) {
  if (score >= 18) return const Color(0xFF1A3A08).withOpacity(0.8);
  if (score >= 13) return const Color(0xFF2D5016).withOpacity(0.7);
  if (score >= 8)  return const Color(0xFF5A8A1E).withOpacity(0.6);
  if (score >= 4)  return const Color(0xFF8B7355).withOpacity(0.5);
  return const Color(0xFF6B4423).withOpacity(0.2);
}

// ── GÉOMÉTRIE ──────────────────────────────────────────────────────────────

bool pointInPolygon(LatLng point, List<dynamic> ring) {
  bool inside = false;
  double x = point.longitude, y = point.latitude;
  int j = ring.length - 1;
  for (int i = 0; i < ring.length; i++) {
    double xi = ring[i][0].toDouble(), yi = ring[i][1].toDouble();
    double xj = ring[j][0].toDouble(), yj = ring[j][1].toDouble();
    if (((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}

bool pointInGeometry(LatLng point, Map geom) {
  final type = geom['type'];
  try {
    if (type == 'Polygon') {
      return pointInPolygon(point, geom['coordinates'][0]);
    } else if (type == 'MultiPolygon') {
      for (final poly in geom['coordinates']) {
        if (pointInPolygon(point, poly[0])) return true;
      }
    }
  } catch (e) {}
  return false;
}

bool crossesWaterBody(LatLng from, LatLng to, Map<String, dynamic> geoJsonData) {
  final features = geoJsonData['features'] as List;
  const steps = 10;
  for (int i = 0; i <= steps; i++) {
    final ratio = i / steps;
    final lat = from.latitude + (to.latitude - from.latitude) * ratio;
    final lon = from.longitude + (to.longitude - from.longitude) * ratio;
    final checkPoint = LatLng(lat, lon);
    for (final feat in features) {
      final props = feat['properties'] as Map;
      final geom = feat['geometry'] as Map;
      final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
      final codeCouv = (props['code_couv'] ?? '').toString().toUpperCase();
      if ((typeEco.contains('EAU') || codeCouv.contains('EAU') ||
           typeEco.contains('RIV') || codeCouv == 'EE') &&
          pointInGeometry(checkPoint, geom)) {
        return true;
      }
    }
  }
  return false;
}

bool hasSteepSlope(LatLng from, LatLng to, Map<String, dynamic> geoJsonData) {
  final features = geoJsonData['features'] as List;
  int? elevationFrom, elevationTo;
  for (final feat in features) {
    final props = feat['properties'] as Map;
    final geom = feat['geometry'] as Map;
    if (pointInGeometry(from, geom)) {
      final pente = props['cl_pent']?.toString();
      if (pente == 'D' || pente == 'E') return true;
      final alt = props['altitude'];
      if (alt != null) elevationFrom = int.tryParse(alt.toString());
    }
    if (pointInGeometry(to, geom)) {
      final pente = props['cl_pent']?.toString();
      if (pente == 'D' || pente == 'E') return true;
      final alt = props['altitude'];
      if (alt != null) elevationTo = int.tryParse(alt.toString());
    }
  }
  if (elevationFrom != null && elevationTo != null) {
    final distance = const Distance().as(LengthUnit.Meter, from, to);
    if (distance > 0) {
      final slope = ((elevationTo - elevationFrom).abs() / distance) * 100;
      if (slope > 30) return true;
    }
  }
  return false;
}

// ── ISOLATE FUNCTIONS (top-level pour compute()) ───────────────────────────

List<Polygon> buildPolygonsIsolate(Map<String, dynamic> geoJsonData) {
  final features = geoJsonData['features'] as List;
  final List<Polygon> result = [];
  for (final feat in features) {
    try {
      final props = feat['properties'] as Map;
      final score = scoreOrignal(props);
      if (score < 4) continue; // Ne pas rendre les zones sans intérêt
      final geom = feat['geometry'];
      final type = geom['type'];
      final color = scoreColor(score);
      List<List<LatLng>> rings = [];
      if (type == 'Polygon') {
        for (final ring in geom['coordinates']) {
          rings.add((ring as List).map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList());
        }
      } else if (type == 'MultiPolygon') {
        for (final poly in geom['coordinates']) {
          for (final ring in poly) {
            rings.add((ring as List).map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList());
          }
        }
      }
      for (final ring in rings) {
        result.add(Polygon(points: ring, color: color, borderColor: Colors.transparent, borderStrokeWidth: 0));
      }
    } catch (e) {}
  }
  return result;
}

List<List<double>> buildHotspotsDataIsolate(Map<String, dynamic> geoJsonData) {
  final features = geoJsonData['features'] as List;
  final List<List<double>> result = [];
  for (final feat in features) {
    try {
      final props = feat['properties'] as Map;
      final score = scoreOrignal(props);
      if (score < 3) continue;
      final geom = feat['geometry'] as Map;
      final type = geom['type'];
      List<dynamic> ring;
      if (type == 'Polygon') {
        ring = geom['coordinates'][0] as List;
      } else if (type == 'MultiPolygon') {
        ring = geom['coordinates'][0][0] as List;
      } else continue;
      double sumLat = 0, sumLon = 0;
      for (final c in ring) {
        sumLon += (c[0] as num).toDouble();
        sumLat += (c[1] as num).toDouble();
      }
      result.add([score.toDouble(), sumLat / ring.length, sumLon / ring.length]);
    } catch (e) {}
  }
  return result;
}
