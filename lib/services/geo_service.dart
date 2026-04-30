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
  // Vérifie uniquement la destination — vérifier le départ bloquerait tous les pas
  // si on part d'une zone à pente forte
  for (final feat in features) {
    final props = feat['properties'] as Map;
    final geom = feat['geometry'] as Map;
    if (pointInGeometry(to, geom)) {
      final pente = props['cl_pent']?.toString();
      if (pente == 'D' || pente == 'E') return true;
      break;
    }
  }
  return false;
}

// ── PARCOURS ISOLATE ───────────────────────────────────────────────────────

Map<String, dynamic> buildParcoursIsolate(Map<String, dynamic> params) {
  final lat = params['lat'] as double;
  final lon = params['lon'] as double;
  final windRad = params['windRad'] as double;
  final targetDist = params['targetDist'] as double;
  final geoJsonData = params['geoJson'] as Map<String, dynamic>;
  final features = geoJsonData['features'] as List;
  final rawHotspots = (params['hotspots'] as List?)
      ?.map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
      .toList() ?? [];

  List<List<double>> points = [[lat, lon]];
  double curLat = lat, curLon = lon;
  double totalDist = 0;
  int totalScore = 0, nbPoints = 0, blockedAttempts = 0;
  final stepDist = targetDist / 28;

  String habitatKey(Map props) =>
      '${props['type_couv'] ?? ''}_${props['gr_ess'] ?? ''}_${props['cl_age'] ?? ''}';

  // F = feuillu (nourriture), B = résineux/humide (couchette), M = mixte, X = autre
  String habitatType(Map props) {
    final couv = (props['type_couv'] ?? '').toString().toUpperCase();
    final drai = (props['cl_drai'] ?? '').toString();
    final depSur = (props['dep_sur'] ?? '').toString();
    final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
    if (couv == 'R') return 'B';
    if (drai == '5' || drai == '6' || depSur.startsWith('3') || depSur.startsWith('4') ||
        typeEco.contains('RIV')) return 'B';
    if (couv == 'F') return 'F';
    if (couv == 'M') return 'M';
    return 'X';
  }

  // Évalue l'habitat, le type et le score à une position donnée
  ({int score, String habitat, String type, bool blocked}) evalPoint(double pLat, double pLon) {
    for (final feat in features) {
      if (pointInGeometry(LatLng(pLat, pLon), feat['geometry'] as Map)) {
        final props = feat['properties'] as Map;
        final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
        final codeCouv = (props['code_couv'] ?? '').toString().toUpperCase();
        if (typeEco.contains('EAU') || codeCouv == 'EE' || typeEco.contains('RIV')) {
          return (score: 0, habitat: '', type: 'X', blocked: true);
        }
        return (score: scoreOrignal(props), habitat: habitatKey(props),
                type: habitatType(props), blocked: false);
      }
    }
    return (score: 0, habitat: '', type: 'X', blocked: false);
  }

  final startEval = evalPoint(lat, lon);
  String currentHabitat = startEval.habitat;
  String currentType = startEval.type;

  // Direction face au vent — contrainte principale (jamais dans le dos du vent)
  final upwindRad = windRad;

  // État d'ondulation — alterne gauche/droite, se retourne aux transitions
  int oscillationDir = 1;
  int stepsInDir = 0;
  const phaseSteps = 3;

  for (int step = 0; step < 80 && totalDist < targetDist; step++) {
    stepsInDir++;
    if (stepsInDir >= phaseSteps) {
      oscillationDir = -oscillationDir;
      stepsInDir = 0;
    }

    // Direction vers le hotspot le plus proche, pour bonus secondaire
    double? hotspotRad;
    if (rawHotspots.isNotEmpty) {
      double minDist = double.infinity;
      List<double>? nearest;
      for (final h in rawHotspots) {
        final d = (h[0] - curLat) * (h[0] - curLat) + (h[1] - curLon) * (h[1] - curLon);
        if (d < minDist) { minDist = d; nearest = h; }
      }
      if (nearest != null) {
        final dlat = nearest[0] - curLat;
        final dlon = (nearest[1] - curLon) * cos(curLat * pi / 180);
        hotspotRad = atan2(dlon, dlat);
      }
    }

    // Détecte si on est actuellement sur une lisière F↔B forte (4 sondes cardinales)
    bool nearStrongEdge = false;
    for (double testAngle = 0; testAngle < 2 * pi; testAngle += pi / 2) {
      final pLat = curLat + (90.0 / 111000) * cos(testAngle);
      final pLon = curLon + (90.0 / 111000) * sin(testAngle) / cos(curLat * pi / 180);
      final pEval = evalPoint(pLat, pLon);
      if (!pEval.blocked &&
          ((pEval.type == 'F' && currentType == 'B') ||
           (pEval.type == 'B' && currentType == 'F'))) {
        nearStrongEdge = true;
        break;
      }
    }

    // Contrainte principale : ±90° autour du vent (jamais dans le dos).
    // Sur lisière F↔B forte : jusqu'à ±120° pour longer l'edge perpendiculairement.
    final maxDelta = nearStrongEdge ? 120.0 : 90.0;

    int bestScore = -1;
    double? bestLat, bestLon;
    double bestAngleDelta = 180;
    String bestHabitat = '';
    String bestType = 'X';

    for (double angleDelta = -maxDelta; angleDelta <= maxDelta; angleDelta += 7.5) {
      final angle = upwindRad + angleDelta * pi / 180;
      final sLat = (stepDist / 111000) * cos(angle);
      final sLon = (stepDist / 111000) * sin(angle) / cos(curLat * pi / 180);
      final cLat = curLat + sLat;
      final cLon = curLon + sLon;

      final eval = evalPoint(cLat, cLon);
      if (eval.blocked) continue;

      // 1. Score habitat
      final habitatScore = eval.score;

      // 2. Bonus vent : face au vent = max, perpendiculaire = 0
      final windBonus = ((90 - angleDelta.abs()) / 90 * 4).round().clamp(0, 4);

      // 3. Bonus hotspot : préfère les angles du cône ±90° qui rapprochent d'un hotspot
      int hotspotBonus = 0;
      if (hotspotRad != null) {
        final hotDelta = ((angle - hotspotRad) * 180 / pi + 360) % 360;
        final hotNorm = hotDelta > 180 ? hotDelta - 360 : hotDelta;
        if (hotNorm.abs() < 60) hotspotBonus = 4;
        else if (hotNorm.abs() < 90) hotspotBonus = 2;
      }

      // 4. Bonus ondulation — zigzag marqué pour longer les lisières
      final oscBonus = (angleDelta * oscillationDir > 10) ? 8 : 0;

      // 5. Bonus lisière F↔B — dominant (transitions feuillu↔résineux/humide)
      int transBonus = 0;
      if (eval.habitat.isNotEmpty && eval.habitat != currentHabitat) {
        final bothFB = (eval.type == 'F' && currentType == 'B') ||
                       (eval.type == 'B' && currentType == 'F');
        final mixte = eval.type == 'M' || currentType == 'M';
        transBonus = bothFB ? 22 : mixte ? 11 : 3;
      }

      // 6. Bonus bordure — longe activement la lisière F↔B (2 sondes perp. à 90m)
      int edgeBonus = 0;
      for (final sign in [1.0, -1.0]) {
        final perpAngle = angle + sign * pi / 2;
        final pLat = cLat + (90.0 / 111000) * cos(perpAngle);
        final pLon = cLon + (90.0 / 111000) * sin(perpAngle) / cos(curLat * pi / 180);
        final perpEval = evalPoint(pLat, pLon);
        if (!perpEval.blocked && perpEval.type != eval.type) {
          final fb = (perpEval.type == 'F' || perpEval.type == 'B') &&
                     (eval.type == 'F' || eval.type == 'B');
          edgeBonus = fb ? 14 : 6;
          break;
        }
      }

      final candidateScore =
          habitatScore + windBonus + hotspotBonus + oscBonus + transBonus + edgeBonus;

      if (candidateScore > bestScore ||
          (candidateScore == bestScore && angleDelta.abs() < bestAngleDelta)) {
        bestScore = candidateScore;
        bestLat = cLat;
        bestLon = cLon;
        bestAngleDelta = angleDelta.abs();
        bestHabitat = eval.habitat;
        bestType = eval.type;
      }
    }

    if (bestLat != null && bestLon != null) {
      final dist = const Distance().as(
          LengthUnit.Meter, LatLng(curLat, curLon), LatLng(bestLat, bestLon));
      totalDist += dist;
      points.add([bestLat, bestLon]);
      curLat = bestLat;
      curLon = bestLon;
      // Retourne l'oscillation à chaque croisement de lisière (zigzag organique)
      if (bestHabitat.isNotEmpty && bestHabitat != currentHabitat && stepsInDir >= 2) {
        oscillationDir = -oscillationDir;
        stepsInDir = 0;
      }
      currentHabitat = bestHabitat;
      currentType = bestType;
      totalScore += bestScore.clamp(0, 999);
      nbPoints++;
    } else {
      blockedAttempts++;
      if (blockedAttempts >= 4) break;
    }
  }

  const scoreMaxPossible = 28.0;
  final scorePct = nbPoints > 0
      ? (totalScore / nbPoints / scoreMaxPossible * 100).clamp(0.0, 100.0)
      : 0.0;

  return {'points': points, 'scorePct': scorePct};
}

// ── ISOLATE FUNCTIONS (top-level pour compute()) ───────────────────────────

List<Polygon> buildPolygonsIsolate(Map<String, dynamic> geoJsonData) {
  final features = geoJsonData['features'] as List;
  final List<Polygon> result = [];
  for (final feat in features) {
    try {
      final props = feat['properties'] as Map;
      final score = scoreOrignal(props);
      if (score < 8) continue;
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

List<Map<String, dynamic>> buildHotspotsDataIsolate(Map<String, dynamic> geoJsonData) {
  final features = geoJsonData['features'] as List;
  final List<Map<String, dynamic>> result = [];
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
      result.add({
        's': score,
        'la': sumLat / ring.length,
        'lo': sumLon / ring.length,
        'p': Map<String, dynamic>.from(props),
      });
    } catch (e) {}
  }
  return result;
}
