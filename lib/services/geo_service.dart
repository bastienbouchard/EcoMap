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
  final dens = (props['cl_dens'] ?? '').toString().toUpperCase();
  final haut = (props['cl_haut'] ?? '').toString().toUpperCase();

  // Type de couvert
  if (couv == 'F') score += 4;
  if (couv == 'M') score += 3;
  if (couv == 'R') score += 2;

  // Essences — alimentation et abri orignal
  if (ess.contains('PE')) score += 5;  // peuplier
  if (ess.contains('AU')) score += 4;  // aulne
  if (ess.contains('SA')) score += 4;  // saule
  if (ess.contains('BP')) score += 3;  // bouleau à papier
  if (ess.contains('ERR')) score += 3; // érable rouge
  if (ess.contains('BJ')) score += 2;  // bouleau jaune
  if (ess.contains('EB')) score += 1;  // épinette blanche
  if (ess.contains('EN')) score += 2;  // épinette noire (abri)
  if (ess.contains('MEL')) score += 2; // mélèze (zones humides)

  // Origine du peuplement
  if (origine == 'CP') score += 5;  // coupe — régénération idéale orignal
  if (origine == 'BR') score += 4;  // brûlis — excellente nourriture
  if (origine == 'EP') score += 3;  // épidémie
  if (origine == 'CH') score += 2;  // chablis

  // Classe d'âge — jeune forêt = meilleure alimentation
  if (age == 'J' || age == 'JIN') score += 5;
  if (age == '10') score += 5;
  if (age == '20') score += 4;
  if (age == '30') score += 3;
  if (age == '40') score += 2;
  if (age == '50') score += 1;
  // 60+ = forêt mature, moins intéressant pour nourriture mais bon abri

  // Drainage — zones humides favorisées
  if (drai == '4' || drai == '5') score += 4;  // mal drainé/tourbeux
  if (drai == '3') score += 2;                   // imparfaitement drainé
  if (drai == '6') score += 5;                   // inondé/marécageux

  // Densité — densité moyenne préférée (abri sans obstruction)
  if (dens == 'B') score += 2;  // clairsemé
  if (dens == 'C') score += 3;  // semi-dense
  if (dens == 'D') score += 1;  // dense

  // Hauteur — forêt basse/moyenne (jeune régénération)
  if (haut == 'A') score += 3;  // < 7m
  if (haut == 'B') score += 2;  // 7-12m

  // Dépôt de surface et type écologique
  final depSur = (props['dep_sur'] ?? '').toString();
  final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
  if (depSur.startsWith('3') || depSur.startsWith('4') ||
      typeEco.contains('RIV') || drai == '6') {
    score += 3;  // zones riveraines/tourbières
  }

  // Pénalités
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

