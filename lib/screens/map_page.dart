import 'dart:async';
import 'dart:convert';
import 'dart:math' show pi, min, max, cos, sqrt, pow;
import 'dart:ui' as ui;
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
import '../providers/arcgis_export_tile_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/web_db.dart';
import '../services/connectivity_service.dart';
import '../services/geo_service.dart';
import '../services/groupe_service.dart';
import '../services/premium_service.dart';
import '../services/territoire_service.dart';
import 'aide_page.dart';
import '../widgets/hotspot_detail_sheet.dart';
import '../widgets/map_controls.dart';
import '../widgets/scale_bar.dart';
import 'about_page.dart';
import 'premium_page.dart';
import 'chat_page.dart';
import 'login_page.dart';
import 'meteo_page.dart';
import 'navigation_page.dart';
import 'territoire_download_page.dart';
import 'suivis_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Types d'observation disponibles
// ─────────────────────────────────────────────────────────────────────────────
const _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

const _typesObservation = [
  ('', 'Frottage'),
  ('💧', 'Souille'),
  ('👣', 'Traces'),
  ('📷', 'Caméra'),
  ('💩', 'Crottes'),
  ('🌿', 'Cache'),
  ('🍃', 'Broutage'),
  ('', 'Orignal'),
  ('', 'Camion'),
  ('', 'Saline'),
  ('', 'Chalet'),
];

