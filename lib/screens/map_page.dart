import 'dart:async';
import 'dart:convert';
import 'dart:math' show pi;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../app_globals.dart';
import '../models/hotspot_info.dart';
import '../painters/painters.dart';
import '../providers/mbtiles_provider.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/geo_service.dart';
import '../services/groupe_service.dart';
import '../services/premium_service.dart';
import '../services/territoire_service.dart';
import '../widgets/aide_dialog.dart';
import '../widgets/hotspot_detail_sheet.dart';
import '../widgets/map_controls.dart';
import '../widgets/scale_bar.dart';
import 'about_page.dart';
import 'chat_page.dart';
import 'login_page.dart';
import 'meteo_page.dart';
import 'navigation_page.dart';
import 'territoire_download_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Types d'observation disponibles
// ─────────────────────────────────────────────────────────────────────────────
const _typesObservation = [
  ('', 'Frottage'),
  ('💧', 'Souille'),
  ('👣', 'Traces'),
  ('📷', 'Caméra'),
  ('💩', 'Crottes'),
  ('🌿', 'Cache'),
  ('🍃', 'Broutage'),
];

// ─────────────────────────────────────────────────────────────────────────────
// MapPage
// ─────────────────────────────────────────────────────────────────────────────
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const double _opacity = 0.7;

  // ── Carte ──
  final MapController _mapController = MapController();
  double _mapZoom = 13.0;
  double _mapLat = 48.2917;
  bool _satellite = false;
  bool _showLayerPanel = false;

  // ── GPS / vent ──
  LatLng _currentPosition = const LatLng(48.2917, -71.322);
  bool _loading = false;
  double? _windDeg;
  double? _windSpeed;
  StreamSubscription<Position>? _positionStream;

  // ── Polygones écoforestiers ──
  List<Polygon> _polygonsCache = [];
  List<Map<String, dynamic>> _polygonLabels = [];

  // ── Hotspots ──
  bool _showHotspots = false;
  List<LatLng> _hotspots = [];
  List<HotspotInfo> _hotspotInfos = [];
  List<HotspotInfo> _rawHotspots = [];
  Timer? _hotspotDebounce;

  // ── Parcours ──
  bool _showParcours = false;
  bool _loadingParcours = false;
  List<LatLng> _parcours = [];
  double _distanceParcours = 2.0;
  double _parcoursScore = 0;

  // ── Affût (pinch points) ──
  bool _showPinchPoints = false;
  bool _loadingPinch = false;
  List<Map<String, dynamic>> _pinchPoints = [];

  // ── Tracé GPS ──
  bool _recording = false;
  List<LatLng> _trackPoints = [];
  final List<({DateTime date, List<LatLng> points})> _savedTracks = [];

  // ── Observations terrain ──
  List<Map<String, dynamic>> _observations = [];

  // ── Groupe ──
  List<Map<String, dynamic>> _obsGroupe = [];
  List<Map<String, dynamic>> _tracesGroupe = [];
  StreamSubscription? _obsGroupeSub;
  StreamSubscription? _tracesGroupeSub;
  String? _groupeId;
  String? _monNom;
  bool _groupeActif = false;
  bool _partagePosition = false;
  List<MembreGroupe> _membres = [];
  StreamSubscription<List<MembreGroupe>>? _groupeStream;

  // ── UI panels ──
  bool _showActionPanel = false;
  bool _showNavPanel = false;

  // ── Connectivité ──
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;

  // ─────────────────────────────────────────────────────────────────────────
  // Cycle de vie
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.isOnline;
    _connectivitySub = ConnectivityService.onStatusChange.listen((online) {
      if (mounted) setState(() => _isOnline = online);
      if (online) _fetchWind();
    });
    _initLocation();
    _fetchWind();
    PremiumService.load();
    Future.delayed(const Duration(seconds: 1), _reloadTerritoire);
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _groupeStream?.cancel();
    _obsGroupeSub?.cancel();
    _tracesGroupeSub?.cancel();
    _hotspotDebounce?.cancel();
    _connectivitySub?.cancel();
    if (_groupeActif && _groupeId != null && _monNom != null) {
      GroupeService.quitter(_groupeId!, _monNom!);
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GPS
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 60),
        ),
      );
      if (mounted) {
        final gpsPos = LatLng(pos.latitude, pos.longitude);
        setState(() => _currentPosition = gpsPos);
        _mapController.move(gpsPos, 13);
        await _fetchWind();
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((position) {
        if (!mounted) return;
        final p = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = p;
          if (_recording) _trackPoints.add(p);
          if (_showHotspots) _hotspots = _computeHotspots();
        });
        if (_groupeActif && _partagePosition && _groupeId != null && _monNom != null) {
          GroupeService.publierPosition(groupeId: _groupeId!, nom: _monNom!, position: p);
        }
      });
    } catch (_) {}
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _loading = true);
    try {
      if (!kIsWeb) {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) {
            setState(() => _loading = false);
            _snack('Active la localisation dans les paramètres', error: true);
          }
          return;
        }
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (mounted) {
          setState(() => _loading = false);
          _snack('Permission de localisation refusée par le navigateur', error: true);
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(pos.latitude, pos.longitude);
          _loading = false;
        });
        _mapController.move(_currentPosition, 13);
        await _fetchWind();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('GPS: autorise la localisation dans ton navigateur', error: true);
      }
    }
  }

  void _resetNorth() => _mapController.rotate(0);

  // ─────────────────────────────────────────────────────────────────────────
  // Vent
  // ─────────────────────────────────────────────────────────────────────────
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
        if (mounted) setState(() {
          _windDeg = data['current']['wind_direction_10m']?.toDouble();
          _windSpeed = data['current']['wind_speed_10m']?.toDouble();
        });
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Territoire écoforestier
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _reloadTerritoire() async {
    final list = await TerritoireService.listTerritoires();
    if (!mounted) return;
    if (list.isEmpty) {
      geoJson = {'type': 'FeatureCollection', 'features': []};
      setState(() { _polygonsCache = []; _polygonLabels = []; });
      return;
    }
    final allFeatures = <dynamic>[];
    for (final t in list) {
      final data = await TerritoireService.loadTerritoire(t['id'] as String);
      if (data != null) allFeatures.addAll(data['features'] as List);
    }
    geoJson = {'type': 'FeatureCollection', 'features': allFeatures};
    final polys = await compute(buildPolygonsIsolate, geoJson);
    final labels = await compute(buildPolygonLabelsIsolate, geoJson);
    final rawHS = await compute(buildHotspotsDataIsolate, geoJson);
    if (!mounted) return;
    final parsedHS = rawHS.map((e) => HotspotInfo(
      position: LatLng(e['la'] as double, e['lo'] as double),
      score: e['s'] as int,
      props: e['p'] as Map,
    )).toList();
    setState(() {
      _polygonsCache = polys;
      _polygonLabels = labels;
      _rawHotspots = parsedHS;
      if (_showHotspots) _hotspots = _computeHotspots();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Hotspots
  // ─────────────────────────────────────────────────────────────────────────
  List<LatLng> _computeHotspots() {
    if (_rawHotspots.isEmpty) return [];
    List<HotspotInfo> candidates = [];
    try {
      final b = _mapController.camera.visibleBounds;
      candidates = _rawHotspots
          .where((h) =>
              h.position.latitude >= b.southWest.latitude &&
              h.position.latitude <= b.northEast.latitude &&
              h.position.longitude >= b.southWest.longitude &&
              h.position.longitude <= b.northEast.longitude)
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
    } catch (_) {}

    if (candidates.isEmpty) {
      try {
        final center = _mapController.camera.center;
        final zoom = _mapController.camera.zoom;
        final delta = 360.0 / (1 << zoom.round());
        candidates = _rawHotspots
            .where((h) =>
                h.position.latitude >= center.latitude - delta &&
                h.position.latitude <= center.latitude + delta &&
                h.position.longitude >= center.longitude - delta * 1.5 &&
                h.position.longitude <= center.longitude + delta * 1.5)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
      } catch (_) {}
    }

    final List<LatLng> result = [];
    final List<HotspotInfo> infos = [];
    for (final info in candidates) {
      final tooClose = result.any(
        (e) => const Distance().as(LengthUnit.Meter, e, info.position) < 200,
      );
      if (!tooClose) {
        result.add(info.position);
        infos.add(info);
      }
      if (result.length >= 5) break;
    }
    _hotspotInfos = infos;
    return result;
  }

  void _toggleHotspots({bool forceRefresh = false}) {
    if (!_requirePremium()) return;
    if (_showHotspots && !forceRefresh) {
      setState(() { _showHotspots = false; _hotspots = []; });
      return;
    }
    if (!_requireEcoMap()) return;
    final spots = _computeHotspots();
    setState(() { _hotspots = spots; _showHotspots = true; });
    _snack(spots.isEmpty
        ? 'Aucun spot ici — navigue vers une zone forestière'
        : '${spots.length} point${spots.length > 1 ? 's' : ''} chaud${spots.length > 1 ? 's' : ''} dans cette zone',
      error: spots.isEmpty);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Parcours
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _genererParcours() async {
    final features = (geoJson['features'] as List?) ?? [];
    if (features.isEmpty) {
      _snack('Télécharge d\'abord une carte écoforestière via "Carte éco"', error: true);
      return;
    }
    setState(() => _loadingParcours = true);
    try {
      final startPos = _mapController.camera.center;
      final topHotspots = (_rawHotspots.toList()
            ..sort((a, b) => b.score.compareTo(a.score)))
          .take(8)
          .map((h) => [h.position.latitude, h.position.longitude])
          .toList();

      final result = await compute(buildParcoursIsolate, {
        'lat': startPos.latitude,
        'lon': startPos.longitude,
        'windRad': (_windDeg ?? 0) * pi / 180,
        'hotspots': topHotspots,
        'targetDist': _distanceParcours * 1000,
        'geoJson': geoJson,
      });

      final rawList = result['points'] as List;
      final scorePct = (result['scorePct'] as num).toDouble();
      final points = rawList.map((p) {
        final coords = p as List;
        return LatLng((coords[0] as num).toDouble(), (coords[1] as num).toDouble());
      }).toList();

      if (!mounted) return;
      setState(() {
        _parcours = points;
        _showParcours = true;
        _parcoursScore = scorePct;
        _loadingParcours = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingParcours = false);
      _snack('Télécharge d\'abord une carte écoforestière via "Carte éco"', error: true);
      return;
    }
    if (_parcours.length < 5) {
      _snack('Parcours limité — télécharge une carte écoforestière plus large', error: true);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Affût (pinch points)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _togglePinchPoints() async {
    if (!_requirePremium()) return;
    if (_showPinchPoints) {
      setState(() { _showPinchPoints = false; _pinchPoints = []; });
      return;
    }
    if (!_requireEcoMap()) return;
    setState(() => _loadingPinch = true);
    try {
      final center = _mapController.camera.center;
      final result = await compute(findPinchPointsIsolate, {
        'lat': center.latitude,
        'lon': center.longitude,
        'radiusM': 3000.0,
        'geoJson': geoJson,
      });
      if (!mounted) return;
      setState(() {
        _pinchPoints = result;
        _showPinchPoints = true;
        _loadingPinch = false;
      });
      if (result.isEmpty) {
        _snack('Aucun affût détecté — télécharge une carte écoforestière via "Carte éco"', error: true);
      } else {
        _snack('${result.length} emplacements d\'affût détectés dans un rayon de 3 km');
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPinch = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tracé GPS
  // ─────────────────────────────────────────────────────────────────────────
  void _toggleRecording() {
    if (_recording) {
      final pts = List<LatLng>.from(_trackPoints);
      setState(() => _recording = false);
      if (pts.length < 2) {
        _snack('Tracé trop court', error: true);
        return;
      }
      setState(() => _savedTracks.add((date: DateTime.now(), points: pts)));
      _snack('Tracé sauvegardé — ${pts.length} points');
    } else {
      setState(() { _recording = true; _trackPoints = []; });
      _snack('Enregistrement démarré — bouge-toi!');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Observations
  // ─────────────────────────────────────────────────────────────────────────
  void _addObservation() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Type d\'observation',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.8,
            children: _typesObservation.map((t) {
              return GestureDetector(
                onTap: () {
                  final pos = _mapController.camera.center;
                  setState(() => _observations.add({
                    'pos': pos,
                    'note': '${t.$1} ${t.$2}',
                    'time': DateTime.now(),
                  }));
                  Navigator.pop(context);
                  _snack('${t.$1} ${t.$2} ajouté');
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFF6B35).withOpacity(0.3)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFFF6B35), width: 1.5),
                        ),
                        child: Center(
                            child: obsIcon('${t.$1} ${t.$2}', size: 20)),
                      ),
                      const SizedBox(width: 8),
                      Text(t.$2,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler',
                style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Groupe
  // ─────────────────────────────────────────────────────────────────────────
  void _sharePosition() {
    if (!_requirePremium()) return;
    _groupeActif ? _panelGroupe() : _dialogueRejoindre();
  }

  void _dialogueRejoindre() {
    final nomCtrl = TextEditingController(text: _monNom);
    final codeCtrl = TextEditingController(text: _groupeId);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Rejoindre un groupe',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _inputField(nomCtrl, 'Ton nom'),
          const SizedBox(height: 12),
          _inputField(codeCtrl, 'Code du groupe (ex: chasse2026)'),
          const SizedBox(height: 8),
          const Text(
              'Tous les chasseurs du même code se voient sur la carte.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler',
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D5016)),
            onPressed: () {
              final nom = nomCtrl.text.trim();
              final code = codeCtrl.text.trim();
              if (nom.isEmpty || code.isEmpty) return;
              Navigator.pop(context);
              _rejoindreGroupe(nom, code);
            },
            child: const Text('Rejoindre',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _panelGroupe() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D2D),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Icon(Icons.people, color: Color(0xFF4A90E2), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Groupe actif',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      Text(_groupeId ?? '',
                          style: const TextStyle(
                              color: Color(0xFF4A90E2), fontSize: 12)),
                    ]),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _quitterGroupe();
                },
                child: const Text('Quitter',
                    style: TextStyle(
                        color: Color(0xFFFF6B35), fontSize: 13)),
              ),
            ]),
            const Divider(color: Colors.white12, height: 24),
            _groupeTile(Icons.chat_bubble_rounded, 'Clavardage du groupe',
                'Messages entre chasseurs', () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                        groupeId: _groupeId!, monNom: _monNom!),
                  ));
            }),
            _groupeTile(
                _partagePosition ? Icons.location_off_rounded : Icons.location_on_rounded,
                _partagePosition ? 'Arrêter le partage GPS' : 'Partager ma position',
                _partagePosition ? 'Ta position est visible par le groupe' : 'Partager ton GPS avec le groupe',
                () {
              Navigator.pop(context);
              setState(() => _partagePosition = !_partagePosition);
              if (_partagePosition) {
                GroupeService.publierPosition(
                    groupeId: _groupeId!, nom: _monNom!, position: _currentPosition);
                _snack('Position GPS partagée avec le groupe');
              } else {
                GroupeService.quitter(_groupeId!, _monNom!);
                _snack('Partage de position arrêté', error: true);
              }
            }),
            _groupeTile(Icons.pin_drop_rounded, 'Partage des observations',
                'Frottages, souilles, traces…', () {
              Navigator.pop(context);
              _partagerObservations();
            }),
            _groupeTile(Icons.route_rounded, 'Partage des tracés',
                'Tracés GPS du groupe', () {
              Navigator.pop(context);
              _partagerTraces();
            }),
          ],
        ),
      ),
    );
  }

  void _rejoindreGroupe(String nom, String groupeId) {
    setState(() {
      _monNom = nom;
      _groupeId = groupeId;
      _groupeActif = true;
      _partagePosition = false;
    });
    _groupeStream?.cancel();
    _groupeStream = GroupeService.ecouterGroupe(groupeId, nom).listen((membres) {
      if (mounted) setState(() => _membres = membres);
    });
    _obsGroupeSub?.cancel();
    _obsGroupeSub = GroupeService.ecouterObservations(groupeId, nom).listen((obs) {
      if (mounted) setState(() => _obsGroupe = obs);
    });
    _tracesGroupeSub?.cancel();
    _tracesGroupeSub = GroupeService.ecouterTraces(groupeId, nom).listen((traces) {
      if (mounted) setState(() => _tracesGroupe = traces);
    });
    _snack('Groupe "$groupeId" rejoint');
  }

  void _quitterGroupe() {
    _groupeStream?.cancel();
    _obsGroupeSub?.cancel();
    _tracesGroupeSub?.cancel();
    if (_groupeId != null && _monNom != null) {
      GroupeService.quitter(_groupeId!, _monNom!);
    }
    setState(() {
      _groupeActif = false;
      _partagePosition = false;
      _membres = [];
      _obsGroupe = [];
      _tracesGroupe = [];
    });
    _snack('Groupe quitté', error: true);
  }

  void _partagerObservations() {
    if (_observations.isEmpty) {
      _snack('Aucune observation à partager', error: true);
      return;
    }
    final db = FirebaseFirestore.instance;
    for (final obs in _observations) {
      final pos = obs['pos'] as LatLng;
      db.collection('groupes').doc(_groupeId).collection('observations').add({
        'nom': _monNom,
        'note': obs['note'],
        'lat': pos.latitude,
        'lon': pos.longitude,
        'ts': FieldValue.serverTimestamp(),
      });
    }
    _snack('${_observations.length} observation(s) partagée(s)');
  }

  void _partagerTraces() {
    if (_savedTracks.isEmpty) {
      _snack('Aucun tracé à partager', error: true);
      return;
    }
    final db = FirebaseFirestore.instance;
    for (final track in _savedTracks) {
      db.collection('groupes').doc(_groupeId).collection('traces').add({
        'nom': _monNom,
        'points': track.points
            .map((p) => {'lat': p.latitude, 'lon': p.longitude})
            .toList(),
        'date': track.date.toIso8601String(),
        'ts': FieldValue.serverTimestamp(),
      });
    }
    _snack('${_savedTracks.length} tracé(s) partagé(s)');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dialogs
  // ─────────────────────────────────────────────────────────────────────────
  void _showParcoursDialog() {
    if (!_requirePremium()) return;
    if (!_requireEcoMap()) return;
    double localDist = _distanceParcours;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D2D),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.route_rounded,
                    color: Color(0xFF5A8A1E), size: 20),
                SizedBox(width: 8),
                Text('Générer un parcours',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                const Text('Distance cible',
                    style: TextStyle(color: Colors.white60, fontSize: 13)),
                Text('${localDist.toStringAsFixed(1)} km',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ]),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: const Color(0xFF5A8A1E),
                  inactiveTrackColor: Colors.white24,
                  thumbColor: const Color(0xFF7DC95E),
                  overlayColor: Colors.transparent,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: localDist,
                  min: 0.5,
                  max: 5.0,
                  divisions: 18,
                  onChanged: (v) => setSheet(() => localDist = v),
                ),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0.5 km',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  Text('5 km',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D5016),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _distanceParcours = localDist;
                      _showParcours = false;
                    });
                    _genererParcours();
                  },
                  child: const Text('Générer le parcours',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTracesDialog() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: const Text('Tracés sauvegardés',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          content: _savedTracks.isEmpty
              ? const Text(
                  'Aucun tracé sauvegardé.\nAppuie sur le bouton Suivi 🔴 pour enregistrer un déplacement.',
                  style: TextStyle(color: Colors.white54, fontSize: 13))
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _savedTracks.length,
                    itemBuilder: (_, i) {
                      final t =
                          _savedTracks[_savedTracks.length - 1 - i];
                      final d = t.date;
                      final label =
                          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
                          '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(label,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        subtitle: Text('${t.points.length} points',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11)),
                        leading: const Icon(Icons.fiber_manual_record,
                            color: Colors.red, size: 20),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Color(0xFFFF6B35), size: 20),
                          onPressed: () {
                            setState(() => _savedTracks.removeAt(
                                _savedTracks.length - 1 - i));
                            setDlg(() {});
                          },
                        ),
                        onTap: () {
                          setState(() => _trackPoints =
                              List<LatLng>.from(t.points));
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
          actions: [
            if (_savedTracks.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() => _savedTracks.clear());
                  setDlg(() {});
                },
                child: const Text('Tout supprimer',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer',
                  style: TextStyle(color: Color(0xFFFF6B35))),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Utilitaires UI
  // ─────────────────────────────────────────────────────────────────────────
  bool _requireEcoMap() {
    final features = (geoJson['features'] as List?) ?? [];
    if (features.isNotEmpty) return true;
    _snack('Télécharge d\'abord une carte éco via le bouton Couches', error: true);
    return false;
  }

  // Retourne true si premium, sinon affiche le dialog d'upgrade
  bool _requirePremium() {
    if (PremiumService.isPremium) return true;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Fonctionnalité Premium',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          'Cette fonctionnalité est disponible avec OrignalScan Premium.\n\n'
          '• Points chauds orignal\n'
          '• Parcours optimisé IA\n'
          '• Postes d\'affût\n'
          '• Groupe de chasseurs\n'
          '• Carte écoforestière',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Pas maintenant',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35)),
            onPressed: () => Navigator.pop(context),
            child: const Text('En savoir plus',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return false;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      backgroundColor: error ? const Color(0xFF8B4513) : const Color(0xFFFF6B35),
      duration: Duration(seconds: error ? 3 : 4),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    ));
  }

  Widget _inputField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFFF6B35))),
        focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFFF6B35))),
      ),
    );
  }

  Widget _groupeTile(IconData icon, String titre, String sous,
      VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF4A90E2).withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF4A90E2), size: 22),
      ),
      title: Text(titre,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Text(sous,
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right,
          color: Colors.white24, size: 18),
      onTap: onTap,
    );
  }

  Widget _navBtn(IconData icon, String label, VoidCallback onTap,
      {Color color = const Color(0xFFBDBDBD)}) {
    return GestureDetector(
      onTap: () {
        setState(() { _showActionPanel = false; _showNavPanel = false; });
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: color.withOpacity(0.45), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 9)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Stack(
        children: [
          _buildMap(),
          _buildCrosshair(),
          _buildStatusBarOverlay(),
          if (_showParcours) _buildParcoursBanner(),
          _buildActionPanel(),
          _buildNavPanel(),
          if (!_isOnline) _buildOfflineBanner(),
          if (_showLayerPanel) _buildLayerPanel(),
          Positioned(
            bottom: 20,
            left: 16,
            child: ScaleBar(zoom: _mapZoom, lat: _mapLat),
          ),
          _buildZoomControls(),
        ],
      ),
    );
  }

  // ── Carte ──────────────────────────────────────────────────────────────
  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(48.2917, -71.322),
        initialZoom: 13,
        minZoom: 5,
        maxZoom: 19,
        onPositionChanged: (pos, _) {
          if (!mounted) return;
          final newZoom = pos.zoom;
          final newLat = pos.center.latitude;
          if ((newZoom - _mapZoom).abs() > 0.1 ||
              (newLat - _mapLat).abs() > 0.001) {
            setState(() { _mapZoom = newZoom; _mapLat = newLat; });
          }
          if (_showHotspots) {
            _hotspotDebounce?.cancel();
            _hotspotDebounce =
                Timer(const Duration(milliseconds: 600), () {
              if (mounted) setState(() => _hotspots = _computeHotspots());
            });
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _satellite
              ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.bastienbouchard.ecomap',
        ),
        Opacity(
          opacity: _opacity,
          child: TileLayer(
            tileProvider: MBTilesProvider(),
            minNativeZoom: mbtilesMinZoom,
            maxNativeZoom: mbtilesMaxZoom,
          ),
        ),
        if (_polygonsCache.isNotEmpty && _mapZoom >= 11)
          PolygonLayer(
              polygons: _polygonsCache, simplificationTolerance: 0),
        if (_polygonLabels.isNotEmpty && _mapZoom >= 14)
          MarkerLayer(
              markers: _polygonLabels
                  .map((l) => Marker(
                        point: LatLng(
                            l['lat'] as double, l['lon'] as double),
                        width: 60, height: 20,
                        child: Text(l['label'] as String,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 3),
                              Shadow(color: Colors.black, blurRadius: 6)
                            ],
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.clip,
                        ),
                      ))
                  .toList()),
        if (_showParcours && _parcours.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(
              points: _parcours,
              color: const Color(0xFFFF6B35),
              strokeWidth: 7,
              borderColor: Colors.white,
              borderStrokeWidth: 2,
            ),
          ]),
        if (_trackPoints.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: _trackPoints,
              color: const Color(0xFFFF6B35),
              strokeWidth: 6,
              borderColor: Colors.white,
              borderStrokeWidth: 2,
            ),
          ]),
        if (_observations.isNotEmpty) _buildObservationMarkers(),
        if (_showHotspots && _hotspots.isNotEmpty) _buildHotspotMarkers(),
        if (_showPinchPoints && _pinchPoints.isNotEmpty)
          _buildPinchMarkers(),
        if (_groupeActif && _tracesGroupe.isNotEmpty)
          _buildGroupeTracePolylines(),
        if (_groupeActif && _obsGroupe.isNotEmpty)
          _buildGroupeObsMarkers(),
        if (_groupeActif && _membres.isNotEmpty) _buildMembreMarkers(),
        _buildCurrentPositionMarker(),
      ],
    );
  }

  // ── Markers ─────────────────────────────────────────────────────────────
  MarkerLayer _buildObservationMarkers() {
    return MarkerLayer(
      markers: _observations.asMap().entries.map((entry) {
        final idx = entry.key;
        final obs = entry.value;
        final pos = obs['pos'] as LatLng;
        final note = obs['note'] as String;
        return Marker(
          point: pos,
          width: 52, height: 52,
          child: GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF2D2D2D),
                title: Text(note,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15)),
                content: Text(
                  '${(obs['time'] as DateTime).hour.toString().padLeft(2, '0')}:'
                  '${(obs['time'] as DateTime).minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      setState(() => _observations.removeAt(idx));
                      Navigator.pop(context);
                    },
                    child: const Text('Supprimer',
                        style: TextStyle(color: Color(0xFFFF6B35))),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ],
              ),
            ),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFFF6B35), width: 2),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 4)
                ],
              ),
              child: Center(child: obsIcon(note)),
            ),
          ),
        );
      }).toList(),
    );
  }

  MarkerLayer _buildHotspotMarkers() {
    return MarkerLayer(
      markers: _hotspots.asMap().entries.map((entry) {
        final idx = entry.key;
        final pos = entry.value;
        final score =
            idx < _hotspotInfos.length ? _hotspotInfos[idx].score : 0;
        final flameColor = score >= 18
            ? const Color(0xFFFF3D00)
            : score >= 13
                ? const Color(0xFFFF6B35)
                : const Color(0xFFFFB347);
        return Marker(
          point: pos,
          width: 56, height: 56,
          child: GestureDetector(
            onTap: () {
              if (idx < _hotspotInfos.length) {
                showHotspotDetail(context, _hotspotInfos[idx]);
              }
            },
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                shape: BoxShape.circle,
                border: Border.all(color: flameColor, width: 3),
                boxShadow: [
                  BoxShadow(
                      color: flameColor.withOpacity(0.7),
                      blurRadius: 12,
                      spreadRadius: 2),
                  const BoxShadow(
                      color: Colors.black54, blurRadius: 4),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_fire_department,
                      color: flameColor, size: 26),
                  Text('$score',
                      style: TextStyle(
                          color: flameColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          height: 1)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  MarkerLayer _buildPinchMarkers() {
    return MarkerLayer(
      markers: _pinchPoints.map((p) {
        final pos = LatLng(p['lat'] as double, p['lon'] as double);
        return Marker(
          point: pos,
          width: 48, height: 48,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              shape: BoxShape.circle,
              border: Border.all(
                  color: const Color(0xFF4CAF50), width: 2.5),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF4CAF50).withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 1),
                const BoxShadow(
                    color: Colors.black54, blurRadius: 4),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.filter_alt,
                    color: Color(0xFF4CAF50), size: 22),
                Text('col',
                    style: TextStyle(
                        color: Color(0xFF4CAF50),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        height: 1)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  MarkerLayer _buildMembreMarkers() {
    return MarkerLayer(
      markers: _membres.map((m) => Marker(
        point: m.position,
        width: 56, height: 56,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90E2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Text(m.nom,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
          const Icon(Icons.person_pin_circle,
              color: Color(0xFF4A90E2), size: 28),
        ]),
      )).toList(),
    );
  }

  PolylineLayer _buildGroupeTracePolylines() {
    final colors = [
      const Color(0xFF4A90E2),
      const Color(0xFF7ED321),
      const Color(0xFFBD10E0),
      const Color(0xFF50E3C2),
    ];
    return PolylineLayer(
      polylines: _tracesGroupe.asMap().entries.map((entry) {
        final i = entry.key;
        final trace = entry.value;
        final pts = (trace['points'] as List).map((p) {
          return LatLng(
            (p['lat'] as num).toDouble(),
            (p['lon'] as num).toDouble(),
          );
        }).toList();
        return Polyline(
          points: pts,
          color: colors[i % colors.length],
          strokeWidth: 4,
          borderColor: Colors.black38,
          borderStrokeWidth: 1,
        );
      }).toList(),
    );
  }

  MarkerLayer _buildGroupeObsMarkers() {
    return MarkerLayer(
      markers: _obsGroupe.map((obs) {
        final pos = LatLng(
          (obs['lat'] as num).toDouble(),
          (obs['lon'] as num).toDouble(),
        );
        final note = obs['note'] as String;
        final nom = obs['nom'] as String;
        return Marker(
          point: pos,
          width: 52, height: 52,
          child: GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF2D2D2D),
                title: Text(note,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                content: Text('Par $nom',
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer',
                        style: TextStyle(color: Color(0xFFFF6B35))),
                  ),
                ],
              ),
            ),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF4A90E2), width: 2),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.5), blurRadius: 4)
                ],
              ),
              child: Center(child: obsIcon(note)),
            ),
          ),
        );
      }).toList(),
    );
  }

  MarkerLayer _buildCurrentPositionMarker() {
    return MarkerLayer(markers: [
      Marker(
        point: _currentPosition,
        width: 20, height: 20,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF4A90E2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4), blurRadius: 4)
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _buildLayerPanel() {
    return Positioned(
      bottom: 90, right: 28,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(0.97),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fond de carte ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text('Fond de carte',
                  style: TextStyle(color: Colors.white54, fontSize: 11,
                      fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            ),
            _layerRadio('OpenStreetMap', Icons.map_rounded, !_satellite,
                () => setState(() { _satellite = false; _showLayerPanel = false; })),
            _layerRadio('Satellite', Icons.satellite_alt_rounded, _satellite,
                () => setState(() { _satellite = true; _showLayerPanel = false; })),
            const Divider(color: Colors.white12, height: 16),
            // ── Superpositions ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Text('Superposition',
                  style: TextStyle(color: Colors.white54, fontSize: 11,
                      fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            ),
            _layerToggle('Carte écoforestière', Icons.forest_rounded,
                _polygonsCache.isNotEmpty,
                () async {
                  setState(() => _showLayerPanel = false);
                  if (!_requirePremium()) return;
                  await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => TerritoireDownloadPage(
                      initialCenter: _mapController.camera.center,
                      initialZoom: _mapController.camera.zoom,
                    ),
                  ));
                  _reloadTerritoire();
                }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _layerRadio(String label, IconData icon, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          Icon(icon, color: selected ? const Color(0xFFFF6B35) : Colors.white54, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
              style: TextStyle(color: selected ? Colors.white : Colors.white60, fontSize: 13))),
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? const Color(0xFFFF6B35) : Colors.white24, size: 18),
        ]),
      ),
    );
  }

  Widget _layerToggle(String label, IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          Icon(icon, color: active ? const Color(0xFFFF6B35) : Colors.white54, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
              style: TextStyle(color: active ? Colors.white : Colors.white60, fontSize: 13))),
          Icon(active ? Icons.check_box : Icons.check_box_outline_blank,
              color: active ? const Color(0xFFFF6B35) : Colors.white24, size: 18),
        ]),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 40, right: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF8B4513).withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6)],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, color: Colors.white, size: 14),
            SizedBox(width: 6),
            Text('Mode hors ligne — GPS, carte et spots disponibles',
                style: TextStyle(color: Colors.white, fontSize: 11),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildCrosshair() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: CustomPaint(
              size: const Size(48, 48), painter: CrosshairPainter()),
        ),
      ),
    );
  }

  Widget _buildStatusBarOverlay() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        height: MediaQuery.of(context).padding.top + 6,
        color: Colors.black.withOpacity(0.45),
      ),
    );
  }

  Widget _buildParcoursBanner() {
    return Positioned(
      bottom: 56, left: 16, right: 90,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFFF6B35).withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.5), blurRadius: 10)
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_parcoursScore > 0)
            Container(
              margin: const EdgeInsets.only(right: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _parcoursScore > 60
                    ? const Color(0xFF2D5016)
                    : _parcoursScore > 35
                        ? const Color(0xFFFF6B35)
                        : const Color(0xFF8B4513),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${_parcoursScore.round()}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NavigationPage(
                  parcours: _parcours,
                  score: _parcoursScore,
                  windDeg: _windDeg,
                ),
              ),
            ),
            child: const Row(children: [
              Icon(Icons.navigation,
                  color: Color(0xFF2D5016), size: 20),
              SizedBox(width: 4),
              Text('Naviguer',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() => _showParcours = false),
            child: const Icon(Icons.close,
                color: Color(0xFFFF6B35), size: 20),
          ),
        ]),
      ),
    );
  }

  // ── Panel gauche — actions ───────────────────────────────────────────────
  Widget _buildActionPanel() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      left: _showActionPanel ? 0 : -70,
      top: 0, bottom: 0,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A).withOpacity(0.94),
                border: Border(
                  top: BorderSide(
                      color: const Color(0xFFFF6B35).withOpacity(0.3)),
                  bottom: BorderSide(
                      color: const Color(0xFFFF6B35).withOpacity(0.3)),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 12,
                      offset: const Offset(4, 0))
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    mapActionBtn(
                      icon: Icons.push_pin_rounded,
                      label: 'Obs.',
                      color: const Color(0xFFFF6B35),
                      active: false,
                      onTap: _addObservation,
                    ),
                    const SizedBox(height: 6),
                    mapActionBtn(
                      icon: Icons.local_fire_department,
                      label: 'Spots',
                      color: const Color(0xFFFF6B35),
                      active: _showHotspots,
                      onTap: _toggleHotspots,
                      onLongPress: _showHotspots
                          ? () => _toggleHotspots(forceRefresh: true)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    mapActionBtn(
                      icon: Icons.route_rounded,
                      label: 'Parcours',
                      color: const Color(0xFF4CAF50),
                      active: _showParcours,
                      loading: _loadingParcours,
                      onTap: _showParcours
                          ? () => setState(() => _showParcours = false)
                          : _showParcoursDialog,
                    ),
                    const SizedBox(height: 6),
                    mapActionBtn(
                      icon: Icons.cabin,
                      label: 'Affût',
                      color: const Color(0xFF4CAF50),
                      active: _showPinchPoints,
                      loading: _loadingPinch,
                      onTap: _togglePinchPoints,
                      customIcon: const SizedBox(
                        width: 22, height: 22,
                        child: CustomPaint(
                            painter: HuntingTowerPainter()),
                      ),
                    ),
                    const SizedBox(height: 6),
                    mapActionBtn(
                      icon: Icons.people,
                      label: 'Groupe',
                      color: _isOnline ? const Color(0xFFFF6B35) : Colors.white24,
                      active: _groupeActif,
                      onTap: _isOnline
                          ? _sharePosition
                          : () => _snack('Groupe non disponible hors ligne', error: true),
                    ),
                    const SizedBox(height: 6),
                    mapActionBtn(
                      icon: Icons.fiber_manual_record,
                      label: 'Suivi',
                      color: Colors.red,
                      active: _recording,
                      onTap: _toggleRecording,
                      customIcon: Icon(
                        _recording ? Icons.stop_rounded : Icons.fiber_manual_record,
                        color: Colors.red,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () =>
                  setState(() => _showActionPanel = !_showActionPanel),
              child: Container(
                width: 28, height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D).withOpacity(0.92),
                  borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(12)),
                  border: Border(
                    right: BorderSide(
                        color: const Color(0xFFFF6B35).withOpacity(0.4)),
                    top: BorderSide(
                        color: const Color(0xFFFF6B35).withOpacity(0.4)),
                    bottom: BorderSide(
                        color: const Color(0xFFFF6B35).withOpacity(0.4)),
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(2, 0))
                  ],
                ),
                child: Icon(
                  _showActionPanel
                      ? Icons.chevron_left
                      : Icons.chevron_right,
                  color: const Color(0xFFFF6B35),
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Panel droit — navigation ─────────────────────────────────────────────
  Widget _buildNavPanel() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      right: _showNavPanel ? 0 : -70,
      top: 0, bottom: 0,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () =>
                  setState(() => _showNavPanel = !_showNavPanel),
              child: Container(
                width: 28, height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D).withOpacity(0.88),
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12)),
                  border: const Border(
                    left: BorderSide(color: Colors.white24),
                    top: BorderSide(color: Colors.white24),
                    bottom: BorderSide(color: Colors.white24),
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(-2, 0))
                  ],
                ),
                child: Icon(
                  _showNavPanel
                      ? Icons.chevron_right
                      : Icons.chevron_left,
                  color: Colors.white54,
                  size: 16,
                ),
              ),
            ),
            Container(
              width: 70,
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                border: Border(
                  top: BorderSide(color: Colors.white12),
                  bottom: BorderSide(color: Colors.white12),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 12,
                      offset: Offset(-4, 0))
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _navBtn(Icons.wb_sunny_rounded, 'Météo',
                        _isOnline ? () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => MeteoPage(
                            latitude: _currentPosition.latitude,
                            longitude: _currentPosition.longitude,
                            windDeg: _windDeg,
                            windSpeed: _windSpeed,
                          ),
                        )) : () => _snack('Météo non disponible hors ligne', error: true),
                        color: _isOnline ? const Color(0xFFBDBDBD) : Colors.white24),
                    const SizedBox(height: 10),
                    _navBtn(Icons.save_alt_rounded, 'Tracés',
                        _showTracesDialog),
                    const SizedBox(height: 10),
                    _navBtn(Icons.info_outline_rounded, 'À propos',
                        () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const AboutPage(),
                            ))),
                    const SizedBox(height: 10),
                    _navBtn(Icons.help_outline_rounded, 'Aide',
                        () => showAideDialog(context)),
                    const SizedBox(height: 10),
                    _navBtn(Icons.logout_rounded, 'Quitter',
                        () async {
                      await AuthService.signOut();
                      if (mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LoginPage()),
                          (_) => false,
                        );
                      }
                    }, color: Colors.white38),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Contrôles zoom + Nord / GPS / Satellite ──────────────────────────────
  Widget _buildZoomControls() {
    return Positioned(
      bottom: 20, right: 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A).withOpacity(0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.4), blurRadius: 6)
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                mapIconBtn(Icons.explore, _resetNorth),
                mapDividerV(),
                mapIconBtn(Icons.my_location, _goToCurrentLocation,
                    loading: _loading),
                mapDividerV(),
                mapIconBtn(
                  Icons.layers_rounded,
                  () => setState(() => _showLayerPanel = !_showLayerPanel),
                  active: _showLayerPanel,
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A).withOpacity(0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.zoom_in, color: Colors.white, size: 22),
                const SizedBox(width: 4),
                SizedBox(
                  width: 110, height: 32,
                  child: ClipRect(
                    child: OverflowBox(
                      maxHeight: 56,
                      alignment: Alignment.center,
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: const Color(0xFFFF6B35),
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayShape: SliderComponentShape.noOverlay,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 9),
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: _mapZoom.clamp(5.0, 19.0),
                          min: 8.0,
                          max: 19.0,
                          onChanged: (val) {
                            _mapController.move(
                                _mapController.camera.center, val);
                            setState(() => _mapZoom = val);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Text('${((_mapZoom.clamp(5.0, 19.0) - 5.0) / 14.0 * 100).round()}%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