Color polygonColor(Map props) {
  final score = scoreOrignal(props);
  final couv    = (props['type_couv'] ?? '').toString().toUpperCase();
  final origine = (props['origine']   ?? '').toString().toUpperCase();
  final age     = (props['cl_age']    ?? '').toString().toUpperCase();
  final drai    = (props['cl_drai']   ?? '').toString();
  final depSur  = (props['dep_sur']   ?? '').toString();
  final typeEco = (props['type_eco']  ?? '').toString().toUpperCase();

  // Toujours cacher les zones vraiment non-forestières ou pénalisées
  final codeCouv = (props['code_couv'] ?? '').toString().toUpperCase();
  if (typeEco.contains('EAU') || codeCouv == 'EE') return Colors.transparent;
  if (typeEco.contains('URB') || typeEco.contains('AGR')) return Colors.transparent;

  // Si aucun type de couvert connu ET score nul → transparent
  if (couv.isEmpty && score < 1) return Colors.transparent;

  // Opacité proportionnelle au score — minimum 0.25 pour ne pas disparaître
  final opacity = score >= 1
      ? (0.35 + score.clamp(0, 20) / 20 * 0.50).clamp(0.35, 0.85)
      : 0.25;

  // Coupe récente / jeune régénération → blanc
  // Seulement les JEUNES peuplements — pas les vieilles coupes régénérées (age 40+)
  if (age == 'J' || age == 'JIN' || age == '10' || age == '20') {
    return Colors.white.withOpacity(opacity);
  }

  // Zone riveraine / marécageuse → bleu
  if (drai == '5' || drai == '6' ||
      depSur.startsWith('3') || depSur.startsWith('4') ||
      typeEco.contains('RIV')) {
    return const Color(0xFF1565C0).withOpacity(opacity);
  }

  // Feuillu → jaune/or
  if (couv == 'F') return const Color(0xFFFFD600).withOpacity(opacity);

  // Mixte → orange
  if (couv == 'M') return const Color(0xFFFF6D00).withOpacity(opacity);

  // Résineux → vert foncé
  if (couv == 'R') return const Color(0xFF1B5E20).withOpacity(opacity);

  // Autre couvert avec score > 0 → vert neutre discret
  if (score > 0) return const Color(0xFF5A8A1E).withOpacity(0.25);

  return Colors.transparent;
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

  // Pre-compute water body centroids for cheap proximity checks during route eval
  final List<List<double>> waterCentroids = [];
  for (final feat in features) {
    try {
      final props = feat['properties'] as Map;
      final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
      final codeCouv = (props['code_couv'] ?? '').toString().toUpperCase();
      if (!(typeEco.contains('EAU') || codeCouv.contains('EAU') ||
            typeEco.contains('RIV') || codeCouv == 'EE')) continue;
      final geom = feat['geometry'] as Map;
      final gType = geom['type'];
      List<dynamic> ring;
      if (gType == 'Polygon') ring = geom['coordinates'][0] as List;
      else if (gType == 'MultiPolygon') ring = geom['coordinates'][0][0] as List;
      else continue;
      double sLat = 0, sLon = 0;
      for (final c in ring) { sLon += (c[0] as num).toDouble(); sLat += (c[1] as num).toDouble(); }
      waterCentroids.add([sLat / ring.length, sLon / ring.length]);
    } catch (_) {}
  }

  final rawHotspots = (params['hotspots'] as List?)
      ?.map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
      .toList() ?? [];

  List<List<double>> points = [[lat, lon]];
  double curLat = lat, curLon = lon;
  double totalDist = 0;
  int totalScore = 0, nbPoints = 0, blockedAttempts = 0;
  int waterBlockCount = 0, terrainBlockCount = 0;
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

  // Détecte si un ensemble de propriétés représente un plan d'eau
  bool _isWaterFeature(Map props) {
    final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
    final codeCouv = (props['code_couv'] ?? '').toString().toUpperCase();
    final typeCouv = (props['type_couv'] ?? '').toString().toUpperCase();
    final depSur   = (props['dep_sur']  ?? '').toString().toUpperCase();
    return typeEco.contains('EAU') || typeEco.contains('RIV') ||
           typeEco.contains('LAC') || typeEco.startsWith('RE') ||
           codeCouv == 'EE' || codeCouv.contains('EAU') ||
           typeCouv == 'EAU' || typeCouv == 'IN' ||
           depSur.startsWith('7') || depSur.startsWith('8');
  }

  // Vérifie si le segment entre deux points traverse de l'eau (9 échantillons)
  bool segmentCrossesWater(double fromLat, double fromLon, double toLat, double toLon) {
    for (int s = 1; s <= 9; s++) {
      final t = s / 10.0;
      final sLat = fromLat + (toLat - fromLat) * t;
      final sLon = fromLon + (toLon - fromLon) * t;
      for (final feat in features) {
        try {
          if (_isWaterFeature(feat['properties'] as Map)) {
            if (pointInGeometry(LatLng(sLat, sLon), feat['geometry'] as Map)) return true;
          }
        } catch (_) {}
      }
    }
    return false;
  }

  // Évalue l'habitat, le type et le score à une position donnée
  ({int score, String habitat, String type, bool blocked}) evalPoint(double pLat, double pLon) {
    for (final feat in features) {
      if (pointInGeometry(LatLng(pLat, pLon), feat['geometry'] as Map)) {
        final props = feat['properties'] as Map;
        if (_isWaterFeature(props)) {
          return (score: 0, habitat: '', type: 'X', blocked: true);
        }
        return (score: scoreOrignal(props), habitat: habitatKey(props),
                type: habitatType(props), blocked: false);
      }
    }
    // Hors de tout polygone = zone sans couverture éco (eau, route, découvert) → bloqué
    return (score: 0, habitat: '', type: 'X', blocked: true);
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

    // Contrainte principale : ±60° autour du vent de face (vent de face ou légèrement de côté).
    // Sur lisière F↔B forte : jusqu'à ±80° pour longer l'edge sans perdre l'avantage du vent.
    final maxDelta = nearStrongEdge ? 80.0 : 60.0;

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
      if (eval.blocked) { terrainBlockCount++; continue; }
      if (segmentCrossesWater(curLat, curLon, cLat, cLon)) { waterBlockCount++; continue; }

      // 1. Score habitat
      final habitatScore = eval.score;

      // 7. Proximity eau — orignal très lié aux zones riveraines
      int waterBonus = 0;
      if (waterCentroids.isNotEmpty) {
        double minSqDist = double.infinity;
        for (final wc in waterCentroids) {
          final d = (cLat - wc[0]) * (cLat - wc[0]) + (cLon - wc[1]) * (cLon - wc[1]);
          if (d < minSqDist) minSqDist = d;
        }
        final degDist = sqrt(minSqDist);
        if (degDist < 150.0 / 111000) waterBonus = 8;
        else if (degDist < 400.0 / 111000) waterBonus = 4;
        else if (degDist < 800.0 / 111000) waterBonus = 2;
      }

      // 2. Bonus vent : face au vent = max, perpendiculaire = 0
      final windBonus = ((60 - angleDelta.abs()) / 60 * 5).round().clamp(0, 5);

      // 3. Bonus hotspot : attire fortement la route vers les points chauds
      int hotspotBonus = 0;
      if (hotspotRad != null) {
        final hotDelta = ((angle - hotspotRad) * 180 / pi + 360) % 360;
        final hotNorm = hotDelta > 180 ? hotDelta - 360 : hotDelta;
        if (hotNorm.abs() < 30) hotspotBonus = 18;
        else if (hotNorm.abs() < 60) hotspotBonus = 12;
        else if (hotNorm.abs() < 90) hotspotBonus = 5;
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
          habitatScore + windBonus + hotspotBonus + oscBonus + transBonus + edgeBonus + waterBonus;

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

  const scoreMaxPossible = 35.0;
  final scorePct = nbPoints > 0
      ? (totalScore / nbPoints / scoreMaxPossible * 100).clamp(0.0, 100.0)
      : 0.0;

  String blockReason = '';
  if (points.length < 5) {
    if (waterBlockCount > terrainBlockCount) {
      blockReason = 'eau';
    } else if (terrainBlockCount > 0) {
      blockReason = 'terrain';
    }
  }

  return {'points': points, 'scorePct': scorePct, 'blockReason': blockReason};
}

// ── ISOLATE FUNCTIONS (top-level pour compute()) ───────────────────────────

List<Map<String, dynamic>> findSalinesIsolate(Map<String, dynamic> params) {
  final lat = params['lat'] as double;
  final lon = params['lon'] as double;
  final radiusM = (params['radiusM'] as num?)?.toDouble() ?? 4000.0;
  final features = (params['geoJson'] as Map<String, dynamic>)['features'] as List;
  final infraPoints = (params['infraPoints'] as List?)
      ?.map((p) => [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()])
      .toList() ?? <List<double>>[];

  // Pre-filter: keep only features whose geometry touches the search bbox
  final latMargin = radiusM / 111000 * 1.3;
  final lonMargin = radiusM / (111000 * cos(lat * pi / 180)) * 1.3;
  final minLat = lat - latMargin; final maxLat = lat + latMargin;
  final minLon = lon - lonMargin; final maxLon = lon + lonMargin;
  final localFeatures = features.where((feat) {
    try {
      final geom = feat['geometry'] as Map;
      final type = geom['type'] as String;
      final List ring;
      if (type == 'Polygon') ring = (geom['coordinates'] as List)[0] as List;
      else if (type == 'MultiPolygon') ring = ((geom['coordinates'] as List)[0] as List)[0] as List;
      else return false;
      for (final c in ring) {
        final fLon = (c[0] as num).toDouble();
        final fLat = (c[1] as num).toDouble();
        if (fLat >= minLat && fLat <= maxLat && fLon >= minLon && fLon <= maxLon) return true;
      }
      return false;
    } catch (_) { return false; }
  }).toList();

  // Collecte les centroids des cours d'eau et zones inondées/intermittentes (pas les plans d'eau)
  final riverPoints = <List<double>>[];      // cours d'eau permanents
  final intermittentPoints = <List<double>>[]; // zones inondées/intermittentes
  for (final feat in localFeatures) {
    try {
      final props = feat['properties'] as Map;
      final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
      final typeCouv = (props['type_couv'] ?? '').toString().toUpperCase();
      final isRiver = typeEco.contains('RIV');
      final isIntermittent = typeCouv == 'IN';
      if (!isRiver && !isIntermittent) continue;
      final geom = feat['geometry'] as Map;
      List<dynamic> ring;
      if (geom['type'] == 'Polygon') ring = geom['coordinates'][0] as List;
      else if (geom['type'] == 'MultiPolygon') ring = geom['coordinates'][0][0] as List;
      else continue;
      double sumLat = 0, sumLon = 0;
      for (final c in ring) { sumLon += (c[0] as num).toDouble(); sumLat += (c[1] as num).toDouble(); }
      final pt = [sumLat / ring.length, sumLon / ring.length];
      if (isIntermittent) { intermittentPoints.add(pt); } else { riverPoints.add(pt); }
    } catch (_) {}
  }

  // Bonus cours d'eau : +8 si intermittent ≤ 600 m, +5 si rivière ≤ 800 m
  int waterBonus(double cLat, double cLon) {
    final cosC = cos(cLat * pi / 180);
    for (final w in intermittentPoints) {
      final d = sqrt(pow((w[0] - cLat) * 111000, 2) + pow((w[1] - cLon) * 111000 * cosC, 2));
      if (d <= 600) return 8;
    }
    for (final w in riverPoints) {
      final d = sqrt(pow((w[0] - cLat) * 111000, 2) + pow((w[1] - cLon) * 111000 * cosC, 2));
      if (d <= 800) return 5;
    }
    return 0;
  }

  final candidates = <Map<String, dynamic>>[];

  for (final feat in localFeatures) {
    try {
      final props = feat['properties'] as Map;
      final drainVal = int.tryParse((props['cl_drai'] ?? '').toString()) ?? 0;
      if (drainVal < 4) continue; // besoin d'une zone humide (imparfait→hydrique)

      final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
      final typeCourvS = (props['type_couv'] ?? '').toString().toUpperCase();
      final codeCourvS = (props['code_couv'] ?? '').toString().toUpperCase();
      if (typeEco.contains('EAU') || typeEco.contains('RIV') ||
          codeCourvS == 'EE' || typeCourvS == 'IN') continue;

      final geom = feat['geometry'] as Map;
      List<dynamic> ring;
      if (geom['type'] == 'Polygon') ring = geom['coordinates'][0] as List;
      else if (geom['type'] == 'MultiPolygon') ring = geom['coordinates'][0][0] as List;
      else continue;

      double sumLat = 0, sumLon = 0;
      for (final c in ring) {
        sumLon += (c[0] as num).toDouble();
        sumLat += (c[1] as num).toDouble();
      }
      final cLat = sumLat / ring.length;
      final cLon = sumLon / ring.length;

      final distM = sqrt(pow((cLat - lat) * 111000, 2) +
          pow((cLon - lon) * 111000 * cos(lat * pi / 180), 2));
      if (distM > radiusM) continue;

      // Exclusion : aucun spot à moins de 100 m d'une route ou d'un bâtiment
      final cosC = cos(cLat * pi / 180);
      final tooCloseToInfra = infraPoints.any((p) =>
          sqrt(pow((p[0] - cLat) * 111000, 2) +
               pow((p[1] - cLon) * 111000 * cosC, 2)) < 100);
      if (tooCloseToInfra) continue;

      // Score: qualité drainage + activité orignal + bonus eau à proximité
      final drainScore = (drainVal - 3) * 3; // 3-12
      final foodScore = scoreOrignal(props) ~/ 5;
      final total = drainScore + foodScore + waterBonus(cLat, cLon);

      candidates.add({'lat': cLat, 'lon': cLon, 'score': total});
    } catch (_) {}
  }

  candidates.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

  final result = <Map<String, dynamic>>[];
  for (final c in candidates) {
    final pos = LatLng(c['lat'] as double, c['lon'] as double);
    final tooClose = result.any((r) =>
        const Distance().as(LengthUnit.Meter,
            LatLng(r['lat'] as double, r['lon'] as double), pos) < 500);
    if (!tooClose) result.add(c);
    if (result.length >= 5) break;
  }
  return result;
}

List<Polygon> buildPolygonsIsolate(Map<String, dynamic> geoJsonData) {
  final features = geoJsonData['features'] as List;
  final List<Polygon> result = [];
  for (final feat in features) {
    try {
      final props = feat['properties'] as Map;
      final color = polygonColor(props);
      if (color == Colors.transparent) continue;
      final geom = feat['geometry'];
      final type = geom['type'];
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

// Retourne les étiquettes de peuplement (centroïde + texte) pour zoom élevé
List<Map<String, dynamic>> buildPolygonLabelsIsolate(Map<String, dynamic> geoJsonData) {
  final features = geoJsonData['features'] as List;
  final result = <Map<String, dynamic>>[];
  for (final feat in features) {
    try {
      final props = feat['properties'] as Map;
      final ess = (props['gr_ess'] ?? '').toString();
      final age = (props['cl_age'] ?? '').toString();
      final dens = (props['cl_dens'] ?? '').toString();
      final label = [ess, age, dens].where((s) => s.isNotEmpty).join('');
      if (label.isEmpty) continue;
      final geom = feat['geometry'];
      final ring = geom['type'] == 'Polygon'
          ? (geom['coordinates'] as List)[0] as List
          : ((geom['coordinates'] as List)[0] as List)[0] as List;
      double sumLat = 0, sumLon = 0;
      for (final c in ring) { sumLon += (c[0] as num).toDouble(); sumLat += (c[1] as num).toDouble(); }
      result.add({'lat': sumLat / ring.length, 'lon': sumLon / ring.length, 'label': label});
    } catch (_) {}
  }
  return result;
}

// ── PINCH POINTS ───────────────────────────────────────────────────────────
// Détecte les meilleurs emplacements d'affût : zones de transition entre habitats.
// Critères : proximité eau, feuillu, résineux, jeune peuplement/coupe/brûlis.
List<Map<String, dynamic>> findPinchPointsIsolate(Map<String, dynamic> params) {
  final lat    = params['lat'] as double;
  final lon    = params['lon'] as double;
  final radius = (params['radiusM'] as num?)?.toDouble() ?? 3000.0;
  final features = (params['geoJson'] as Map<String, dynamic>)['features'] as List;
  final infraPoints = (params['infraPoints'] as List?)
      ?.map((p) => [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()])
      .toList() ?? <List<double>>[];

  final cosLat = cos(lat * pi / 180);

  // Types de zones
  const zEau = 0, zFeuillu = 1, zResineux = 2, zMixte = 3, zJeune = 4, zAutre = 5;

  int zoneType(Map props) {
    final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
    final codeCouv = (props['code_couv'] ?? '').toString().toUpperCase();
    final ess = (props['type_couv'] ?? '').toString().toUpperCase();
    final age = (props['cl_age'] ?? '').toString().toUpperCase();
    final origine = (props['origine'] ?? '').toString().toUpperCase();
    if (typeEco.contains('EAU') || typeEco.contains('RIV') || codeCouv == 'EE') return zEau;
    final isJeune = age == 'J' || age == 'JIN' || age == '10' || age == '20' ||
                    origine == 'CP' || origine == 'BR' || origine == 'EP';
    if (isJeune) return zJeune;
    if (codeCouv == 'F') return zFeuillu;
    if (codeCouv == 'R') return zResineux;
    if (codeCouv == 'M') return zMixte;
    final decidus = ['PE', 'AU', 'SA', 'BP', 'ERR', 'BJ', 'PB'];
    final conifes = ['EP', 'EN', 'MEL', 'SAB', 'PIR', 'PIG', 'THO'];
    final hasD = decidus.any((e) => ess.contains(e));
    final hasC = conifes.any((e) => ess.contains(e));
    if (hasD && hasC) return zMixte;
    if (hasD) return zFeuillu;
    if (hasC) return zResineux;
    return zAutre;
  }

  // Étape 1 : centroïdes + score + type de zone
  final nodes = <Map<String, dynamic>>[];
  for (final feat in features) {
    try {
      final geom = feat['geometry'] as Map;
      final type = geom['type'] as String;
      final List ring;
      if (type == 'Polygon') ring = (geom['coordinates'] as List)[0] as List;
      else if (type == 'MultiPolygon') ring = ((geom['coordinates'] as List)[0] as List)[0] as List;
      else continue;
      double sumLat = 0, sumLon = 0;
      for (final c in ring) { sumLon += (c[0] as num).toDouble(); sumLat += (c[1] as num).toDouble(); }
      final cLat = sumLat / ring.length;
      final cLon = sumLon / ring.length;
      final distM = sqrt(pow((cLat - lat) * 111000, 2) + pow((cLon - lon) * 111000 * cosLat, 2));
      if (distM > radius * 1.2) continue;

      // Exclusion : aucun spot à moins de 100 m d'une route ou d'un bâtiment
      final cosC = cos(cLat * pi / 180);
      final tooCloseToInfra = infraPoints.any((p) =>
          sqrt(pow((p[0] - cLat) * 111000, 2) +
               pow((p[1] - cLon) * 111000 * cosC, 2)) < 100);
      if (tooCloseToInfra) continue;

      final props = feat['properties'] as Map;
      final zt = zoneType(props);
      final score = (zt == zEau) ? -1 : scoreOrignal(props);
      nodes.add({'lat': cLat, 'lon': cLon, 'score': score, 'zone': zt});
    } catch (_) {}
  }

  // Étape 2 : score de transition pour chaque bon habitat
  const neighborM = 400.0;
  final candidates = <Map<String, dynamic>>[];

  nodes.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

  for (final node in nodes) {
    final nScore = node['score'] as int;
    if (nScore < 8) continue;
    final nLat = node['lat'] as double;
    final nLon = node['lon'] as double;
    final cosN = cos(nLat * pi / 180);

    bool hasWater = false, hasFeuillu = false, hasResineux = false, hasJeune = false;
    int goodNeighbors = 0, barriers = 0;
    double closestWaterM = double.infinity;

    for (final other in nodes) {
      if (identical(node, other)) continue;
      final dM = sqrt(pow(((other['lat'] as double) - nLat) * 111000, 2) +
                      pow(((other['lon'] as double) - nLon) * 111000 * cosN, 2));
      if (dM > neighborM) continue;
      final oScore = other['score'] as int;
      final oZone  = other['zone'] as int;
      if (oZone == zEau) {
        hasWater = true;
        barriers++;
        if (dM < closestWaterM) closestWaterM = dM;
      } else if (oScore < 5) {
        barriers++;
      } else {
        goodNeighbors++;
        if (oZone == zFeuillu || oZone == zMixte) hasFeuillu = true;
        if (oZone == zResineux || oZone == zMixte) hasResineux = true;
        if (oZone == zJeune) hasJeune = true;
      }
    }

    if (goodNeighbors < 1) continue;

    // Score final : terrain + bonuses de transition
    int finalScore = nScore;
    if (hasWater) finalScore += closestWaterM < 150 ? 10 : 7;
    if (hasFeuillu) finalScore += 4;
    if (hasResineux) finalScore += 3;
    if (hasJeune) finalScore += 6;
    if (hasFeuillu && hasResineux) finalScore += 3; // corridor mixte
    if (hasWater && hasJeune) finalScore += 4;      // eau + jeune = habitat parfait

    candidates.add({'lat': nLat, 'lon': nLon, 'score': finalScore});
  }

  candidates.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

  // Déduplication à 600 m — évite la surpopulation de spots proches
  final deduped = <Map<String, dynamic>>[];
  for (final c in candidates) {
    final cLat = c['lat'] as double;
    final cLon = c['lon'] as double;
    final cosC = cos(cLat * pi / 180);
    final tooClose = deduped.any((r) =>
      sqrt(pow(((r['lat'] as double) - cLat) * 111000, 2) +
           pow(((r['lon'] as double) - cLon) * 111000 * cosC, 2)) < 600);
    if (!tooClose) deduped.add(c);
  }

  // Sélection par grille — garantit la couverture spatiale de toute la zone
  final maxN = (params['maxResults'] as int?) ?? 10;
  final latSpan = radius / 111000;
  final lonSpan = radius / (111000 * cosLat);
  final minLat = lat - latSpan;
  final minLon = lon - lonSpan;
  final gridDim = sqrt(maxN.toDouble()).ceil().clamp(2, 5);

  final result = <Map<String, dynamic>>[];
  final usedIdx = <int>{};

  for (int row = 0; row < gridDim && result.length < maxN; row++) {
    for (int col = 0; col < gridDim && result.length < maxN; col++) {
      final rMin = minLat + row * (2 * latSpan) / gridDim;
      final rMax = minLat + (row + 1) * (2 * latSpan) / gridDim;
      final cMin = minLon + col * (2 * lonSpan) / gridDim;
      final cMax = minLon + (col + 1) * (2 * lonSpan) / gridDim;
      for (int i = 0; i < deduped.length; i++) {
        if (usedIdx.contains(i)) continue;
        final rLat = deduped[i]['lat'] as double;
        final rLon = deduped[i]['lon'] as double;
        if (rLat >= rMin && rLat < rMax && rLon >= cMin && rLon < cMax) {
          result.add(deduped[i]);
          usedIdx.add(i);
          break;
        }
      }
    }
  }

  // Compléter avec les meilleurs scores non encore inclus
  for (int i = 0; i < deduped.length && result.length < maxN; i++) {
    if (!usedIdx.contains(i)) result.add(deduped[i]);
  }

  result.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
  return result;
}

List<Map<String, dynamic>> buildHotspotsDataIsolate(Map<String, dynamic> geoJsonData) {
  final features = geoJsonData['features'] as List;

  // Pré-calcul des centroïdes des plans d'eau
  final List<List<double>> waterCentroids = [];
  for (final feat in features) {
    try {
      final props = feat['properties'] as Map;
      final typeEco = (props['type_eco'] ?? '').toString().toUpperCase();
      final codeCouv = (props['code_couv'] ?? '').toString().toUpperCase();
      if (!typeEco.contains('EAU') && codeCouv != 'EE' && !typeEco.contains('RIV')) continue;
      final geom = feat['geometry'] as Map;
      final type = geom['type'];
      List<dynamic> ring;
      if (type == 'Polygon') ring = geom['coordinates'][0] as List;
      else if (type == 'MultiPolygon') ring = geom['coordinates'][0][0] as List;
      else continue;
      double sLat = 0, sLon = 0;
      for (final c in ring) { sLon += (c[0] as num).toDouble(); sLat += (c[1] as num).toDouble(); }
      waterCentroids.add([sLat / ring.length, sLon / ring.length]);
    } catch (_) {}
  }

  final List<Map<String, dynamic>> result = [];
  for (final feat in features) {
    try {
      final props = feat['properties'] as Map;
      final typeEcoH = (props['type_eco'] ?? '').toString().toUpperCase();
      final codeCourvH = (props['code_couv'] ?? '').toString().toUpperCase();
      final typeCourvH = (props['type_couv'] ?? '').toString().toUpperCase();
      if (typeEcoH.contains('EAU') || typeEcoH.contains('RIV') ||
          codeCourvH == 'EE' || typeCourvH == 'IN') continue;
      int score = scoreOrignal(props);
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
      final lat = sumLat / ring.length;
      final lon = sumLon / ring.length;

      // Bonus proximité eau (même logique que parcours)
      if (waterCentroids.isNotEmpty) {
        double minSqDist = double.infinity;
        for (final wc in waterCentroids) {
          final d = (lat - wc[0]) * (lat - wc[0]) + (lon - wc[1]) * (lon - wc[1]);
          if (d < minSqDist) minSqDist = d;
        }
        final degDist = sqrt(minSqDist);
        if (degDist < 150.0 / 111000) score += 8;
        else if (degDist < 400.0 / 111000) score += 4;
        else if (degDist < 800.0 / 111000) score += 2;
      }

      result.add({
        's': score,
        'la': lat,
        'lo': lon,
        'p': Map<String, dynamic>.from(props),
      });
    } catch (e) {}
  }
  return result;
}
