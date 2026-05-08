import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../app_globals.dart';
import '../services/groupe_service.dart';
import '../models/hotspot_info.dart';
import '../services/geo_service.dart';
import '../painters/painters.dart';
import '../providers/mbtiles_provider.dart';
import '../widgets/scale_bar.dart';
import '../widgets/hotspot_detail_sheet.dart';
import 'about_page.dart';
import 'territoire_download_page.dart';
import '../services/territoire_service.dart';
import 'chat_page.dart';
import 'meteo_page.dart';
import 'navigation_page.dart';
import 'parcours_page.dart';

class _AideItem extends StatelessWidget {
  final String title;
  final String desc;
  const _AideItem(this.title, this.desc);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$title  ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            TextSpan(text: desc, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  double _opacity = 0.5;
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(48.2917, -71.322);
  bool _loading = false;
  bool _loadingParcours = false;
  double? _windDeg;
  double? _windSpeed;
  List<LatLng> _parcours = [];
  double _distanceParcours = 2.0;
  bool _showParcours = false;
  List<Polygon> _polygonsCache = [];
  List<Map<String, dynamic>> _polygonLabels = [];
  double _parcoursScore = 0;
  bool _showHotspots = false;
  List<LatLng> _hotspots = [];
  List<HotspotInfo> _hotspotInfos = [];
  List<HotspotInfo> _rawHotspots = [];
  double _mapZoom = 13.0;
  double _mapLat = 48.2917;
  StreamSubscription<Position>? _positionStream;
  Timer? _hotspotDebounce;
  List<Map<String, dynamic>> _observations = [];
  String? _groupeId;
  String? _monNom;
  bool _groupeActif = false;
  List<MembreGroupe> _membres = [];
  StreamSubscription<List<MembreGroupe>>? _groupeStream;
  bool _recording = false;
  List<LatLng> _trackPoints = [];
  final List<({DateTime date, List<LatLng> points})> _savedTracks = [];
  bool _showPinchPoints = false;
  List<Map<String, dynamic>> _pinchPoints = [];
  bool _loadingPinch = false;
  bool _showActionPanel = false;
  bool _showNavPanel = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _fetchWind();
    Future.delayed(const Duration(seconds: 1), () async {
      await _reloadTerritoire();
    });
    compute(buildHotspotsDataIsolate, geoJson).then((raw) {
      if (mounted) {
        setState(() {
          _rawHotspots = raw.map((e) => HotspotInfo(
            position: LatLng(e['la'] as double, e['lo'] as double),
            score: e['s'] as int,
            props: e['p'] as Map,
          )).toList();
          if (_showHotspots) _hotspots = _computeHotspots();
        });
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

      // Position initiale
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

      // Suivi continu — met à jour la position en temps réel
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Mise à jour tous les 10m
        ),
      ).listen((position) {
        if (mounted) {
          final pos = LatLng(position.latitude, position.longitude);
          setState(() {
            _currentPosition = pos;
            if (_recording) _trackPoints.add(pos);
            if (_showHotspots) _hotspots = _computeHotspots();
          });
          if (_groupeActif && _groupeId != null && _monNom != null) {
            GroupeService.publierPosition(groupeId: _groupeId!, nom: _monNom!, position: pos);
          }
        }
      });
    } catch (e) {}
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _groupeStream?.cancel();
    _hotspotDebounce?.cancel();
    if (_groupeActif && _groupeId != null && _monNom != null) {
      GroupeService.quitter(_groupeId!, _monNom!);
    }
    super.dispose();
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _loading = true);
    try {
      // Sur web, on saute le check isLocationServiceEnabled (peu fiable)
      if (!kIsWeb) {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Active la localisation dans les paramètres'),
              backgroundColor: Color(0xFFFF6B35),
            ));
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Permission de localisation refusée par le navigateur'),
            backgroundColor: Color(0xFFFF6B35),
          ));
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 15));
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
            content: Text('GPS: autorise la localisation dans ton navigateur'),
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

  // Génère un parcours dans un isolate séparé pour ne pas bloquer le thread UI
  Future<void> _genererParcours() async {
    setState(() => _loadingParcours = true);

    try {
      // Départ = centre de l'écran (réticule), pas le GPS
      final startPos = _mapController.camera.center;

      // Direction vers les meilleurs hotspots (triés par score)
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur parcours: $e'),
            backgroundColor: const Color(0xFF8B4513)),
      );
      return;
    }

    if (_parcours.length < 5) {
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

  List<LatLng> _computeHotspots() {
    if (_rawHotspots.isEmpty) return [];

    List<HotspotInfo> candidates = [];

    // Essaie visibleBounds d'abord, sinon calcule la zone depuis le centre + zoom
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

    // Fallback : calcul de la zone visible depuis zoom + centre
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

  static const _typesObservation = [
    ('🦌', 'Frottage'),
    ('💧', 'Souille'),
    ('👣', 'Traces'),
    ('📷', 'Caméra'),
    ('💩', 'Crottes'),
    ('🌿', 'Cache'),
    ('🍃', 'Broutage'),
  ];

  void _addObservation() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Type d\'observation', style: TextStyle(color: Colors.white, fontSize: 16)),
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
                  final obsPos = _mapController.camera.center;
                  setState(() => _observations.add({
                    'pos': obsPos,
                    'note': '${t.$1} ${t.$2}',
                    'time': DateTime.now(),
                  }));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${t.$1} ${t.$2} ajouté'),
                    backgroundColor: const Color(0xFF2D5016),
                    duration: const Duration(seconds: 1),
                  ));
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(t.$1, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(t.$2, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _sharePosition() {
    if (!_groupeActif) {
      _dialogueRejoindre();
    } else {
      _panelGroupe();
    }
  }

  void _dialogueRejoindre() {
    final nomCtrl = TextEditingController(text: _monNom);
    final codeCtrl = TextEditingController(text: _groupeId);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Rejoindre un groupe', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nomCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Ton nom', labelStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6B35))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6B35))),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: codeCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Code du groupe (ex: chasse2026)',
              labelStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6B35))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6B35))),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Tous les chasseurs du même code se voient sur la carte.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Annuler', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D5016)),
            onPressed: () {
              final nom = nomCtrl.text.trim();
              final code = codeCtrl.text.trim();
              if (nom.isEmpty || code.isEmpty) return;
              Navigator.pop(context);
              _rejoindreGroupe(nom, code);
            },
            child: const Text('Rejoindre', style: TextStyle(color: Colors.white)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Icon(Icons.people, color: Color(0xFF4A90E2), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Groupe actif', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(_groupeId ?? '', style: const TextStyle(color: Color(0xFF4A90E2), fontSize: 12)),
                ]),
              ),
              TextButton(
                onPressed: () { Navigator.pop(context); _quitterGroupe(); },
                child: const Text('Quitter', style: TextStyle(color: Color(0xFFFF6B35), fontSize: 13)),
              ),
            ]),
            const Divider(color: Colors.white12, height: 24),
            _groupeTile(
              Icons.location_on_rounded, 'Position du groupe',
              'Positions GPS en temps réel',
              () { Navigator.pop(context); },
            ),
            _groupeTile(
              Icons.chat_bubble_rounded, 'Clavardage du groupe',
              'Messages entre chasseurs',
              () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatPage(groupeId: _groupeId!, monNom: _monNom!),
                ));
              },
            ),
            _groupeTile(
              Icons.pin_drop_rounded, 'Partage des observations',
              'Frottages, souilles, traces…',
              () {
                Navigator.pop(context);
                _partagerObservations();
              },
            ),
            _groupeTile(
              Icons.route_rounded, 'Partage des tracés',
              'Tracés GPS du groupe',
              () {
                Navigator.pop(context);
                _partagerTraces();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupeTile(IconData icon, String titre, String sous, VoidCallback onTap) {
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
      title: Text(titre, style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Text(sous, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
      onTap: onTap,
    );
  }

  void _partagerObservations() {
    if (_observations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucune observation à partager'),
        backgroundColor: Color(0xFF8B4513),
        duration: Duration(seconds: 2),
      ));
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_observations.length} observation(s) partagée(s)'),
      backgroundColor: const Color(0xFF2D5016),
      duration: const Duration(seconds: 2),
    ));
  }

  void _partagerTraces() {
    if (_savedTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun tracé à partager'),
        backgroundColor: Color(0xFF8B4513),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final db = FirebaseFirestore.instance;
    for (final track in _savedTracks) {
      db.collection('groupes').doc(_groupeId).collection('traces').add({
        'nom': _monNom,
        'points': track.points.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
        'date': track.date.toIso8601String(),
        'ts': FieldValue.serverTimestamp(),
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_savedTracks.length} tracé(s) partagé(s)'),
      backgroundColor: const Color(0xFF2D5016),
      duration: const Duration(seconds: 2),
    ));
  }

  void _rejoindreGroupe(String nom, String groupeId) {
    setState(() {
      _monNom = nom;
      _groupeId = groupeId;
      _groupeActif = true;
    });
    // Publier ma position immédiatement
    GroupeService.publierPosition(groupeId: groupeId, nom: nom, position: _currentPosition);
    // Écouter les autres membres
    _groupeStream?.cancel();
    _groupeStream = GroupeService.ecouterGroupe(groupeId, nom).listen((membres) {
      if (mounted) setState(() => _membres = membres);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Groupe "$groupeId" rejoint — ta position est partagée'),
      backgroundColor: const Color(0xFF2D5016),
    ));
  }

  void _quitterGroupe() {
    _groupeStream?.cancel();
    if (_groupeId != null && _monNom != null) {
      GroupeService.quitter(_groupeId!, _monNom!);
    }
    setState(() { _groupeActif = false; _membres = []; });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Groupe quitté'), backgroundColor: Color(0xFF8B4513)));
  }

  void _toggleHotspots({bool forceRefresh = false}) {
    if (_showHotspots && !forceRefresh) {
      setState(() { _showHotspots = false; _hotspots = []; });
      return;
    }
    if (_rawHotspots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Données habitat non chargées — patiente un instant'),
        backgroundColor: Color(0xFF8B4513),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final spots = _computeHotspots();
    setState(() { _hotspots = spots; _showHotspots = true; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(spots.isEmpty
          ? 'Aucun spot ici — navigue vers une zone forestière'
          : '${spots.length} point${spots.length > 1 ? 's' : ''} chaud${spots.length > 1 ? 's' : ''} dans cette zone'),
      backgroundColor: spots.isEmpty ? const Color(0xFF8B4513) : const Color(0xFF2D5016),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _reloadTerritoire() async {
    final list = await TerritoireService.listTerritoires();
    if (!mounted) return;
    if (list.isEmpty) {
      geoJson = {'type': 'FeatureCollection', 'features': []};
      if (mounted) setState(() { _polygonsCache = []; _polygonLabels = []; });
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
    if (mounted) setState(() { _polygonsCache = polys; _polygonLabels = labels; });
  }

  Future<void> _togglePinchPoints() async {
    if (_showPinchPoints) {
      setState(() { _showPinchPoints = false; _pinchPoints = []; });
      return;
    }
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun corridor détecté — navigue vers une zone avec eau ou coupes'),
          backgroundColor: Color(0xFF8B4513),
          duration: Duration(seconds: 3),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${result.length} corridors détectés dans un rayon de 3 km'),
          backgroundColor: const Color(0xFF2D5016),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _loadingPinch = false);
    }
  }

  void _toggleRecording() {
    if (_recording) {
      final pts = List<LatLng>.from(_trackPoints);
      setState(() => _recording = false);
      if (pts.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tracé trop court'),
          backgroundColor: Color(0xFF8B4513),
          duration: Duration(seconds: 2),
        ));
        return;
      }
      setState(() => _savedTracks.add((date: DateTime.now(), points: pts)));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Tracé sauvegardé — ${pts.length} points'),
        backgroundColor: const Color(0xFF2D5016),
        duration: const Duration(seconds: 2),
      ));
    } else {
      setState(() {
        _recording = true;
        _trackPoints = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enregistrement démarré — bouge-toi!'),
        backgroundColor: const Color(0xFF2D2D2D),
        duration: Duration(seconds: 2),
      ));
    }
  }

  Widget _obsBtn() => _actionBtn(
    icon: Icons.push_pin_rounded,
    label: 'Obs.',
    color: const Color(0xFFFF6B35),
    active: false,
    onTap: _addObservation,
  );

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required bool active,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: active ? color.withOpacity(0.25) : const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: active ? color : color.withOpacity(0.4),
                width: active ? 2 : 1,
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6)],
            ),
            child: loading
                ? Center(child: SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: color)))
                : Icon(icon, color: active ? color : color.withOpacity(0.8), size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: active ? color : Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }

  void _showParcoursDialog() {
    double localDist = _distanceParcours;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D2D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.route_rounded, color: Color(0xFF5A8A1E), size: 20),
                SizedBox(width: 8),
                Text('Générer un parcours',
                    style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Distance cible',
                    style: TextStyle(color: Colors.white60, fontSize: 13)),
                Text('${localDist.toStringAsFixed(1)} km',
                    style: const TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ]),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: const Color(0xFF5A8A1E),
                  inactiveTrackColor: Colors.white24,
                  thumbColor: const Color(0xFF7DC95E),
                  overlayColor: Colors.transparent,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
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
                  Text('0.5 km', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  Text('5 km', style: TextStyle(color: Colors.white38, fontSize: 11)),
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
                      style: TextStyle(color: Colors.white, fontSize: 15,
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
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          content: _savedTracks.isEmpty
              ? const Text('Aucun tracé sauvegardé.\nAppuie sur ⏺ pour enregistrer un déplacement.',
                  style: TextStyle(color: Colors.white54, fontSize: 13))
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _savedTracks.length,
                    itemBuilder: (_, i) {
                      final t = _savedTracks[_savedTracks.length - 1 - i];
                      final d = t.date;
                      final label =
                          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
                          '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(label,
                            style: const TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: Text('${t.points.length} points',
                            style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        leading: const Icon(Icons.route, color: Color(0xFFE53935), size: 20),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Color(0xFFFF6B35), size: 20),
                          onPressed: () {
                            setState(() => _savedTracks.removeAt(_savedTracks.length - 1 - i));
                            setDlg(() {});
                          },
                        ),
                        onTap: () {
                          setState(() => _trackPoints = List<LatLng>.from(t.points));
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
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer', style: TextStyle(color: Color(0xFFFF6B35))),
            ),
          ],
        ),
      ),
    );
  }

  void _showAide() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Aide', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AideItem('🔥 Spots', 'Affiche les 5 meilleurs habitats d\'orignal dans la zone visible. Se met à jour en déplaçant la carte.'),
              _AideItem('🗺 Parcours', 'Génère un itinéraire optimisé selon le vent et l\'habitat. Ajuste la distance avant de générer.'),
              _AideItem('👥 Groupe', 'Partage ta position GPS en temps réel avec les autres chasseurs du même code.'),
              _AideItem('🧭 Nord', 'Réoriente la carte vers le nord.'),
              _AideItem('📍 GPS', 'Centre la carte sur ta position actuelle.'),
              _AideItem('⏺ Tracé', 'Enregistre ton déplacement GPS. Appuie sur Stop pour sauvegarder.'),
              _AideItem('! Obs.', 'Ajoute une observation terrain (frottage, traces, souille…) au centre de l\'écran.'),
              _AideItem('🔻 Cols', 'Détecte les corridors naturels (pinch points) dans un rayon de 3 km — endroits où l\'orignal est forcé de passer.'),
              _AideItem('Slider', 'Contrôle la transparence de la couche de scoring habitat.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer', style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
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
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: color.withOpacity(0.45), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 9)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
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
                if (!mounted) return;
                final newZoom = pos.zoom;
                final newLat = pos.center.latitude;
                if ((newZoom - _mapZoom).abs() > 0.1 || (newLat - _mapLat).abs() > 0.001) {
                  setState(() {
                    _mapZoom = newZoom;
                    _mapLat = newLat;
                  });
                }
                if (_showHotspots) {
                  _hotspotDebounce?.cancel();
                  _hotspotDebounce = Timer(const Duration(milliseconds: 600), () {
                    if (mounted) setState(() => _hotspots = _computeHotspots());
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ecomap',
              ),
              Opacity(
                opacity: _opacity,
                child: TileLayer(
                  tileProvider: MBTilesProvider(),
                  minNativeZoom: mbtilesMinZoom,
                  maxNativeZoom: mbtilesMaxZoom,
                ),
              ),
              if (_polygonsCache.isNotEmpty && _mapZoom >= 11 && _opacity > 0.02)
                PolygonLayer(polygons: _polygonsCache, simplificationTolerance: 0),
              if (_polygonLabels.isNotEmpty && _mapZoom >= 14)
                MarkerLayer(markers: _polygonLabels.map((l) => Marker(
                  point: LatLng(l['lat'] as double, l['lon'] as double),
                  width: 40, height: 14,
                  child: Text(l['label'] as String,
                    style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                    textAlign: TextAlign.center, overflow: TextOverflow.clip),
                )).toList()),
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
              if (_trackPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trackPoints,
                      color: const Color(0xFFE53935),
                      strokeWidth: 4,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
              // Observations terrain
              if (_observations.isNotEmpty)
                MarkerLayer(
                  markers: _observations.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final obs = entry.value;
                    final pos = obs['pos'] as LatLng;
                    final note = obs['note'] as String;
                    return Marker(
                      point: pos,
                      width: 52,
                      height: 52,
                      child: GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: const Color(0xFF2D2D2D),
                              title: Text(note, style: const TextStyle(color: Colors.white, fontSize: 15)),
                              content: Text(
                                '${(obs['time'] as DateTime).hour.toString().padLeft(2, '0')}:${(obs['time'] as DateTime).minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    setState(() => _observations.removeAt(idx));
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Supprimer', style: TextStyle(color: Color(0xFFFF6B35))),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Fermer', style: TextStyle(color: Colors.white54)),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D1A00),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFFFB347), width: 2),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4)],
                          ),
                          child: Center(
                            child: Text(
                              note.split(' ').first,
                              style: const TextStyle(fontSize: 20, height: 1),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              // Points chauds orignal
              if (_showHotspots && _hotspots.isNotEmpty)
                MarkerLayer(
                  markers: _hotspots.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final pos = entry.value;
                    final score = idx < _hotspotInfos.length ? _hotspotInfos[idx].score : 0;
                    final flameColor = score >= 18
                        ? const Color(0xFFFF3D00)
                        : score >= 13
                            ? const Color(0xFFFF6B35)
                            : const Color(0xFFFFB347);
                    return Marker(
                      point: pos,
                      width: 56,
                      height: 56,
                      child: GestureDetector(
                        onTap: () {
                          if (idx < _hotspotInfos.length) {
                            showHotspotDetail(context, _hotspotInfos[idx]);
                          }
                        },
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            shape: BoxShape.circle,
                            border: Border.all(color: flameColor, width: 3),
                            boxShadow: [
                              BoxShadow(color: flameColor.withOpacity(0.7), blurRadius: 12, spreadRadius: 2),
                              const BoxShadow(color: Colors.black54, blurRadius: 4),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.local_fire_department, color: flameColor, size: 26),
                              Text('$score', style: TextStyle(color: flameColor, fontSize: 10,
                                  fontWeight: FontWeight.bold, height: 1)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              // Corridors / pinch points
              if (_showPinchPoints && _pinchPoints.isNotEmpty)
                MarkerLayer(
                  markers: _pinchPoints.map((p) {
                    final pos = LatLng(p['lat'] as double, p['lon'] as double);
                    return Marker(
                      point: pos,
                      width: 48,
                      height: 48,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF4CAF50), width: 2.5),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF4CAF50).withOpacity(0.5),
                                blurRadius: 10, spreadRadius: 1),
                            const BoxShadow(color: Colors.black54, blurRadius: 4),
                          ],
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.filter_alt, color: Color(0xFF4CAF50), size: 22),
                            Text('col', style: TextStyle(color: Color(0xFF4CAF50),
                                fontSize: 9, fontWeight: FontWeight.bold, height: 1)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              // Membres du groupe
              if (_groupeActif && _membres.isNotEmpty)
                MarkerLayer(
                  markers: _membres.map((m) => Marker(
                    point: m.position,
                    width: 56,
                    height: 56,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A90E2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(m.nom, style: const TextStyle(color: Colors.white,
                            fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const Icon(Icons.person_pin_circle, color: Color(0xFF4A90E2), size: 28),
                    ]),
                  )).toList(),
                ),
              // ── POSITION ACTUELLE (point bleu) ────────────────
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
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

          // ── BANDE STATUS BAR ───────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: MediaQuery.of(context).padding.top + 6,
              color: Colors.black.withOpacity(0.45),
            ),
          ),

          // ── BARRE PARCOURS ACTIF ──────────────────────────────
          if (_showParcours)
            Positioned(
              bottom: 56,
              left: 16,
              right: 90,
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
                          windDeg: _windDeg,
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

          // ── PANEL GAUCHE — ACTIONS (coloré) ──────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            left: _showActionPanel ? 0 : -70,
            top: 0,
            bottom: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withOpacity(0.94),
                      border: Border(
                        top: BorderSide(color: const Color(0xFFFF6B35).withOpacity(0.3)),
                        bottom: BorderSide(color: const Color(0xFFFF6B35).withOpacity(0.3)),
                      ),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 12, offset: const Offset(4, 0))],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _obsBtn(),
                          const SizedBox(height: 10),
                          _actionBtn(
                            icon: Icons.local_fire_department,
                            label: 'Spots',
                            color: const Color(0xFFFF6B35),
                            active: _showHotspots,
                            onTap: _toggleHotspots,
                            onLongPress: _showHotspots
                                ? () => _toggleHotspots(forceRefresh: true)
                                : null,
                          ),
                          const SizedBox(height: 10),
                          _actionBtn(
                            icon: Icons.route_rounded,
                            label: 'Parcours',
                            color: const Color(0xFF4CAF50),
                            active: _showParcours,
                            loading: _loadingParcours,
                            onTap: _showParcours
                                ? () => setState(() => _showParcours = false)
                                : _showParcoursDialog,
                          ),
                          const SizedBox(height: 10),
                          _actionBtn(
                            icon: Icons.filter_alt,
                            label: 'Cols',
                            color: const Color(0xFF4CAF50),
                            active: _showPinchPoints,
                            loading: _loadingPinch,
                            onTap: _togglePinchPoints,
                          ),
                          const SizedBox(height: 10),
                          _actionBtn(
                            icon: Icons.people,
                            label: 'Groupe',
                            color: const Color(0xFFFF6B35),
                            active: _groupeActif,
                            onTap: _sharePosition,
                          ),
                          const SizedBox(height: 10),
                          _actionBtn(
                            icon: _recording ? Icons.stop : Icons.fiber_manual_record,
                            label: _recording ? 'Stop' : 'Tracé',
                            color: const Color(0xFFE53935),
                            active: _recording,
                            onTap: _toggleRecording,
                          ),
                          const SizedBox(height: 10),
                          _actionBtn(
                            icon: Icons.my_location,
                            label: 'GPS',
                            color: const Color(0xFFBDBDBD),
                            active: false,
                            loading: _loading,
                            onTap: _goToCurrentLocation,
                          ),
                          const SizedBox(height: 10),
                          _actionBtn(
                            icon: Icons.explore,
                            label: 'Nord',
                            color: const Color(0xFFBDBDBD),
                            active: false,
                            onTap: _resetNorth,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Onglet droit du panel gauche
                  GestureDetector(
                    onTap: () => setState(() => _showActionPanel = !_showActionPanel),
                    child: Container(
                      width: 28,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D).withOpacity(0.92),
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                        border: Border(
                          right: BorderSide(color: const Color(0xFFFF6B35).withOpacity(0.4)),
                          top: BorderSide(color: const Color(0xFFFF6B35).withOpacity(0.4)),
                          bottom: BorderSide(color: const Color(0xFFFF6B35).withOpacity(0.4)),
                        ),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8, offset: const Offset(2, 0))],
                      ),
                      child: Icon(
                        _showActionPanel ? Icons.chevron_left : Icons.chevron_right,
                        color: const Color(0xFFFF6B35),
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── PANEL DROIT — NAVIGATION (grisâtre) ──────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            right: _showNavPanel ? 0 : -70,
            top: 0,
            bottom: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Onglet gauche du panel droit
                  GestureDetector(
                    onTap: () => setState(() => _showNavPanel = !_showNavPanel),
                    child: Container(
                      width: 28,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D).withOpacity(0.88),
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                        border: Border(
                          left: BorderSide(color: Colors.white24),
                          top: BorderSide(color: Colors.white24),
                          bottom: BorderSide(color: Colors.white24),
                        ),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8, offset: const Offset(-2, 0))],
                      ),
                      child: Icon(
                        _showNavPanel ? Icons.chevron_right : Icons.chevron_left,
                        color: Colors.white54,
                        size: 16,
                      ),
                    ),
                  ),
                  Container(
                    width: 70,
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withOpacity(0.90),
                      border: const Border(
                        top: BorderSide(color: Colors.white12),
                        bottom: BorderSide(color: Colors.white12),
                      ),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 12, offset: const Offset(-4, 0))],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _navBtn(Icons.wb_sunny_rounded, 'Météo', () => Navigator.push(context, MaterialPageRoute(builder: (_) => MeteoPage(
                            latitude: _currentPosition.latitude,
                            longitude: _currentPosition.longitude,
                            windDeg: _windDeg,
                            windSpeed: _windSpeed,
                          )))),
                          const SizedBox(height: 10),
                          _navBtn(Icons.save_alt_rounded, 'Tracés', _showTracesDialog),
                          const SizedBox(height: 10),
                          _navBtn(Icons.download_rounded, 'Territoire', () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => TerritoireDownloadPage(initialCenter: _mapController.camera.center, initialZoom: _mapController.camera.zoom)));
                            _reloadTerritoire();
                          }),
                          const SizedBox(height: 10),
                          _navBtn(Icons.info_outline_rounded, 'À propos', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage()))),
                          const SizedBox(height: 10),
                          _navBtn(Icons.help_outline_rounded, 'Aide', _showAide),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── BARRE D'ÉCHELLE ────────────────────────────────────
          Positioned(
            bottom: 20,
            left: 16,
            child: ScaleBar(zoom: _mapZoom, lat: _mapLat),
          ),

          // ── SLIDERS ZOOM + OPACITÉ (droite) ──────────────────────
          Positioned(
            bottom: 20,
            right: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Slider zoom
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.zoom_in, color: Colors.white70, size: 16),
                      SizedBox(
                        width: 120,
                        height: 28,
                        child: ClipRect(
                          child: OverflowBox(
                            maxHeight: 52,
                            alignment: Alignment.center,
                            child: SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: const Color(0xFFFF6B35),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayShape: SliderComponentShape.noOverlay,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                trackHeight: 3,
                              ),
                              child: Slider(
                                value: _mapZoom.clamp(8.0, 19.0),
                                min: 8.0,
                                max: 19.0,
                                onChanged: (val) {
                                  _mapController.move(_mapController.camera.center, val);
                                  setState(() => _mapZoom = val);
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'z${_mapZoom.round()}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Slider opacité
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.layers, color: Colors.white70, size: 16),
                      SizedBox(
                        width: 120,
                        height: 28,
                        child: ClipRect(
                          child: OverflowBox(
                            maxHeight: 52,
                            alignment: Alignment.center,
                            child: SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: const Color(0xFFFF6B35),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayShape: SliderComponentShape.noOverlay,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
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
                        ),
                      ),
                      Text(
                        '${(_opacity * 100).round()}%',
                        style: const TextStyle(color: Colors.white70, fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