// ─────────────────────────────────────────────────────────────────────────────
// MapPage
// ─────────────────────────────────────────────────────────────────────────────
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _opacity = 0.7;

  // ── Carte ──
  final MapController _mapController = MapController();
  double _mapZoom = 13.0;
  double _mapLat = 48.2917;
  bool _satellite = false;
  bool _showLayerPanel = false;
  bool _showTerresPrivees = false;

  // ── GPS / vent ──
  LatLng _currentPosition = const LatLng(48.2917, -71.322);
  bool _hasGpsPosition = false;
  bool _loading = false;
  bool _followingLocation = true; // false dès que l'utilisateur pan manuellement

  // ── Chat non lu ──
  int _unreadMessages = 0;
  StreamSubscription? _chatSub;
  Timestamp? _lastSeenMsgTs;
  bool _chatInitialized = false;
  double? _windDeg;
  double? _windSpeed;
  bool _windCached = false;
  StreamSubscription<Position>? _positionStream;
  Timer? _locationTimer;
  DateTime? _lastStreamUpdate;

  // ── Polygones écoforestiers ──
  List<Polygon> _polygonsCache = [];
  List<Map<String, dynamic>> _polygonLabels = [];

  // ── Cadastre (terres privées) ──
  List<List<LatLng>> _cadastreRings = [];
  List<String> _cadastreNoLots = [];
  int? _selectedCadastreLot;
  bool _downloadingLotTerritoire = false;
  Set<String> _downloadedLotNoms = {};

  // ── Hotspots ──
  bool _showHotspots = false;
  List<LatLng> _hotspots = [];
  List<HotspotInfo> _hotspotInfos = [];
  List<HotspotInfo> _rawHotspots = [];
  Timer? _hotspotDebounce;

  // ── Carte écoforestière ──
  double _ecoOpacity = 0.7;

  // ── Parcours ──
  bool _showParcours = false;
  bool _parcoursBlocked = false;
  late AnimationController _layersGlowCtrl;
  late Animation<double> _layersGlowAnim;
  bool _loadingParcours = false;
  List<LatLng> _parcours = [];
  double _distanceParcours = 2.0;
  double _parcoursScore = 0;

  // ── Points épinglés ──
  List<Map<String, dynamic>> _pinnedPoints = [];
  List<Map<String, dynamic>> _groupePins = [];
  StreamSubscription? _groupePinsSub;
  LatLng? _coordPreview;

  // ── Affût (pinch points) ──
  bool _showPinchPoints = false;
  bool _loadingPinch = false;
  List<Map<String, dynamic>> _pinchPoints = [];

  // ── Salines ──
  bool _showSalines = false;
  bool _loadingSalines = false;
  List<Map<String, dynamic>> _salines = [];

  // ── Tracé GPS ──
  bool _recording = false;
  List<LatLng> _trackPoints = [];
  final List<({String nom, DateTime date, List<LatLng> points})> _savedTracks = [];
  final List<String?> _savedTrackIds = [];

  // ── Observations terrain ──
  List<Map<String, dynamic>> _observations = [];
  int? _newObsIdx;
  OverlayEntry? _toastEntry;

  // ── Groupe ──
  List<Map<String, dynamic>> _obsGroupe = [];
  List<Map<String, dynamic>> _tracesGroupe = [];
  StreamSubscription? _obsGroupeSub;
  StreamSubscription? _tracesGroupeSub;
  String? _groupeId;
  String? _monNom;
  bool _groupeActif = false;
  bool _partagePosition = false;
  bool _obsPartagees = false;
  bool _tracesPartages = false;
  List<MembreGroupe> _membres = [];
  StreamSubscription<List<MembreGroupe>>? _groupeStream;
  final Set<String> _chasseursMasques = {};

  // ── UI panels ──
  bool _showActionPanel = false;
  bool _showNavPanel = false;

  // ── Infra cache pour refresh silencieux ──
  List<List<double>> _pinchInfraCache = [];
  List<List<double>> _salineInfraCache = [];
  Timer? _pinchDebounce;
  Timer? _salineDebounce;

  // ── Connectivité ──
  bool _isOnline = true;
  bool _showOfflineBanner = true;
  bool _showDownloadTip = true;
  StreamSubscription<bool>? _connectivitySub;

  // ─────────────────────────────────────────────────────────────────────────
  // Cycle de vie
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _layersGlowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _layersGlowAnim = Tween<double>(begin: 0, end: 1).animate(_layersGlowCtrl);
    _isOnline = ConnectivityService.isOnline;
    _connectivitySub = ConnectivityService.onStatusChange.listen((online) {
      if (mounted) setState(() { _isOnline = online; if (!online) _showOfflineBanner = true; });
      if (online) {
        _fetchWind();
        final uid = AuthService.uid;
        if (uid != null) _syncPendingObservations(uid);
      }
    });
    _initLocation();
    _fetchWind();
    PremiumService.load();
    Future.delayed(const Duration(seconds: 1), _reloadTerritoire);
    _loadObservations();
    _loadTracks();
    _loadGroupePrefs();
    _loadPins();
    requestPersistentStorage();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Le foreground service garde le processus en vie — le timer continue même écran fermé
  }

  void _restartAndroidTimer() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final last = _lastStreamUpdate;
      if (last != null && DateTime.now().difference(last).inSeconds < 2) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        if (!mounted) return;
        final p = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _currentPosition = p;
          _hasGpsPosition = true;
          if (_recording) _trackPoints.add(p);
          if (_showHotspots) _hotspots = _computeHotspots();
        });
        if (_followingLocation || _recording) _mapController.move(p, _mapZoom);
        if (_groupeActif && _partagePosition && _groupeId != null && _monNom != null) {
          GroupeService.publierPosition(groupeId: _groupeId!, nom: _monNom!, position: p);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _locationTimer?.cancel();
    _chatSub?.cancel();
    _groupeStream?.cancel();
    _obsGroupeSub?.cancel();
    _tracesGroupeSub?.cancel();
    _groupePinsSub?.cancel();
    _hotspotDebounce?.cancel();
    _pinchDebounce?.cancel();
    _salineDebounce?.cancel();
    _connectivitySub?.cancel();
    if (_groupeActif && _groupeId != null && _monNom != null) {
      GroupeService.quitter(_groupeId!, _monNom!);
    }
    _layersGlowCtrl.dispose();
    _toastEntry?.remove();
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
        setState(() { _currentPosition = gpsPos; _hasGpsPosition = true; });
        if (_followingLocation) _mapController.move(gpsPos, 13);
        await _fetchWind();
      }

      void handlePos(double lat, double lon) {
        if (!mounted) return;
        final p = LatLng(lat, lon);
        setState(() {
          _currentPosition = p;
          _hasGpsPosition = true;
          if (_recording) _trackPoints.add(p);
          if (_showHotspots) _hotspots = _computeHotspots();
        });
        if (_followingLocation || _recording) {
          _mapController.move(p, _mapZoom);
        }
        if (_groupeActif && _partagePosition && _groupeId != null && _monNom != null) {
          GroupeService.publierPosition(groupeId: _groupeId!, nom: _monNom!, position: p);
        }
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _positionStream = Geolocator.getPositionStream(
          locationSettings: AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 3,
            activityType: ActivityType.fitness,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          ),
        ).listen((position) => handlePos(position.latitude, position.longitude));
      } else {
        await Permission.notification.request();
        _positionStream = Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 3,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'OrignalScan',
              notificationText: 'Suivi GPS actif',
              enableWakeLock: true,
            ),
          ),
        ).listen((position) {
          _lastStreamUpdate = DateTime.now();
          handlePos(position.latitude, position.longitude);
        });
        // Timer fallback toutes les 2s si le stream ne répond pas
        _locationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
          final last = _lastStreamUpdate;
          if (last != null && DateTime.now().difference(last).inSeconds < 2) return;
          try {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
            );
            handlePos(pos.latitude, pos.longitude);
          } catch (_) {}
        });
      }
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
            _snackAvecReglages('Active la localisation dans les réglages');
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
          _snackAvecReglages('Permission de localisation refusée');
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
          _followingLocation = true;
        });
        _mapController.move(_currentPosition, 13);
        await _fetchWind();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _snackAvecReglages('GPS non disponible — vérifie les réglages');
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
      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final deg = data['current']['wind_direction_10m']?.toDouble();
        final speed = data['current']['wind_speed_10m']?.toDouble();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('wind_deg', deg ?? 0);
        await prefs.setDouble('wind_speed', speed ?? 0);
        await prefs.setInt('wind_ts', DateTime.now().millisecondsSinceEpoch);
        if (mounted) setState(() {
          _windDeg = deg;
          _windSpeed = speed;
          _windCached = false;
        });
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final deg = prefs.getDouble('wind_deg');
      final speed = prefs.getDouble('wind_speed');
      if (deg != null && mounted) {
        setState(() {
          _windDeg = deg;
          _windSpeed = speed;
          _windCached = true;
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Territoire écoforestier
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _reloadTerritoire() async {
    final list = await TerritoireService.listTerritoires();
    if (mounted) setState(() => _downloadedLotNoms = list.map((t) => t['id'] as String).toSet());
    if (!mounted) return;
    if (list.isEmpty) {
      geoJson = {'type': 'FeatureCollection', 'features': []};
      setState(() { _polygonsCache = []; _polygonLabels = []; });
      return;
    }
    // Charger seulement la carte active (ou la première si aucune active)
    var activeId = await TerritoireService.getActiveTerritoire();
    final ids = list.map((t) => t['id'] as String).toSet();
    if (activeId == null || !ids.contains(activeId)) {
      activeId = list.first['id'] as String;
      await TerritoireService.setActiveTerritoire(activeId);
    }
    final allFeatures = <dynamic>[];
    final data = await TerritoireService.loadTerritoire(activeId);
    if (data != null) allFeatures.addAll(data['features'] as List);
    geoJson = {'type': 'FeatureCollection', 'features': allFeatures};
    final all = await compute(buildAllGeoDataIsolate, geoJson);
    if (!mounted) return;
    final polys = all['polys'] as List<Polygon>;
    final labels = (all['labels'] as List).cast<Map<String, dynamic>>();
    final rawHS = (all['hotspots'] as List).cast<Map<String, dynamic>>();
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

  Future<void> _fetchCadastre() async {
    if (!_showTerresPrivees || _mapZoom < 14.1) return;
    try {
      final b = _mapController.camera.visibleBounds;
      final url = Uri.parse(
        'https://geo.environnement.gouv.qc.ca/donnees/rest/services/Reference'
        '/Cadastre_allege/MapServer/0/query'
        '?geometry=${b.southWest.longitude},${b.southWest.latitude}'
        ',${b.northEast.longitude},${b.northEast.latitude}'
        '&geometryType=esriGeometryEnvelope&inSR=4326&outSR=4326'
        '&outFields=NO_LOT&returnGeometry=true&f=geojson',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (resp.statusCode != 200) {
        debugPrint('Cadastre HTTP ${resp.statusCode}');
        return;
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final features = data['features'] as List? ?? [];
      debugPrint('Cadastre: ${features.length} lots');
      final rings = <List<LatLng>>[];
      final noLots = <String>[];
      for (final f in features) {
        try {
          final props = f['properties'] as Map<String, dynamic>? ?? {};
          final noLot = props['NO_LOT']?.toString() ?? '';
          final geom = f['geometry'] as Map<String, dynamic>;
          final type = geom['type'] as String;
          final rawCoords = geom['coordinates'] as List;
          final outerRings = type == 'MultiPolygon'
              ? rawCoords.expand<dynamic>((r) => r as List)
              : rawCoords;
          for (final ring in outerRings) {
            final pts = (ring as List)
                .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
                .toList();
            if (pts.length >= 3) {
              rings.add(pts);
              noLots.add(noLot);
            }
          }
        } catch (e) {
          debugPrint('Cadastre ring error: $e');
        }
      }
      if (mounted && _showTerresPrivees && _mapZoom >= 14.1) {
        setState(() {
          _cadastreRings = rings;
          _cadastreNoLots = noLots;
          _selectedCadastreLot = null;
        });
      }
    } catch (e) {
      debugPrint('Cadastre error: $e');
    }
  }

  bool _pointInPolygon(LatLng pt, List<LatLng> poly) {
    bool inside = false;
    int j = poly.length - 1;
    for (int i = 0; i < poly.length; i++) {
      if ((poly[i].longitude > pt.longitude) != (poly[j].longitude > pt.longitude) &&
          pt.latitude <
              (poly[j].latitude - poly[i].latitude) *
                      (pt.longitude - poly[i].longitude) /
                      (poly[j].longitude - poly[i].longitude) +
                  poly[i].latitude) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  void _handleMapTap(LatLng point) {
    if (_showActionPanel || _showNavPanel || _showLayerPanel) {
      setState(() {
        _showActionPanel = false;
        _showNavPanel = false;
        _showLayerPanel = false;
      });
      return;
    }
    if (!_showTerresPrivees || _cadastreRings.isEmpty) return;
    for (int i = 0; i < _cadastreRings.length; i++) {
      if (_pointInPolygon(point, _cadastreRings[i])) {
        setState(() =>
            _selectedCadastreLot = _selectedCadastreLot == i ? null : i);
        return;
      }
    }
    setState(() => _selectedCadastreLot = null);
  }

  Future<void> _downloadLotTerritoire() async {
    final idx = _selectedCadastreLot;
    if (idx == null || idx >= _cadastreRings.length) return;
    final pts = _cadastreRings[idx];
    final noLot = idx < _cadastreNoLots.length ? _cadastreNoLots[idx] : 'inconnu';
    final lats = pts.map((p) => p.latitude);
    final lons = pts.map((p) => p.longitude);
    setState(() => _downloadingLotTerritoire = true);
    try {
      await TerritoireService.downloadTerritoire(
        nom: 'Lot $noLot',
        minLat: lats.reduce(min),
        minLon: lons.reduce(min),
        maxLat: lats.reduce(max),
        maxLon: lons.reduce(max),
      );
      await _reloadTerritoire();
      if (mounted) _snack('Carte éco — Lot $noLot téléchargée');
    } catch (e) {
      if (mounted) _snack('Erreur: $e', error: true);
    } finally {
      if (mounted) setState(() => _downloadingLotTerritoire = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  int _observationBoost(LatLng pos) {
    const weights = {
      'Orignal': 5, 'Frottage': 4, 'Souille': 4,
      'Traces': 3, 'Broutage': 3, 'Crottes': 2, 'Saline': 1,
    };
    int boost = 0;
    for (final obs in _observations) {
      final obsPos = obs['pos'] as LatLng;
      final note = obs['note'] as String;
      final dist = const Distance().as(LengthUnit.Meter, pos, obsPos);
      if (dist > 500) continue;
      for (final entry in weights.entries) {
        if (note.contains(entry.key)) {
          boost += dist < 200 ? entry.value : (entry.value * 0.5).round();
          break;
        }
      }
    }
    return boost.clamp(0, 5);
  }

  // Hotspots
  // ─────────────────────────────────────────────────────────────────────────
  List<LatLng> _computeHotspots({List<List<double>> infraPoints = const []}) {
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
        ..sort((a, b) => (b.score + _observationBoost(b.position))
            .compareTo(a.score + _observationBoost(a.position)));
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
          ..sort((a, b) => (b.score + _observationBoost(b.position))
              .compareTo(a.score + _observationBoost(a.position)));
      } catch (_) {}
    }

    final List<LatLng> result = [];
    final List<HotspotInfo> infos = [];
    for (final info in candidates) {
      final tooClose = result.any(
        (e) => const Distance().as(LengthUnit.Meter, e, info.position) < 200,
      );
      if (tooClose) continue;
      if (infraPoints.isNotEmpty) {
        final lat = info.position.latitude;
        final lon = info.position.longitude;
        final cosC = cos(lat * pi / 180);
        final nearInfra = infraPoints.any((p) =>
            sqrt(pow((p[0] - lat) * 111000, 2) +
                 pow((p[1] - lon) * 111000 * cosC, 2)) < 100);
        if (nearInfra) continue;
      }
      result.add(info.position);
      infos.add(info);
      if (result.length >= _maxResults()) break;
    }
    _hotspotInfos = infos;
    return result;
  }

  Future<void> _toggleHotspots({bool forceRefresh = false}) async {
    if (!_requirePremium()) return;
    if (_showHotspots && !forceRefresh) {
      setState(() { _showHotspots = false; _hotspots = []; });
      return;
    }
    if (!_requireEcoMap()) return;
    final center = _mapController.camera.center;
    final radiusM = _visibleRadiusM(minM: 2000);
    final infraPoints = await _fetchOsmInfra(center, radiusM);
    final spots = _computeHotspots(infraPoints: infraPoints);
    setState(() { _hotspots = spots; _showHotspots = true; });
    _snack('Zoomer l\'entièreté de votre territoire à analyser');
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
      final blockReason = (result['blockReason'] as String?) ?? '';
      final points = rawList.map((p) {
        final coords = p as List;
        return LatLng((coords[0] as num).toDouble(), (coords[1] as num).toDouble());
      }).toList();

      if (!mounted) return;
      setState(() {
        _parcours = points;
        _showParcours = true;
        _parcoursScore = scorePct;
        _parcoursBlocked = points.length < 5;
        _loadingParcours = false;
      });
      if (points.length < 5) {
        final msg = blockReason == 'eau'
            ? 'Parcours bloqué par un cours d\'eau — essaie une autre position de départ'
            : blockReason == 'terrain'
                ? 'Parcours bloqué par le terrain — essaie une zone avec plus de forêt'
                : 'Parcours limité — télécharge une carte écoforestière plus large';
        _snack(msg, error: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingParcours = false);
      _snack('Télécharge d\'abord une carte écoforestière via "Carte éco"', error: true);
    }
  }

  // Rayon visible en mètres depuis les bounds de la carte, avec un minimum garanti
  double _visibleRadiusM({double minM = 2000}) {
    try {
      final b = _mapController.camera.visibleBounds;
      final center = _mapController.camera.center;
      final latM = (b.northEast.latitude - b.southWest.latitude) / 2 * 111000;
      final lonM = (b.northEast.longitude - b.southWest.longitude) / 2 *
          111000 * cos(center.latitude * pi / 180);
      return max(sqrt(latM * latM + lonM * lonM), minM);
    } catch (_) {
      return minM;
    }
  }

  // 1 résultat max par cellule de 1000 pieds × 1000 pieds (≈305m)
  int _maxResults() => 5;

  // ─────────────────────────────────────────────────────────────────────────
  // Affût (pinch points)
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<List<double>>> _fetchOsmInfra(LatLng center, double radiusM) async {
    final r = radiusM.round();
    final query =
        '[out:json][timeout:25];'
        '('
        'way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|service|track|path|footway|cycleway|bridleway)\$"](around:$r,${center.latitude},${center.longitude});'
        'way["building"](around:$r,${center.latitude},${center.longitude});'
        'node["building"](around:$r,${center.latitude},${center.longitude});'
        ');'
        'out geom;';
    try {
      final resp = await http
          .post(Uri.parse('https://overpass-api.de/api/interpreter'), body: query)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final elements = data['elements'] as List;
      final points = <List<double>>[];
      for (final el in elements) {
        if (el['type'] == 'node') {
          points.add([(el['lat'] as num).toDouble(), (el['lon'] as num).toDouble()]);
        } else if (el['type'] == 'way') {
          // Géométrie complète de la route/chemin — tous les nœuds intermédiaires
          final geom = el['geometry'] as List?;
          if (geom != null) {
            for (final node in geom) {
              final nLat = (node['lat'] as num?)?.toDouble();
              final nLon = (node['lon'] as num?)?.toDouble();
              if (nLat != null && nLon != null) points.add([nLat, nLon]);
            }
          }
        }
      }
      return points;
    } catch (_) {
      return [];
    }
  }

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
      final radiusM = _visibleRadiusM(minM: 1500);
      final infraPoints = await _fetchOsmInfra(center, radiusM);
      _pinchInfraCache = infraPoints;
      final result = await compute(findPinchPointsIsolate, {
        'lat': center.latitude,
        'lon': center.longitude,
        'radiusM': radiusM,
        'geoJson': geoJson,
        'maxResults': 5,
        'infraPoints': infraPoints,
      });
      if (!mounted) return;
      setState(() {
        _pinchPoints = result.take(5).toList();
        _showPinchPoints = true;
        _loadingPinch = false;
      });
      _snack('Zoomer l\'entièreté de votre territoire à analyser');
    } catch (_) {
      if (mounted) setState(() => _loadingPinch = false);
    }
  }

  Future<void> _toggleSalines() async {
    if (!_requirePremium()) return;
    if (_showSalines) {
      setState(() { _showSalines = false; _salines = []; });
      return;
    }
    if (!_requireEcoMap()) return;
    setState(() => _loadingSalines = true);
    try {
      final center = _mapController.camera.center;
      final radiusM = _visibleRadiusM(minM: 2000);
      final infraPoints = await _fetchOsmInfra(center, radiusM);
      _salineInfraCache = infraPoints;
      final result = await compute(findSalinesIsolate, {
        'lat': center.latitude,
        'lon': center.longitude,
        'radiusM': radiusM,
        'geoJson': geoJson,
        'infraPoints': infraPoints,
        'maxResults': 5,
      });
      if (!mounted) return;
      setState(() {
        _salines = result.take(5).toList();
        _showSalines = true;
        _loadingSalines = false;
      });
      _snack('Zoomer l\'entièreté de votre territoire à analyser');
    } catch (_) {
      if (mounted) setState(() => _loadingSalines = false);
    }
  }

  Future<void> _refreshPinchPoints() async {
    if (!_showPinchPoints) return;
    try {
      final center = _mapController.camera.center;
      final radiusM = _visibleRadiusM(minM: 1500);
      final result = await compute(findPinchPointsIsolate, {
        'lat': center.latitude,
        'lon': center.longitude,
        'radiusM': radiusM,
        'geoJson': geoJson,
        'maxResults': 5,
        'infraPoints': _pinchInfraCache,
      });
      if (!mounted || !_showPinchPoints) return;
      setState(() => _pinchPoints = result.take(5).toList());
    } catch (_) {}
  }

  Future<void> _refreshSalines() async {
    if (!_showSalines) return;
    try {
      final center = _mapController.camera.center;
      final radiusM = _visibleRadiusM(minM: 2000);
      final result = await compute(findSalinesIsolate, {
        'lat': center.latitude,
        'lon': center.longitude,
        'radiusM': radiusM,
        'geoJson': geoJson,
        'infraPoints': _salineInfraCache,
        'maxResults': 5,
      });
      if (!mounted || !_showSalines) return;
      setState(() => _salines = result.take(5).toList());
    } catch (_) {}
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
      final now = DateTime.now();
      final defaultNom = 'Suivi ${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')} '
          '${now.hour.toString().padLeft(2,'0')}h${now.minute.toString().padLeft(2,'0')}';
      final ctrl = TextEditingController(text: defaultNom);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Nommer le suivi',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              hintText: 'Nom du suivi',
              hintStyle: const TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                final nom = ctrl.text.trim().isEmpty ? defaultNom : ctrl.text.trim();
                final newIdx = _savedTracks.length;
                setState(() {
                  _savedTracks.add((nom: nom, date: now, points: pts));
                  _savedTrackIds.add(null);
                });
                _saveTrack(newIdx);
                _snack('Suivi "$nom" sauvegardé');
              },
              child: const Text('Sauvegarder',
                  style: TextStyle(color: Color(0xFFFF6B35))),
            ),
          ],
        ),
      );
    } else {
      setState(() { _recording = true; _trackPoints = []; _followingLocation = true; });
      _snack('Enregistrement démarré — bouge-toi!');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Observations
  // ─────────────────────────────────────────────────────────────────────────
  // ── Cache local observations ───────────────────────────────────────────────

  String _obsCacheKey(String uid) => 'obs_cache_$uid';

  Future<void> _persistObsCache(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _observations.map((o) {
      final pos = o['pos'] as LatLng;
      return {
        'id': o['id'],
        'lat': pos.latitude,
        'lon': pos.longitude,
        'note': o['note'],
        'time': (o['time'] as DateTime).toIso8601String(),
        if (o['pending'] == true) 'pending': true,
      };
    }).toList();
    await prefs.setString(_obsCacheKey(uid), jsonEncode(list));
  }

  Future<void> _loadObsFromCache(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_obsCacheKey(uid));
    if (raw == null || !mounted) return;
    try {
      final list = (jsonDecode(raw) as List).map<Map<String, dynamic>>((m) => {
        'id': m['id'],
        'pos': LatLng((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble()),
        'note': m['note'] as String,
        'time': DateTime.parse(m['time'] as String),
        if (m['pending'] == true) 'pending': true,
      }).toList();
      setState(() => _observations = list);
    } catch (_) {}
  }

  Future<void> _syncPendingObservations(String uid) async {
    final pending = _observations.where((o) => o['pending'] == true).toList();
    for (final obs in pending) {
      try {
        final pos = obs['pos'] as LatLng;
        final ref = await FirebaseFirestore.instance
            .collection('users').doc(uid).collection('observations')
            .add({
          'lat': pos.latitude, 'lon': pos.longitude,
          'note': obs['note'],
          'time': Timestamp.fromDate(obs['time'] as DateTime),
        });
        if (mounted) setState(() { obs['id'] = ref.id; obs.remove('pending'); });
      } catch (_) {}
    }
    if (pending.isNotEmpty) await _persistObsCache(uid);
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pinned_points') ?? '[]';
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _pinnedPoints = list);
    } catch (_) {}
  }

  Future<void> _savePins() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pinned_points', jsonEncode(_pinnedPoints));
  }

  bool _isPinned(LatLng pos) => _pinnedPoints.any((p) =>
      (p['lat'] as double).toStringAsFixed(5) == pos.latitude.toStringAsFixed(5) &&
      (p['lon'] as double).toStringAsFixed(5) == pos.longitude.toStringAsFixed(5));

  void _togglePin(String type, LatLng pos) {
    final pinned = _isPinned(pos);
    setState(() {
      if (pinned) {
        _pinnedPoints.removeWhere((p) =>
            (p['lat'] as double).toStringAsFixed(5) == pos.latitude.toStringAsFixed(5) &&
            (p['lon'] as double).toStringAsFixed(5) == pos.longitude.toStringAsFixed(5));
      } else {
        _pinnedPoints.add({'type': type, 'lat': pos.latitude, 'lon': pos.longitude});
      }
    });
    _savePins();
    if (_groupeActif && _groupeId != null && _monNom != null) {
      if (pinned) {
        GroupeService.supprimerEpingle(
            groupeId: _groupeId!, nom: _monNom!,
            lat: pos.latitude, lon: pos.longitude);
      } else {
        GroupeService.publierEpingle(
            groupeId: _groupeId!, nom: _monNom!,
            type: type, lat: pos.latitude, lon: pos.longitude);
      }
    }
  }

  LatLng? _parseCoords(String input) {
    input = input.trim();
    // Format décimal: "46.8123, -71.2456" ou "46.8123 -71.2456"
    final dec = RegExp(r'^(-?\d+\.?\d*)[,\s]+(-?\d+\.?\d*)$');
    final dm = dec.firstMatch(input);
    if (dm != null) {
      final lat = double.tryParse(dm.group(1)!);
      final lon = double.tryParse(dm.group(2)!);
      if (lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180) {
        return LatLng(lat, lon);
      }
    }
    // Format DMS: "46°48'44"N 71°14'44"W" ou "46° 48' 44" N, 71° 14' 44" W"
    final dms = RegExp(
      r'(\d+)\s*[°]\s*(\d+)\s*[\'′]\s*(\d+(?:\.\d+)?)\s*[\"″]?\s*([NS])[,\s]+(\d+)\s*[°]\s*(\d+)\s*[\'′]\s*(\d+(?:\.\d+)?)\s*[\"″]?\s*([EW])',
      caseSensitive: false,
    );
    final mm = dms.firstMatch(input);
    if (mm != null) {
      double toDec(String d, String m, String s) =>
          double.parse(d) + double.parse(m) / 60 + double.parse(s) / 3600;
      double lat = toDec(mm.group(1)!, mm.group(2)!, mm.group(3)!);
      double lon = toDec(mm.group(5)!, mm.group(6)!, mm.group(7)!);
      if (mm.group(4)!.toUpperCase() == 'S') lat = -lat;
      if (mm.group(8)!.toUpperCase() == 'W') lon = -lon;
      return LatLng(lat, lon);
    }
    return null;
  }

  void _showCoordsSearch() {
    final ctrl = TextEditingController();
    String? erreur;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: const Text('Aller à des coordonnées',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '46.8123, -71.2456',
                  hintStyle: const TextStyle(color: Colors.white38),
                  errorText: erreur,
                  enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFF6B35))),
                  errorBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.redAccent)),
                  focusedErrorBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.redAccent)),
                ),
                onSubmitted: (_) => _submitCoords(ctrl.text, ctx, setS, (e) => erreur = e),
              ),
              const SizedBox(height: 8),
              const Text(
                'Formats acceptés :\n46.8123, -71.2456\n46°48\'44"N 71°14\'44"W',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35), foregroundColor: Colors.white),
              onPressed: () => _submitCoords(ctrl.text, ctx, setS, (e) => erreur = e),
              child: const Text('Aller'),
            ),
          ],
        ),
      ),
    );
  }

  void _submitCoords(String text, BuildContext ctx, StateSetter setS, void Function(String?) setErr) {
    final pos = _parseCoords(text);
    if (pos == null) {
      setS(() => setErr('Format invalide'));
      return;
    }
    Navigator.pop(ctx);
    _mapController.move(pos, _mapZoom < 14 ? 15 : _mapZoom);
    setState(() => _coordPreview = pos);
    // Afficher dialog de sauvegarde après déplacement
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _showCoordPreviewDialog(pos);
    });
  }

  void _showCoordPreviewDialog(LatLng pos) {
    final nomCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(children: [
          Expanded(child: _coordsWidget(pos)),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 20),
            onPressed: () { Navigator.pop(ctx); setState(() => _coordPreview = null); },
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
        ]),
        content: TextField(
          controller: nomCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nom du favori (optionnel)',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6B35))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(ctx); setState(() => _coordPreview = null); },
            child: const Text('Fermer', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35), foregroundColor: Colors.white),
            icon: const Icon(Icons.star_rounded, size: 16),
            label: const Text('Sauvegarder'),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _coordPreview = null;
                final nom = nomCtrl.text.trim();
                _pinnedPoints.add({
                  'type': 'coordonnees',
                  'lat': pos.latitude,
                  'lon': pos.longitude,
                  if (nom.isNotEmpty) 'nom': nom,
                });
              });
              _savePins();
              if (_groupeActif && _groupeId != null && _monNom != null) {
                GroupeService.publierEpingle(
                    groupeId: _groupeId!, nom: _monNom!,
                    type: 'coordonnees', lat: pos.latitude, lon: pos.longitude);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadObservations() async {
    final uid = AuthService.uid;
    if (uid == null) return;
    // Charge le cache local immédiatement (fonctionne hors ligne)
    await _loadObsFromCache(uid);
    // Sync Firestore si en ligne
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('observations')
          .orderBy('time', descending: false)
          .get();
      if (!mounted) return;
      final remote = snap.docs.map<Map<String, dynamic>>((doc) {
        final d = doc.data();
        return {
          'id': doc.id,
          'pos': LatLng((d['lat'] as num).toDouble(), (d['lon'] as num).toDouble()),
          'note': d['note'] as String,
          'time': (d['time'] as Timestamp).toDate(),
        };
      }).toList();
      // Fusionne : garde les pending locaux non encore synchros
      final pendingLocal = _observations.where((o) => o['pending'] == true).toList();
      setState(() => _observations = [...remote, ...pendingLocal]);
      await _persistObsCache(uid);
    } catch (_) {}
  }

  Future<void> _saveObservation(Map<String, dynamic> obs) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    // Sauvegarde locale immédiate
    await _persistObsCache(uid);
    // Sync Firestore
    try {
      final pos = obs['pos'] as LatLng;
      final ref = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('observations')
          .add({
        'lat': pos.latitude, 'lon': pos.longitude,
        'note': obs['note'],
        'time': Timestamp.fromDate(obs['time'] as DateTime),
      });
      if (mounted) setState(() { obs['id'] = ref.id; obs.remove('pending'); });
      await _persistObsCache(uid);
    } catch (_) {
      // Hors ligne — marque comme pending pour sync ultérieure
      if (mounted) setState(() => obs['pending'] = true);
      await _persistObsCache(uid);
    }
  }

  Future<void> _deleteObservation(int idx) async {
    final obs = _observations[idx];
    final id = obs['id'] as String?;
    setState(() => _observations.removeAt(idx));
    final uid = AuthService.uid;
    if (uid != null) await _persistObsCache(uid);
    if (id == null || obs['pending'] == true) return;
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(uid!).collection('observations')
          .doc(id).delete();
    } catch (_) {}
  }

  // ── Cache local tracés ────────────────────────────────────────────────────

  String _trackCacheKey(String uid) => 'tracks_cache_$uid';

  Future<void> _persistTrackCache(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List.generate(_savedTracks.length, (i) => {
      'id': _savedTrackIds.length > i ? _savedTrackIds[i] : null,
      'nom': _savedTracks[i].nom,
      'date': _savedTracks[i].date.toIso8601String(),
      'points': _savedTracks[i].points
          .map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
    });
    await prefs.setString(_trackCacheKey(uid), jsonEncode(list));
  }

  Future<void> _loadTracksFromCache(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_trackCacheKey(uid));
    if (raw == null || !mounted) return;
    try {
      final list = jsonDecode(raw) as List;
      setState(() {
        for (final m in list) {
          _savedTracks.add((
            nom: (m['nom'] as String?) ?? '',
            date: DateTime.parse(m['date'] as String),
            points: (m['points'] as List).map((p) =>
                LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble())).toList(),
          ));
          _savedTrackIds.add(m['id'] as String?);
        }
      });
    } catch (_) {}
  }

  Future<void> _loadTracks() async {
    final uid = AuthService.uid;
    if (uid == null) return;
    await _loadTracksFromCache(uid);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('tracks')
          .orderBy('date', descending: false)
          .get();
      if (!mounted) return;
      final tracks = <({String nom, DateTime date, List<LatLng> points})>[];
      final ids = <String?>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        tracks.add((
          nom: (d['nom'] as String?) ?? '',
          date: (d['date'] as Timestamp).toDate(),
          points: (d['points'] as List).map((p) =>
              LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble())).toList(),
        ));
        ids.add(doc.id);
      }
      setState(() {
        _savedTracks.clear();
        _savedTrackIds.clear();
        _savedTracks.addAll(tracks);
        _savedTrackIds.addAll(ids);
      });
      await _persistTrackCache(uid);
    } catch (_) {}
  }

  Future<void> _saveTrack(int idx) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    await _persistTrackCache(uid);
    try {
      final track = _savedTracks[idx];
      final ref = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('tracks')
          .add({
        'nom': track.nom,
        'date': Timestamp.fromDate(track.date),
        'points': track.points
            .map((p) => {'lat': p.latitude, 'lon': p.longitude})
            .toList(),
      });
      if (mounted) setState(() => _savedTrackIds[idx] = ref.id);
      await _persistTrackCache(uid);
    } catch (_) {}
  }

  Future<void> _renameTrack(int idx, String newNom) async {
    final old = _savedTracks[idx];
    setState(() => _savedTracks[idx] = (nom: newNom, date: old.date, points: old.points));
    final uid = AuthService.uid;
    if (uid == null) return;
    await _persistTrackCache(uid);
    final id = idx < _savedTrackIds.length ? _savedTrackIds[idx] : null;
    if (id == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('tracks')
          .doc(id).update({'nom': newNom});
    } catch (_) {}
  }

  Future<void> _deleteTrack(int idx) async {
    final id = idx < _savedTrackIds.length ? _savedTrackIds[idx] : null;
    setState(() {
      _savedTracks.removeAt(idx);
      if (idx < _savedTrackIds.length) _savedTrackIds.removeAt(idx);
    });
    final uid = AuthService.uid;
    if (uid != null) await _persistTrackCache(uid);
    if (id == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(uid!).collection('tracks')
          .doc(id).delete();
    } catch (_) {}
  }

  void _centerOnTrack(int idx) {
    if (idx >= _savedTracks.length) return;
    final pts = _savedTracks[idx].points;
    if (pts.isEmpty) return;
    final lats = pts.map((p) => p.latitude);
    final lngs = pts.map((p) => p.longitude);
    final centerLat = (lats.reduce(min) + lats.reduce(max)) / 2;
    final centerLng = (lngs.reduce(min) + lngs.reduce(max)) / 2;
    _mapController.move(LatLng(centerLat, centerLng), 14);
    setState(() => _followingLocation = false);
  }

  void _addObservation() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(0, 12, 0, MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 32, height: 3,
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Type d\'observation',
                    style: TextStyle(color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.55),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _typesObservation.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10, indent: 64),
                itemBuilder: (_, i) {
                  final t = _typesObservation[i];
                  return InkWell(
                    onTap: () {
                      final pos = _mapController.camera.center;
                      final obs = {
                        'pos': pos,
                        'note': '${t.$1} ${t.$2}',
                        'time': DateTime.now(),
                      };
                      final newIdx = _observations.length;
                      setState(() {
                        _observations.add(obs);
                        _newObsIdx = newIdx;
                      });
                      _saveObservation(obs);
                      Navigator.pop(context);
                      _snack('${t.$2} ajouté');
                      Future.delayed(const Duration(milliseconds: 800),
                          () { if (mounted) setState(() => _newObsIdx = null); });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(children: [
                        SizedBox(width: 36, height: 36, child: obsIcon('${t.$1} ${t.$2}', size: 36)),
                        const SizedBox(width: 16),
                        Text(t.$2, style: const TextStyle(color: Colors.white, fontSize: 15)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + MediaQuery.of(ctx).viewPadding.bottom),
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
                onPressed: () { Navigator.pop(context); _quitterGroupe(); },
                child: const Text('Quitter',
                    style: TextStyle(color: Color(0xFFFF6B35), fontSize: 13)),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 20),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const Divider(color: Colors.white12, height: 24),
            _groupeTile(Icons.chat_bubble_rounded, 'Clavardage du groupe',
                'Messages entre chasseurs', () {
              Navigator.pop(context);
              _markChatSeen(_groupeId!);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                        groupeId: _groupeId!, monNom: _monNom!),
                  ));
            }, badge: _unreadMessages),
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
            _groupeTile(
                _obsPartagees ? Icons.pin_drop_outlined : Icons.pin_drop_rounded,
                _obsPartagees ? 'Arrêter le partage obs.' : 'Partager mes observations',
                _obsPartagees ? 'Tes observations sont visibles' : 'Frottages, souilles, traces…',
                () { Navigator.pop(context); _partagerObservations(); }),
            _groupeTile(
                _tracesPartages ? Icons.route_outlined : Icons.route_rounded,
                _tracesPartages ? 'Arrêter le partage tracés' : 'Partager mes tracés',
                _tracesPartages ? 'Tes tracés sont visibles' : 'Tracés GPS du groupe',
                () { Navigator.pop(context); _partagerTraces(); }),
            if (_chasseursMasques.isNotEmpty)
              _groupeTile(
                Icons.visibility_rounded,
                'Réafficher tous les chasseurs',
                '${_chasseursMasques.length} chasseur(s) masqué(s)',
                () {
                  setState(() => _chasseursMasques.clear());
                  Navigator.pop(context);
                  _snack('Observations réaffichées');
                }),
          ],
        ),
      ),
    );
  }

  Future<void> _loadGroupePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('last_groupe_code');
    final nom = prefs.getString('last_groupe_nom');
    if (code != null && mounted) setState(() { _groupeId = code; _monNom = nom; });
  }

  void _rejoindreGroupe(String nom, String groupeId) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('last_groupe_code', groupeId);
      prefs.setString('last_groupe_nom', nom);
    });
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
    _groupePinsSub?.cancel();
    _groupePinsSub = GroupeService.ecouterEpingles(groupeId, nom).listen((pins) {
      if (mounted) setState(() => _groupePins = pins);
    });
    _loadLastSeenTs(groupeId);
    _startChatStream(groupeId);
    _snack('Groupe "$groupeId" rejoint');
  }

  void _startChatStream(String groupeId) {
    _chatSub?.cancel();
    _chatInitialized = false;
    _chatSub = FirebaseFirestore.instance
        .collection('groupes')
        .doc(groupeId)
        .collection('messages')
        .orderBy('ts', descending: false)
        .limitToLast(50)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      int count = 0;
      Map<String, dynamic>? latestNew;
      for (final doc in snap.docs) {
        final ts = doc['ts'] as Timestamp?;
        final nom = doc['nom'] as String?;
        if (ts == null || nom == _monNom) continue;
        final seen = _lastSeenMsgTs;
        if (seen == null || ts.millisecondsSinceEpoch > seen.millisecondsSinceEpoch) {
          count++;
          latestNew = doc.data() as Map<String, dynamic>;
        }
      }
      if (_chatInitialized && count > _unreadMessages && latestNew != null) {
        _showChatBanner(
          latestNew['nom'] as String? ?? '',
          latestNew['texte'] as String? ?? '',
        );
      }
      _chatInitialized = true;
      setState(() => _unreadMessages = count);
    });
  }

  Future<void> _loadLastSeenTs(String groupeId) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('chat_seen_$groupeId');
    if (ms != null && mounted) setState(() => _lastSeenMsgTs = Timestamp.fromMillisecondsSinceEpoch(ms));
  }

  Future<void> _markChatSeen(String groupeId) async {
    final now = Timestamp.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('chat_seen_$groupeId', now.millisecondsSinceEpoch);
    if (mounted) setState(() { _unreadMessages = 0; _lastSeenMsgTs = now; });
  }

  void _quitterGroupe() {
    _chatSub?.cancel();
    _groupeStream?.cancel();
    _obsGroupeSub?.cancel();
    _tracesGroupeSub?.cancel();
    _groupePinsSub?.cancel();
    if (_groupeId != null && _monNom != null) {
      GroupeService.quitter(_groupeId!, _monNom!);
    }
    setState(() {
      _groupeActif = false;
      _partagePosition = false;
      _obsPartagees = false;
      _tracesPartages = false;
      _membres = [];
      _obsGroupe = [];
      _tracesGroupe = [];
      _groupePins = [];
    });
    _snack('Groupe quitté', error: true);
  }

  Future<void> _partagerObservations() async {
    final db = FirebaseFirestore.instance;
    final col = db.collection('groupes').doc(_groupeId).collection('observations');
    if (_obsPartagees) {
      final snap = await col.where('nom', isEqualTo: _monNom).get();
      for (final doc in snap.docs) { await doc.reference.delete(); }
      setState(() => _obsPartagees = false);
      _snack('Observations retirées du groupe', error: true);
      return;
    }
    if (_observations.isEmpty) {
      _snack('Aucune observation à partager', error: true);
      return;
    }
    for (final obs in _observations) {
      final pos = obs['pos'] as LatLng;
      await col.add({
        'nom': _monNom,
        'note': obs['note'],
        'lat': pos.latitude,
        'lon': pos.longitude,
        'ts': FieldValue.serverTimestamp(),
      });
    }
    setState(() => _obsPartagees = true);
    _snack('${_observations.length} observation(s) partagée(s)');
  }

  Future<void> _partagerTraces() async {
    final db = FirebaseFirestore.instance;
    final col = db.collection('groupes').doc(_groupeId).collection('traces');
    if (_tracesPartages) {
      final snap = await col.where('nom', isEqualTo: _monNom).get();
      for (final doc in snap.docs) { await doc.reference.delete(); }
      setState(() => _tracesPartages = false);
      _snack('Tracés retirés du groupe', error: true);
      return;
    }
    if (_savedTracks.isEmpty) {
      _snack('Aucun tracé à partager', error: true);
      return;
    }
    for (final track in _savedTracks) {
      await col.add({
        'nom': _monNom,
        'points': track.points
            .map((p) => {'lat': p.latitude, 'lon': p.longitude})
            .toList(),
        'date': track.date.toIso8601String(),
        'ts': FieldValue.serverTimestamp(),
      });
    }
    setState(() => _tracesPartages = true);
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
          padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + MediaQuery.of(ctx).viewPadding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.route_rounded, color: Color(0xFF5A8A1E), size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Générer un parcours',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 20),
                  onPressed: () => Navigator.pop(ctx),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
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

  double _trackDistanceM(List<LatLng> pts) {
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i]; final b = pts[i + 1];
      final c = cos(a.latitude * pi / 180);
      total += sqrt(pow((b.latitude - a.latitude) * 111000, 2) +
                    pow((b.longitude - a.longitude) * 111000 * c, 2));
    }
    return total;
  }

  void _showTrackPopup(int idx) {
    final track = _savedTracks[idx];
    final d = track.date;
    final dateLabel =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}  '
        '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
    final distM = _trackDistanceM(track.points);
    final distStr = distM >= 1000
        ? '${(distM / 1000).toStringAsFixed(1)} km'
        : '${distM.round()} m';
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.route_rounded,
                    color: Color(0xFF4A90E2), size: 26),
              ),
              const SizedBox(height: 10),
              if (track.nom.isNotEmpty)
                Text(track.nom,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(dateLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              Text('$distStr · ${track.points.length} points',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    final ctrl = TextEditingController(text: track.nom);
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF1C1C1C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('Renommer', style: TextStyle(color: Colors.white, fontSize: 16)),
                        content: TextField(
                          controller: ctrl,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF2A2A2A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context),
                              child: const Text('Annuler', style: TextStyle(color: Colors.white38))),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              if (ctrl.text.trim().isNotEmpty) _renameTrack(idx, ctrl.text.trim());
                            },
                            child: const Text('OK', style: TextStyle(color: Color(0xFFFF6B35))),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white54),
                  label: const Text('Renommer', style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteTrack(idx);
                  },
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white38),
                  label: const Text('Supprimer', style: TextStyle(color: Colors.white38, fontSize: 13)),
                ),
              ),
            ],
          ),
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
    _snack('Télécharge d\'abord une carte écoforestière via le bouton Couches', error: true);
    _layersGlowCtrl.repeat(reverse: true);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _layersGlowCtrl.stop();
    });
    return false;
  }

  // Retourne true si premium, sinon affiche le dialog d'upgrade
  bool _requirePremium() {
    if (PremiumService.isPremium) return true;
    showDialog(
      context: context,
      builder: (_) => const PremiumPopup(),
    );
    return false;
  }

  void _showChatBanner(String nom, String texte) {
    if (!mounted) return;
    _toastEntry?.remove();
    _toastEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16, right: 16,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {
              _toastEntry?.remove();
              _toastEntry = null;
              if (_groupeId == null || _monNom == null) return;
              _markChatSeen(_groupeId!);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ChatPage(groupeId: _groupeId!, monNom: _monNom!),
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.6)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Row(children: [
                const Icon(Icons.chat_bubble_rounded, color: Color(0xFFFF6B35), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(nom, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    if (texte.isNotEmpty)
                      Text(texte, style: const TextStyle(color: Colors.white60, fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                )),
                const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
              ]),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_toastEntry!);
    Future.delayed(const Duration(seconds: 5), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    _toastEntry?.remove();
    _toastEntry = OverlayEntry(
      builder: (_) => _AppToast(
        msg: msg,
        error: error,
        onDone: () { _toastEntry?.remove(); _toastEntry = null; },
      ),
    );
    Overlay.of(context).insert(_toastEntry!);
  }

  void _snackAvecReglages(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.location_off_rounded, color: Color(0xFFFF6B35), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13))),
          ],
        ),
        backgroundColor: const Color(0xFF2D2D2D),
        action: SnackBarAction(
          label: 'Réglages',
          textColor: const Color(0xFFFF6B35),
          onPressed: () => Geolocator.openAppSettings(),
        ),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFFF6B35), width: 1),
        ),
      ),
    );
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
      VoidCallback onTap, {int badge = 0}) {
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
      trailing: badge > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$badge',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          : const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
      onTap: onTap,
    );
  }

  Widget _navBtn(IconData icon, String label, VoidCallback onTap,
      {Color color = const Color(0xFFBDBDBD), Color? badgeColor, int badgeCount = 0}) {
    return GestureDetector(
      onTap: () {
        setState(() { _showActionPanel = false; _showNavPanel = false; });
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
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
              if (badgeColor != null)
                Positioned(
                  top: badgeCount > 0 ? -5 : 1,
                  right: badgeCount > 0 ? -5 : 1,
                  child: badgeCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF1A1A1A), width: 1.5),
                        ),
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      )
                    : Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1A1A1A), width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 10)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Stack(
        children: [
          _buildMap(),
          _buildCrosshair(),
          _buildStatusBarOverlay(),
          if (_showParcours) _buildParcoursBanner(),
          if (_selectedCadastreLot != null) _buildSelectedLotPanel(),
          _buildActionPanel(),
          _buildNavPanel(),
          if (!_isOnline && _showOfflineBanner) _buildOfflineBanner(),
          if (_isOnline && _polygonsCache.isEmpty && _showDownloadTip) _buildDownloadTip(),
          if (_showLayerPanel) _buildLayerPanel(),
          Positioned(
            bottom: 20,
            left: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IgnorePointer(
                  child: Opacity(
                    opacity: 0.42,
                    child: Image.asset('assets/logo.png', width: 100),
                  ),
                ),
                const SizedBox(height: 4),
                ScaleBar(zoom: _mapZoom, lat: _mapLat),
              ],
            ),
          ),
          _buildZoomControls(),
          if (_windDeg != null) _buildWindIndicator(),
        ],
        ),
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
        maxZoom: 22,
        onTap: (_, point) => _handleMapTap(point),
        onPositionChanged: (pos, hasGesture) {
          if (!mounted) return;
          if (hasGesture) _followingLocation = false;
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
          if (_showPinchPoints) {
            _pinchDebounce?.cancel();
            _pinchDebounce = Timer(const Duration(milliseconds: 800), _refreshPinchPoints);
          }
          if (_showSalines) {
            _salineDebounce?.cancel();
            _salineDebounce = Timer(const Duration(milliseconds: 800), _refreshSalines);
          }
          if (_showTerresPrivees) {
            if (newZoom < 14.1 && _cadastreRings.isNotEmpty) {
              setState(() { _cadastreRings = []; _cadastreNoLots = []; });
            } else if (newZoom >= 14.1) {
              _fetchCadastre();
            }
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _satellite
              ? 'https://servicesmatriciels.mern.gouv.qc.ca/erdas-iws/ogc/wmts/Imagerie_Continue?layer=Imagerie_GQ&style=default&tilematrixset=GoogleMapsCompatibleExt2:epsg:3857&Service=WMTS&Request=GetTile&Version=1.0.0&Format=image/jpeg&TileMatrix={z}&TileCol={x}&TileRow={y}'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.bastienbouchard.ecomap',
          maxNativeZoom: _satellite ? 20 : 19,
          maxZoom: 22,
        ),
        Opacity(
          opacity: _opacity,
          child: TileLayer(
            tileProvider: MBTilesProvider(),
            minNativeZoom: mbtilesMinZoom,
            maxNativeZoom: mbtilesMaxZoom,
          ),
        ),
        if (_showTerresPrivees && _mapZoom >= 12.0)
          Opacity(
            opacity: 0.7,
            child: TileLayer(
              tileProvider: ArcGISExportTileProvider(
                mapServerUrl: 'https://geo.environnement.gouv.qc.ca/donnees/rest'
                    '/services/Reference/Cadastre_allege/MapServer',
              ),
              minNativeZoom: 12,
              maxNativeZoom: 17,
            ),
          ),
        if (_showTerresPrivees && _cadastreRings.isNotEmpty) ...[
          if (_ecoOpacity > 0)
            PolygonLayer(
              simplificationTolerance: 0,
              polygons: _cadastreRings.asMap().entries.map((e) {
                final selected = e.key == _selectedCadastreLot;
                return Polygon(
                  points: e.value,
                  color: Colors.transparent,
                  borderColor: Colors.white.withOpacity(0.85),
                  borderStrokeWidth: selected ? 5.0 : 3.0,
                );
              }).toList(),
            ),
          PolygonLayer(
            simplificationTolerance: 0,
            polygons: _cadastreRings.asMap().entries.map((e) {
              final selected = e.key == _selectedCadastreLot;
              final onEco = _ecoOpacity > 0;
              return Polygon(
                points: e.value,
                color: selected
                    ? (onEco
                        ? Colors.black.withOpacity(0.12)
                        : const Color(0xFFFF6B35).withOpacity(0.25))
                    : Colors.transparent,
                borderColor: onEco ? Colors.black : const Color(0xFFFF6B35),
                borderStrokeWidth: onEco
                    ? (selected ? 2.5 : 1.8)
                    : (selected ? 2.5 : 1.2),
              );
            }).toList(),
          ),
        ],
        if (_polygonsCache.isNotEmpty && _mapZoom >= 11 && _ecoOpacity > 0)
          Opacity(
            opacity: _ecoOpacity,
            child: PolygonLayer(
                polygons: _polygonsCache, simplificationTolerance: 0),
          ),
        if (_polygonLabels.isNotEmpty && _mapZoom >= 14 && _ecoOpacity > 0)
          Opacity(
            opacity: _ecoOpacity,
            child: MarkerLayer(
              markers: _polygonLabels
                  .where((l) => _mapZoom >= (l['minZoom'] as int? ?? 16))
                  .map((l) => Marker(
                        point: LatLng(l['lat'] as double, l['lon'] as double),
                        width: 90, height: 26,
                        child: GestureDetector(
                          onTap: () {
                            final full = l['full'] as String?;
                            if (full == null || full.isEmpty) return;
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: const Color(0xFF1A1A1A),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                              ),
                              builder: (_) => Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(full,
                                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6)),
                                    const SizedBox(height: 12),
                                    Text('Code: ${l['label']}',
                                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Text(l['label'] as String,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                                Shadow(color: Colors.black, blurRadius: 8),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ))
                  .toList()),
          ),
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
        if (_savedTracks.isNotEmpty)
          PolylineLayer(
            polylines: _savedTracks.asMap().entries.map((e) => Polyline(
              points: e.value.points,
              color: const Color(0xFF4A90E2),
              strokeWidth: 4,
              borderColor: Colors.white,
              borderStrokeWidth: 1.5,
            )).toList(),
          ),
        if (_savedTracks.isNotEmpty)
          MarkerLayer(
            markers: _savedTracks.asMap().entries.map((e) {
              final idx = e.key;
              final pts = e.value.points;
              return Marker(
                point: pts.first,
                width: 36, height: 36,
                child: GestureDetector(
                  onTap: () => _showTrackPopup(idx),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF4A90E2), width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 4)
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.route_rounded,
                          color: Color(0xFF4A90E2), size: 16),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
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
        if (_pinnedPoints.isNotEmpty || _groupePins.isNotEmpty) _buildPinnedLayer(),
        if (_coordPreview != null) MarkerLayer(markers: [
          Marker(
            point: _coordPreview!,
            width: 36, height: 44,
            child: GestureDetector(
              onTap: () => _showCoordPreviewDialog(_coordPreview!),
              child: _pinMarker('coordonnees'),
            ),
          ),
        ]),
        if (_showHotspots && _hotspots.isNotEmpty) _buildHotspotMarkers(),
        if (_showPinchPoints && _pinchPoints.isNotEmpty)
          _buildPinchMarkers(),
        if (_showSalines && _salines.isNotEmpty)
          _buildSalineMarkers(),
        if (_groupeActif && _tracesGroupe.isNotEmpty)
          _buildGroupeTracePolylines(),
        if (_groupeActif && _tracesGroupe.isNotEmpty)
          _buildGroupeTraceLabels(),
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
        final isNew = idx == _newObsIdx;
        Widget markerBall = Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFF6B35), width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 4)],
          ),
          child: Center(child: obsIcon(note, size: 30)),
        );
        if (isNew) {
          markerBall = TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 650),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: markerBall,
          );
        }
        return Marker(
          point: pos,
          width: 52, height: 52,
          child: GestureDetector(
            onTap: () {
              final dt = obs['time'] as DateTime;
              final parts = note.trim().split(' ');
              final label = parts.length > 1 ? parts.sublist(1).join(' ') : parts.first;
              final dateStr =
                '${dt.day.toString().padLeft(2, '0')}/'
                '${dt.month.toString().padLeft(2, '0')}/'
                '${dt.year}';
              showDialog(
                context: context,
                barrierColor: Colors.black54,
                builder: (_) => Dialog(
                  backgroundColor: const Color(0xFF1C1C1C),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        obsIcon(note, size: 52),
                        const SizedBox(height: 10),
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(dateStr,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: _coordsWidget(pos),
                        ),
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () {
                                _deleteObservation(idx);
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.delete_outline,
                                  size: 16, color: Colors.white38),
                              label: const Text('Supprimer',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.push(context,
                                    MaterialPageRoute(builder: (_) =>
                                        NavigationPage(
                                          parcours: [_currentPosition, pos],
                                          score: 0, windDeg: _windDeg,
                                        )));
                              },
                              icon: const Icon(Icons.navigation, size: 16),
                              label: const Text('Naviguer'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B35),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              );
            },
            child: markerBall,
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
        final hotspotFill = (score / 25.0).clamp(0.0, 1.0);
        return Marker(
          point: pos,
          width: 56, height: 66,
          child: GestureDetector(
            onTap: () {
              if (idx < _hotspotInfos.length) {
                showHotspotDetail(context, _hotspotInfos[idx],
                    currentPosition: _currentPosition, windDeg: _windDeg,
                    isPinned: _isPinned(_hotspotInfos[idx].position),
                    onTogglePin: () => setState(() => _togglePin('hotspot', _hotspotInfos[idx].position)));
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    width: 48, height: 5,
                    child: Stack(children: [
                      Container(color: const Color(0xFF1B5E20)),
                      FractionallySizedBox(
                        widthFactor: hotspotFill,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
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
                    ],
                  ),
                  child: Center(
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Icon(Icons.local_fire_department,
                            color: Colors.white12, size: 32),
                        ClipRect(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            heightFactor: hotspotFill.clamp(0.25, 1.0),
                            child: Icon(Icons.local_fire_department,
                                color: flameColor, size: 32),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  MarkerLayer _buildPinchMarkers() {
    final maxPinchScore = _pinchPoints.fold<int>(1, (m, p) => max(m, p['score'] as int? ?? 0));
    return MarkerLayer(
      markers: _pinchPoints.map((p) {
        final pos = LatLng(p['lat'] as double, p['lon'] as double);
        final pScore = p['score'] as int? ?? 0;
        final pFill = (pScore / maxPinchScore).clamp(0.0, 1.0);
        return Marker(
          point: pos,
          width: 48, height: 58,
          child: GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => StatefulBuilder(builder: (ctx, setDlgState) => AlertDialog(
                backgroundColor: const Color(0xFF2D2D2D),
                title: Row(children: [
                  const Expanded(child: Text('Affût',
                      style: TextStyle(color: Colors.white, fontSize: 15))),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 20),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
                content: _coordsWidget(pos),
                actions: [
                  ElevatedButton.icon(
                    onPressed: () {
                      _togglePin('affut', pos);
                      setDlgState(() {});
                    },
                    icon: Icon(
                      _isPinned(pos) ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      size: 16),
                    label: Text(_isPinned(pos) ? 'Désépingler' : 'Épingler'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => NavigationPage(
                          parcours: [_currentPosition, pos],
                          score: 0,
                          windDeg: _windDeg,
                        ),
                      ));
                    },
                    icon: const Icon(Icons.navigation, size: 16),
                    label: const Text('Naviguer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              )),
            ),
            child: SizedBox(
              width: 48, height: 58,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      width: 40, height: 5,
                      child: Stack(children: [
                        Container(color: const Color(0xFF1B5E20)),
                        FractionallySizedBox(
                          widthFactor: pFill,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF4CAF50), width: 2.5),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF4CAF50).withOpacity(0.55),
                            blurRadius: 10, spreadRadius: 1),
                      ],
                    ),
                    child: const Center(
                      child: CustomPaint(
                        size: Size(26, 26),
                        painter: HuntingTowerPainter(color: Color(0xFF4CAF50)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _coordsWidget(LatLng pos) {
    final lat = pos.latitude;
    final lon = pos.longitude;
    final latStr = '${lat.abs().toStringAsFixed(4)}° ${lat >= 0 ? 'N' : 'S'}';
    final lonStr = '${lon.abs().toStringAsFixed(4)}° ${lon >= 0 ? 'E' : 'O'}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.location_on, color: Color(0xFFFF6B35), size: 16),
          const SizedBox(width: 6),
          Text(latStr, style: const TextStyle(color: Colors.white, fontSize: 14,
              fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const SizedBox(width: 22),
          Text(lonStr, style: const TextStyle(color: Colors.white, fontSize: 14,
              fontFamily: 'monospace')),
        ]),
      ],
    );
  }

  MarkerLayer _buildMembreMarkers() {
    return MarkerLayer(
      markers: _membres.asMap().entries.map((entry) {
        final i = entry.key;
        final m = entry.value;
        final color = _traceColors[i % _traceColors.length];
        final initiale = m.nom.isNotEmpty ? m.nom[0].toUpperCase() : '?';
        return Marker(
          point: m.position,
          width: 70, height: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tête 3D
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.4),
                    radius: 0.75,
                    colors: [
                      Color.lerp(color, Colors.white, 0.50)!,
                      color,
                      Color.lerp(color, Colors.black, 0.35)!,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.55),
                      blurRadius: 8,
                      offset: const Offset(2, 5),
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Reflet spéculaire
                    Positioned(
                      top: 7, left: 9,
                      child: Container(
                        width: 11, height: 7,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.38),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(initiale,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black38, blurRadius: 3)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Queue
              CustomPaint(
                size: const Size(14, 10),
                painter: _PinTailPainter(color),
              ),
              // Étiquette nom
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.82),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color, width: 1),
                ),
                child: Text(m.nom,
                  style: const TextStyle(color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static const _traceColors = [
    Color(0xFF4A90E2),
    Color(0xFF7ED321),
    Color(0xFFBD10E0),
    Color(0xFF50E3C2),
  ];

  PolylineLayer _buildGroupeTracePolylines() {
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
          color: _traceColors[i % _traceColors.length],
          strokeWidth: 4,
          borderColor: Colors.black38,
          borderStrokeWidth: 1,
        );
      }).toList(),
    );
  }

  MarkerLayer _buildGroupeTraceLabels() {
    final markers = <Marker>[];
    for (final entry in _tracesGroupe.asMap().entries) {
      final i = entry.key;
      final trace = entry.value;
      final nom = trace['nom'] as String;
      final pts = trace['points'] as List;
      if (pts.isEmpty) continue;
      final last = pts.last;
      final pos = LatLng(
        (last['lat'] as num).toDouble(),
        (last['lon'] as num).toDouble(),
      );
      markers.add(Marker(
        point: pos,
        width: 90, height: 28,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _traceColors[i % _traceColors.length],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: Text(nom,
            style: const TextStyle(color: Colors.white, fontSize: 10,
                fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ));
    }
    return MarkerLayer(markers: markers);
  }

  MarkerLayer _buildGroupeObsMarkers() {
    return MarkerLayer(
      markers: _obsGroupe.where((obs) => !_chasseursMasques.contains(obs['nom'])).map((obs) {
        final pos = LatLng(
          (obs['lat'] as num).toDouble(),
          (obs['lon'] as num).toDouble(),
        );
        final note = obs['note'] as String;
        final nom = obs['nom'] as String;
        return Marker(
          point: pos,
          width: 80, height: 72,
          child: GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF2D2D2D),
                title: Row(children: [
                  Expanded(child: Text(note,
                      style: const TextStyle(color: Colors.white, fontSize: 15))),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
                content: Text('Par $nom',
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ),
            onLongPress: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF2D2D2D),
                title: Text(nom,
                    style: const TextStyle(color: Color(0xFF4A90E2), fontSize: 15)),
                content: Text('Masquer toutes les observations de $nom?',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _chasseursMasques.add(nom));
                      Navigator.pop(context);
                      _snack('Observations de $nom masquées');
                    },
                    child: const Text('Masquer', style: TextStyle(color: Color(0xFFFF6B35))),
                  ),
                ],
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 44, height: 44,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 6, spreadRadius: 1)],
                    ),
                    child: obsIcon(note, size: 36),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF4A90E2), width: 1),
                ),
                child: Text(nom,
                  style: const TextStyle(color: Colors.white, fontSize: 10,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  MarkerLayer _buildCurrentPositionMarker() {
    if (!_hasGpsPosition) return const MarkerLayer(markers: []);
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

  MarkerLayer _buildSalineMarkers() {
    return MarkerLayer(
      markers: () {
        final maxScore = _salines.fold<int>(1, (m, s) => max(m, s['score'] as int? ?? 0));
        return _salines.map((s) {
        final pos = LatLng(s['lat'] as double, s['lon'] as double);
        final score = s['score'] as int? ?? 0;
        final fillLevel = (score / maxScore).clamp(0.0, 1.0);
        final miniCubes = fillLevel >= 0.67 ? 3 : fillLevel >= 0.33 ? 2 : 1;
        return Marker(
          point: pos,
          width: 44, height: 54,
          child: GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => StatefulBuilder(builder: (ctx, setDlgState) => AlertDialog(
                backgroundColor: const Color(0xFF2D2D2D),
                title: Row(children: [
                  const Expanded(child: Text('Site de saline',
                      style: TextStyle(color: Colors.white, fontSize: 15))),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 20),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
                content: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Emplacement idéal identifié par l\'algorithme OrignalScan pour l\'installation d\'une saline.',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                    const SizedBox(height: 12),
                    _coordsWidget(pos),
                  ]),
                actions: [
                  ElevatedButton.icon(
                    onPressed: () {
                      _togglePin('saline', pos);
                      setDlgState(() {});
                    },
                    icon: Icon(
                      _isPinned(pos) ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      size: 16),
                    label: Text(_isPinned(pos) ? 'Désépingler' : 'Épingler'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => NavigationPage(
                          parcours: [_currentPosition, pos],
                          score: 0, windDeg: _windDeg,
                        ),
                      ));
                    },
                    icon: const Icon(Icons.navigation, size: 16),
                    label: const Text('Naviguer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF37474F),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              )),
            ),
            child: SizedBox(
              width: 44, height: 54,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Barre de score verte
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      width: 40, height: 5,
                      child: Stack(children: [
                        Container(color: const Color(0xFF1B5E20)),
                        FractionallySizedBox(
                          widthFactor: fillLevel,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 3),
                  const SizedBox(
                    width: 44, height: 44,
                    child: CustomPaint(painter: SaltCubePainter()),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList();
      }(),
    );
  }

  Widget _pinMarker(String type) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B35),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Center(
          child: Container(
            width: 18, height: 18,
            decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
            padding: const EdgeInsets.all(3),
            child: type == 'affut'
                ? CustomPaint(painter: HuntingTowerPainter(color: const Color(0xFFAAAAAA)))
                : type == 'saline'
                    ? CustomPaint(painter: SaltCubePainter(color: const Color(0xFFAAAAAA)))
                    : type == 'coordonnees'
                        ? const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 12)
                        : const Icon(Icons.local_fire_department_rounded, color: Color(0xFFAAAAAA), size: 10),
          ),
        ),
      ),
      CustomPaint(size: const Size(10, 12), painter: _PinTailPainter(const Color(0xFFFF6B35))),
    ]);
  }

  MarkerLayer _buildPinnedLayer() {
    final myMarkers = _pinnedPoints.map((p) {
      final pos = LatLng(p['lat'] as double, p['lon'] as double);
      final type = p['type'] as String? ?? 'hotspot';
      return Marker(
        point: pos,
        width: 36, height: 44,
        child: GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF2D2D2D),
              title: Row(children: [
                Expanded(child: Text(
                    (p['nom'] as String?)?.isNotEmpty == true ? p['nom'] as String : 'Point épinglé',
                    style: const TextStyle(color: Colors.white, fontSize: 15))),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
              ]),
              content: _coordsWidget(pos),
              actions: [
                TextButton.icon(
                  onPressed: () { Navigator.pop(context); _togglePin(type, pos); },
                  icon: const Icon(Icons.push_pin_outlined, size: 16, color: Color(0xFFFFD700)),
                  label: const Text('Désépingler', style: TextStyle(color: Color(0xFFFFD700))),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => NavigationPage(parcours: [_currentPosition, pos], score: 0, windDeg: _windDeg),
                    ));
                  },
                  icon: const Icon(Icons.navigation, size: 16),
                  label: const Text('Naviguer'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B35), foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
          child: _pinMarker(type),
        ),
      );
    });

    final groupeMarkers = _groupePins.map((p) {
      final pos = LatLng(p['lat'] as double, p['lon'] as double);
      final type = p['type'] as String? ?? 'hotspot';
      final nom = p['nom'] as String? ?? '?';
      return Marker(
        point: pos,
        width: 44, height: 56,
        child: GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF2D2D2D),
              title: Row(children: [
                Expanded(child: Text('Épinglé par $nom',
                    style: const TextStyle(color: Colors.white, fontSize: 14))),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
              ]),
              content: _coordsWidget(pos),
              actions: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => NavigationPage(parcours: [_currentPosition, pos], score: 0, windDeg: _windDeg),
                    ));
                  },
                  icon: const Icon(Icons.navigation, size: 16),
                  label: const Text('Naviguer'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B35), foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(nom, style: const TextStyle(color: Colors.white, fontSize: 9,
                fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 3)])),
            const SizedBox(height: 1),
            _pinMarker(type),
          ]),
        ),
      );
    });

    return MarkerLayer(markers: [...myMarkers, ...groupeMarkers]);
  }

  Widget _buildSelectedLotPanel() {
    final idx = _selectedCadastreLot!;
    final noLot = idx < _cadastreNoLots.length && _cadastreNoLots[idx].isNotEmpty
        ? _cadastreNoLots[idx]
        : 'Lot sélectionné';
    return Positioned(
      bottom: 60, left: 16,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
        ),
        child: Row(children: [
          const Icon(Icons.fence_rounded, color: Color(0xFFFF6B35), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(noLot,
                style: const TextStyle(color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D5016),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _downloadingLotTerritoire ? null : (_downloadedLotNoms.contains('Lot $noLot')
                  ? () => setState(() => _selectedCadastreLot = null)
                  : _downloadLotTerritoire),
              child: _downloadingLotTerritoire
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      _downloadedLotNoms.contains('Lot $noLot') ? 'Retour sur la carte' : 'Carte éco',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setState(() => _selectedCadastreLot = null),
            child: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 18),
          ),
        ]),
      ),
    );
  }

  Widget _buildLayerPanel() {
    return Positioned(
      bottom: 120, right: 28,
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
            InkWell(
              onTap: () async {
                setState(() => _showLayerPanel = false);
                if (!_requirePremium()) return;
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TerritoireDownloadPage(
                    initialCenter: _mapController.camera.center,
                    initialZoom: _mapController.camera.zoom,
                  ),
                ));
                _reloadTerritoire();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(children: [
                  Icon(Icons.forest_rounded,
                      color: _polygonsCache.isNotEmpty
                          ? const Color(0xFFFF6B35)
                          : Colors.white54,
                      size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Carte écoforestière',
                      style: TextStyle(
                          color: _polygonsCache.isNotEmpty
                              ? Colors.white
                              : Colors.white60,
                          fontSize: 13))),
                  const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
                ]),
              ),
            ),
            if (_polygonsCache.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                child: Row(children: [
                  Icon(Icons.forest_rounded,
                      color: _ecoOpacity > 0
                          ? const Color(0xFFFF6B35)
                          : Colors.white38,
                      size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Opacité carte éco',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                  Text('${(_ecoOpacity * 100).round()}%',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12,
                          fontFeatures: [ui.FontFeature.tabularFigures()])),
                ]),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFFFF6B35),
                  thumbColor: const Color(0xFFFF6B35),
                  inactiveTrackColor: Colors.white24,
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: _ecoOpacity,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) => setState(() => _ecoOpacity = v),
                ),
              ),
            ],
            _layerToggle('Terres privées', Icons.fence_rounded,
                _showTerresPrivees, () {
                  if (!_showTerresPrivees && !_requirePremium()) return;
                  setState(() {
                    _showTerresPrivees = !_showTerresPrivees;
                    _showLayerPanel = false;
                  });
                  _fetchCadastre();
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

  Widget _buildWindIndicator() {
    final deg = _windDeg!;
    final speed = _windSpeed ?? 0.0;
    final bannerVisible = (!_isOnline && _showOfflineBanner) ||
        (_isOnline && _polygonsCache.isEmpty && _showDownloadTip);
    return Positioned(
      top: MediaQuery.of(context).padding.top + (bannerVisible ? 62 : 12),
      right: 16,
      child: GestureDetector(
        onTap: (_isOnline || _windDeg != null) ? () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => MeteoPage(
            latitude: _currentPosition.latitude,
            longitude: _currentPosition.longitude,
            windDeg: _windDeg,
            windSpeed: _windSpeed,
            windCached: _windCached,
          ),
        )) : () => _snack('Météo non disponible hors ligne', error: true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withOpacity(0.88),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 6)
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.rotate(
                angle: (deg + 180) * pi / 180,
                child: const Icon(Icons.navigation,
                    color: Colors.white70, size: 15),
              ),
              const SizedBox(width: 6),
              Text('${speed.round()} km/h',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildOfflineBanner() {
    final hasData = _polygonsCache.isNotEmpty;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16, right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasData
              ? const Color(0xFF8B4513).withOpacity(0.95)
              : const Color(0xFFB71C1C).withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6)],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _showOfflineBanner = false),
              child: const Icon(Icons.close, color: Colors.white54, size: 16),
            ),
            const SizedBox(width: 8),
            Icon(hasData ? Icons.wifi_off : Icons.warning_amber_rounded,
                color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasData
                    ? 'Hors ligne — GPS, carte et algorithmes disponibles'
                    : 'Hors ligne sans carte — télécharge la carte éco avant de partir en chasse pour utiliser les algorithmes',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadTip() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16, right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A3A1A).withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6)],
        ),
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _showDownloadTip = false),
            child: const Icon(Icons.close, color: Colors.white38, size: 16),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.download_for_offline_outlined, color: Color(0xFF4CAF50), size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Sans réseau en forêt ? Télécharge ta carte éco avant de partir — requis pour les algorithmes.',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildCrosshair() {
    if (!_showActionPanel) return const SizedBox.shrink();
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
      top: MediaQuery.of(context).padding.top + 10, left: 16, right: 110,
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
          if (_parcoursBlocked)
            const Row(children: [
              Icon(Icons.block, color: Color(0xFFFF6B35), size: 16),
              SizedBox(width: 6),
              Text('Parcours bloqué',
                  style: TextStyle(color: Color(0xFFFF6B35),
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ])
          else ...[
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
          ],
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() { _showParcours = false; _parcoursBlocked = false; }),
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
                      label: 'Hot',
                      color: const Color(0xFFFF6B35),
                      active: _showHotspots,
                      onTap: _toggleHotspots,
                      onLongPress: _showHotspots
                          ? () => _toggleHotspots(forceRefresh: true)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    mapActionBtn(
                      icon: Icons.cabin,
                      label: 'Affût',
                      color: const Color(0xFFFF6B35),
                      active: _showPinchPoints,
                      loading: _loadingPinch,
                      onTap: _togglePinchPoints,
                      customIcon: const SizedBox(
                        width: 22, height: 22,
                        child: CustomPaint(
                            painter: HuntingTowerPainter(color: Color(0xFFFF6B35))),
                      ),
                    ),
                    const SizedBox(height: 6),
                    mapActionBtn(
                      icon: Icons.view_in_ar,
                      label: 'Saline',
                      color: const Color(0xFFFF6B35),
                      active: _showSalines,
                      loading: _loadingSalines,
                      onTap: _toggleSalines,
                      customIcon: const CustomPaint(
                        size: Size(26, 26),
                        painter: SaltCubePainter(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    mapActionBtn(
                      icon: Icons.route_rounded,
                      label: 'Parcours',
                      color: const Color(0xFFFF6B35),
                      active: _showParcours,
                      loading: _loadingParcours,
                      onTap: _showParcours
                          ? () => setState(() => _showParcours = false)
                          : _showParcoursDialog,
                    ),
                    const SizedBox(height: 6),
                    mapActionBtn(
                      icon: Icons.fiber_manual_record,
                      label: 'Suivi',
                      color: const Color(0xFFFF6B35),
                      active: _recording,
                      onTap: _toggleRecording,
                      customIcon: Icon(
                        _recording ? Icons.stop_rounded : Icons.fiber_manual_record,
                        color: const Color(0xFFFF6B35),
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    mapActionBtn(
                      icon: Icons.list_alt_rounded,
                      label: 'Registre',
                      color: const Color(0xFF4A90E2),
                      active: false,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SuivisPage(
                              tracks: List.unmodifiable(_savedTracks),
                              onRename: _renameTrack,
                              onDelete: _deleteTrack,
                              onCenterMap: (idx) {
                                _centerOnTrack(idx);
                              },
                            ),
                          ),
                        );
                      },
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
                  color: const Color(0xFF2D2D2D).withOpacity(0.92),
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12)),
                  border: Border(
                    left: BorderSide(
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
                        offset: const Offset(-2, 0))
                  ],
                ),
                child: Icon(
                  _showNavPanel
                      ? Icons.chevron_right
                      : Icons.chevron_left,
                  color: const Color(0xFFFF6B35),
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
                        (_isOnline || _windDeg != null) ? () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => MeteoPage(
                            latitude: _currentPosition.latitude,
                            longitude: _currentPosition.longitude,
                            windDeg: _windDeg,
                            windSpeed: _windSpeed,
                            windCached: _windCached,
                          ),
                        )) : () => _snack('Météo non disponible hors ligne', error: true),
                        color: (_isOnline || _windDeg != null) ? const Color(0xFFBDBDBD) : Colors.white24),
                    const SizedBox(height: 10),
                    _navBtn(Icons.people, 'Groupe',
                        _isOnline
                            ? _sharePosition
                            : () => _snack('Groupe non disponible hors ligne', error: true),
                        color: _isOnline
                            ? (_groupeActif ? const Color(0xFFFF6B35) : const Color(0xFFBDBDBD))
                            : Colors.white24,
                        badgeColor: _groupeActif
                            ? (_unreadMessages > 0
                                ? Colors.red
                                : (_membres.any((m) => m.nom != _monNom)
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFFF6B35)))
                            : null,
                        badgeCount: _unreadMessages),
                    const SizedBox(height: 10),
                    _navBtn(Icons.info_outline_rounded, 'À propos',
                        () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const AboutPage(),
                            ))),
                    const SizedBox(height: 10),
                    _navBtn(Icons.help_outline_rounded, 'Aide',
                        () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AidePage()))),
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
                mapIconBtn(Icons.search_rounded, _showCoordsSearch),
                mapDividerV(),
                AnimatedBuilder(
                  animation: _layersGlowAnim,
                  builder: (_, __) => GestureDetector(
                    onTap: () {
                      _layersGlowCtrl.stop();
                      setState(() => _showLayerPanel = !_showLayerPanel);
                    },
                    child: SizedBox(
                      width: 42, height: 36,
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_layersGlowCtrl.isAnimating)
                              Container(
                                width: 28 + _layersGlowAnim.value * 14,
                                height: 28 + _layersGlowAnim.value * 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFFF6B35).withOpacity(0.15 + _layersGlowAnim.value * 0.25),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF6B35).withOpacity(0.5 * _layersGlowAnim.value),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            Icon(
                              Icons.layers_rounded,
                              size: 20,
                              color: _layersGlowCtrl.isAnimating
                                  ? Color.lerp(Colors.white, const Color(0xFFFF6B35), _layersGlowAnim.value)
                                  : (_showLayerPanel ? const Color(0xFF4A90E2) : Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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

class _PinTailPainter extends CustomPainter {
  final Color color;
  const _PinTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final fill = Paint()..color = color..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path.shift(const Offset(1, 2)), shadow);
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(_PinTailPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Toast notification (haut de l'écran)
// ─────────────────────────────────────────────────────────────────────────────
class _AppToast extends StatefulWidget {
  final String msg;
  final bool error;
  final VoidCallback onDone;
  const _AppToast({required this.msg, required this.error, required this.onDone});

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _slide = Tween<Offset>(
            begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(Duration(seconds: widget.error ? 3 : 2), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.error ? const Color(0xFFFF6B35) : const Color(0xFF4CAF50);
    final top = MediaQuery.of(context).padding.top + 12;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withOpacity(0.45)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Row(children: [
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.error
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      color: accent, size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.msg,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
