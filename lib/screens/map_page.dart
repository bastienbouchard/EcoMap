import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../app_globals.dart';
import '../models/hotspot_info.dart';
import '../services/geo_service.dart';
import '../painters/painters.dart';
import '../providers/mbtiles_provider.dart';
import '../widgets/scale_bar.dart';
import '../widgets/hotspot_detail_sheet.dart';
import '../widgets/map_drawer.dart';
import 'navigation_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  double _opacity = 0.86;
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(48.2917, -71.322);
  bool _loading = false;
  bool _loadingParcours = false;
  double? _windDeg;
  double? _windSpeed;
  List<LatLng> _parcours = [];
  double _distanceParcours = 2.0;
  bool _showParcours = false;
  bool _showPolygons = true;
  List<Polygon> _polygonsCache = [];
  double _parcoursScore = 0;
  bool _showHotspots = false;
  List<LatLng> _hotspots = [];
  List<HotspotInfo> _hotspotInfos = [];
  List<MapEntry<int, LatLng>> _hotspotsData = [];
  List<Map> _hotspotsProps = [];
  bool _showMenu = false;
  double _mapZoom = 13.0;
  double _mapLat = 48.2917;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _initLocation();
    _fetchWind();
    // Calculs lourds dans des isolates background — ne bloque plus le thread UI
    compute(buildPolygonsIsolate, geoJson).then((polys) {
      if (mounted) setState(() => _polygonsCache = polys);
    });
    compute(buildHotspotsDataIsolate, geoJson).then((raw) {
      if (mounted) {
        _hotspotsData =
            raw.map((e) => MapEntry(e[0].round(), LatLng(e[1], e[2]))).toList();
      }
    });
  }

  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() => _currentPosition = LatLng(pos.latitude, pos.longitude));
        await _fetchWind();
      }
    } catch (e) {}
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _loading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permission de localisation refusée'),
              backgroundColor: Color(0xFFFF6B35),
            ),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(pos.latitude, pos.longitude);
          _loading = false;
        });
        _mapController.move(_currentPosition, 13);
        await _fetchWind();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur GPS: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF6B35),
          ),
        );
      }
    }
  }

  void _resetNorth() {
    _mapController.rotate(0);
  }

  Future<void> _fetchWind() async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${_currentPosition.latitude}'
        '&longitude=${_currentPosition.longitude}'
        '&current=wind_speed_10m,wind_direction_10m',
      );
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        setState(() {
          _windDeg = data['current']['wind_direction_10m']?.toDouble();
          _windSpeed = data['current']['wind_speed_10m']?.toDouble();
        });
      }
    } catch (e) {}
  }

  // Génère un parcours SINUEUX qui suit les bonnes zones
  Future<void> _genererParcours() async {
    setState(() => _loadingParcours = true);

    final features = geoJson['features'] as List;
    double windRad = ((_windDeg ?? 0) + 180) * pi / 180;

    List<LatLng> points = [_currentPosition];
    LatLng current = _currentPosition;
    double totalDist = 0;
    double targetDist = _distanceParcours * 1000;
    int totalScore = 0;
    int nbPoints = 0;
    int blockedAttempts = 0;

    for (int step = 0; step < 80 && totalDist < targetDist; step++) {
      // Céder le thread à chaque étape pour éviter le blocage du thread principal
      await Future.delayed(Duration.zero);

      int bestScore = -1;
      LatLng? bestPoint;
      double stepDist = targetDist / 30;

      for (double angleDelta = -90; angleDelta <= 90; angleDelta += 5) {
        double angle = windRad + angleDelta * pi / 180;
        double stepLat = (stepDist / 111000) * cos(angle);
        double stepLon =
            (stepDist / 111000) * sin(angle) / cos(current.latitude * pi / 180);

        LatLng candidate = LatLng(
          current.latitude + stepLat,
          current.longitude + stepLon,
        );

        if (crossesWaterBody(current, candidate, geoJson)) continue;
        if (hasSteepSlope(current, candidate, geoJson)) continue;

        int candidateScore = 0;
        for (final feat in features) {
          final geom = feat['geometry'] as Map;
          if (pointInGeometry(candidate, geom)) {
            final props = feat['properties'] as Map;
            candidateScore = scoreOrignal(props);
            break;
          }
        }

        if (candidateScore > bestScore ||
            (candidateScore == bestScore && angleDelta.abs() > 20)) {
          bestScore = candidateScore;
          bestPoint = candidate;
          blockedAttempts = 0;
        }
      }

      if (bestPoint != null) {
        double dist = const Distance().as(LengthUnit.Meter, current, bestPoint);
        totalDist += dist;
        points.add(bestPoint);
        current = bestPoint;
        totalScore += bestScore < 0 ? 0 : bestScore;
        nbPoints++;
      } else {
        blockedAttempts++;
        if (blockedAttempts >= 3) break;
      }
    }

    const double scoreMaxPossible = 26.0;
    double scorePct = nbPoints > 0
        ? (totalScore / nbPoints / scoreMaxPossible * 100).clamp(0, 100)
        : 0;

    if (!mounted) return;
    setState(() {
      _parcours = points;
      _showParcours = true;
      _parcoursScore = scorePct;
      _loadingParcours = false;
    });

    if (points.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Parcours limité — déplacez-vous dans une zone plus ouverte',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Color(0xFFFF6B35),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  List<Polygon> _buildPolygons() {
    final features = geoJson['features'] as List;
    List<Polygon> result = [];

    for (final feat in features) {
      try {
        final props = feat['properties'] as Map;
        final score = scoreOrignal(props);
        final geom = feat['geometry'];
        final type = geom['type'];
        final color = scoreColor(score);
        List<List<LatLng>> rings = [];

        if (type == 'Polygon') {
          for (final ring in geom['coordinates']) {
            rings.add(
              (ring as List)
                  .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                  .toList(),
            );
          }
        } else if (type == 'MultiPolygon') {
          for (final poly in geom['coordinates']) {
            for (final ring in poly) {
              rings.add(
                (ring as List)
                    .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                    .toList(),
              );
            }
          }
        }

        for (final ring in rings) {
          result.add(
            Polygon(
              points: ring,
              color: color,
              borderColor: Colors.transparent,
              borderStrokeWidth: 0,
            ),
          );
        }
      } catch (e) {}
    }
    return result;
  }

  List<LatLng> _computeHotspots() {
    // Peupler le cache si nécessaire
    if (_hotspotsData.isEmpty) {
      final features = geoJson['features'] as List;
      final List<MapEntry<int, LatLng>> temp = [];
      final List<Map> tempProps = [];
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
          temp.add(MapEntry(score, LatLng(sumLat / ring.length, sumLon / ring.length)));
          tempProps.add(props);
        } catch (e) {}
      }
      _hotspotsData = temp;
      _hotspotsProps = tempProps;
    }

    // Filtrer par ce qui est VISIBLE à l'écran
    LatLngBounds? bounds;
    try {
      bounds = _mapController.camera.visibleBounds;
    } catch (_) {}

    final inView = bounds == null
        ? _hotspotsData
        : _hotspotsData.where((e) => bounds!.contains(e.value)).toList();

    // Fallback si rien dans la vue : tout le dataset
    final source = List<MapEntry<int, LatLng>>.from(
      inView.isNotEmpty ? inView : _hotspotsData,
    );
    source.sort((a, b) => b.key.compareTo(a.key));

    final List<LatLng> result = [];
    final List<HotspotInfo> infos = [];
    for (int i = 0; i < source.length; i++) {
      final entry = source[i];
      final pos = entry.value;
      final tooClose = result.any(
        (e) => const Distance().as(LengthUnit.Meter, e, pos) < 200,
      );
      if (!tooClose) {
        result.add(pos);
        // Retrouver les props par comparaison de coordonnées
        Map props = {};
        for (int j = 0; j < _hotspotsData.length; j++) {
          final e = _hotspotsData[j];
          if ((e.value.latitude - pos.latitude).abs() < 0.000001 &&
              (e.value.longitude - pos.longitude).abs() < 0.000001 &&
              j < _hotspotsProps.length) {
            props = _hotspotsProps[j];
            break;
          }
        }
        infos.add(HotspotInfo(position: pos, score: entry.key, props: props));
      }
      if (result.length >= 25) break;
    }
    _hotspotInfos = infos;

    return result;
  }

  String _windDirection(double deg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return dirs[((deg + 22.5) / 45).floor() % 8];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF1A1A1A),
      drawer: MapDrawer(
        showPolygons: _showPolygons,
        onPolygonsChanged: (val) => setState(() => _showPolygons = val),
        opacity: _opacity,
        onOpacityChanged: (val) => setState(() => _opacity = val),
        distanceParcours: _distanceParcours,
        onDistanceChanged: (val) => setState(() {
          _distanceParcours = val;
          _showParcours = false;
        }),
        loadingParcours: _loadingParcours,
        onGenerateParcours: _genererParcours,
      ),
      body: Stack(
        children: [
          // ── CARTE ──────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(48.2917, -71.322),
              initialZoom: 13,
              minZoom: 8,
              maxZoom: 19,
              onPositionChanged: (pos, _) {
                if (mounted) setState(() {
                  _mapZoom = pos.zoom;
                  _mapLat = pos.center.latitude;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ecomap',
              ),
              Opacity(
                opacity: _opacity,
                child: TileLayer(tileProvider: MBTilesProvider()),
              ),
              if (_showPolygons && _polygonsCache.isNotEmpty)
                PolygonLayer(polygons: _polygonsCache),
              if (_showParcours && _parcours.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _parcours,
                      color: const Color(0xFFFF6B35),
                      strokeWidth: 5,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
              // Points chauds orignal
              if (_showHotspots && _hotspots.isNotEmpty)
                MarkerLayer(
                  markers: _hotspots.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final pos = entry.value;
                    final score = idx < _hotspotInfos.length ? _hotspotInfos[idx].score : 0;
                    final bgColor = score >= 18
                        ? const Color(0xFF1A3A08)
                        : score >= 13
                            ? const Color(0xFF2D5016)
                            : const Color(0xFF5A8A1E);
                    return Marker(
                      point: pos,
                      width: 48,
                      height: 48,
                      child: GestureDetector(
                        onTap: () {
                          if (idx < _hotspotInfos.length) {
                            showHotspotDetail(context, _hotspotInfos[idx]);
                          }
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: bgColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: bgColor.withOpacity(0.5), blurRadius: 6)],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('🔥', style: TextStyle(fontSize: 16, height: 1.1)),
                              Text('$score', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1.1)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),

          // ── RÉTICULE FIXE AU CENTRE ────────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: CustomPaint(
                  size: const Size(48, 48),
                  painter: CrosshairPainter(),
                ),
              ),
            ),
          ),

          // ── EN-TÊTE: Logo + Score ──────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF2D2D2D).withOpacity(0.95),
                    const Color(0xFF1A1A1A).withOpacity(0.95),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF6B35).withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Image.asset('assets/logo.png', height: 32),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.menu, color: Color(0xFFFF6B35), size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_windDeg != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('💨 ', style: TextStyle(fontSize: 14)),
                              Text(
                                '${_windDirection(_windDeg!)} ${_windSpeed?.toStringAsFixed(0)} km/h',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${_currentPosition.latitude.toStringAsFixed(4)}, ${_currentPosition.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 9, color: Color(0xFF888888)),
                          ),
                        ],
                      ),
                    )
                  else
                    const Expanded(
                      child: Text(
                        'Chargement...',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  if (_showParcours)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _parcoursScore > 60
                            ? const Color(0xFF2D5016)
                            : _parcoursScore > 35
                            ? const Color(0xFFFF6B35)
                            : const Color(0xFF8B4513),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_parcoursScore.round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── BOUTON NORD ────────────────────────────────────────
          Positioned(
            top: 80,
            right: 16,
            child: GestureDetector(
              onTap: _resetNorth,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)],
                  ),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: const Color(0xFFFF6B35).withOpacity(0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'N',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF6B35),
                      ),
                    ),
                    Text(
                      '↑',
                      style: TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── BOUTON POINTS CHAUDS ──────────────────────────────
          Positioned(
            top: 142,
            right: 16,
            child: GestureDetector(
              onTap: () {
                if (_showHotspots) {
                  setState(() => _showHotspots = false);
                  return;
                }
                final spots = _computeHotspots();
                setState(() {
                  _hotspots = spots;
                  _showHotspots = spots.isNotEmpty;
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(spots.isEmpty
                      ? 'Aucun point chaud ici — navigue vers ton secteur'
                      : '${spots.length} points chauds dans cette zone'),
                  backgroundColor: spots.isEmpty
                      ? const Color(0xFF8B4513)
                      : const Color(0xFF2D5016),
                  duration: const Duration(seconds: 2),
                ));
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _showHotspots
                        ? [const Color(0xFF2D5016), const Color(0xFF1F3A0F)]
                        : [const Color(0xFF2D2D2D), const Color(0xFF1A1A1A)],
                  ),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: _showHotspots
                        ? const Color(0xFF2D5016)
                        : const Color(0xFFFF6B35).withOpacity(0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _showHotspots
                          ? const Color(0xFF2D5016).withOpacity(0.5)
                          : Colors.black.withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.local_fire_department,
                  color: _showHotspots ? Colors.white : const Color(0xFFFF6B35),
                  size: 26,
                ),
              ),
            ),
          ),

          // ── BARRE PARCOURS ACTIF ──────────────────────────────
          if (_showParcours)
            Positioned(
              bottom: 84,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_parcoursScore > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _parcoursScore > 60
                            ? const Color(0xFF2D5016)
                            : _parcoursScore > 35
                            ? const Color(0xFFFF6B35)
                            : const Color(0xFF8B4513),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_parcoursScore.round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NavigationPage(
                          parcours: _parcours,
                          score: _parcoursScore,
                        ),
                      ),
                    ),
                    child: const Row(children: [
                      Icon(Icons.navigation, color: Color(0xFF2D5016), size: 20),
                      SizedBox(width: 4),
                      Text(
                        'Naviguer',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => setState(() => _showParcours = false),
                    child: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 20),
                  ),
                ]),
              ),
            ),

          // ── BOUTON GPS (bas droite) ────────────────────────────
          Positioned(
            bottom: 16,
            right: 16,
            child: GestureDetector(
              onTap: _goToCurrentLocation,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8)],
                ),
                child: _loading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFFFF6B35),
                          ),
                        ),
                      )
                    : const CustomPaint(
                        size: Size(30, 30),
                        painter: CrosshairPainter(),
                      ),
              ),
            ),
          ),

          // ── BARRE D'ÉCHELLE ────────────────────────────────────
          Positioned(
            bottom: 16,
            left: 16,
            child: ScaleBar(zoom: _mapZoom, lat: _mapLat),
          ),

          // ── SLIDER OPACITÉ ─────────────────────────────────────
          Positioned(
            top: 140,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF2D2D2D).withOpacity(0.9),
                    const Color(0xFF1A1A1A).withOpacity(0.9),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFFF6B35).withOpacity(0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.layers, color: Color(0xFFFF6B35), size: 18),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: const Color(0xFFFF6B35),
                        inactiveTrackColor: const Color(0xFF3D3D3D),
                        thumbColor: const Color(0xFFFF6B35),
                        overlayColor: const Color(0xFFFF6B35).withOpacity(0.3),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: _opacity,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (val) => setState(() => _opacity = val),
                      ),
                    ),
                  ),
                  Text(
                    '${(_opacity * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
