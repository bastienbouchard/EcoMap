import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/territoire_service.dart';
import '../services/mbtiles_service.dart';
import '../services/satellite_cache_service.dart';

class TerritoireDownloadPage extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final String? satUrlTemplate;
  final String? satSource;
  final String? mapboxToken;
  final bool ecoOnly;
  const TerritoireDownloadPage({
    super.key,
    required this.initialCenter,
    required this.initialZoom,
    this.satUrlTemplate,
    this.satSource,
    this.mapboxToken,
    this.ecoOnly = false,
  });

  @override
  State<TerritoireDownloadPage> createState() => _TerritoireDownloadPageState();
}

class _TerritoireDownloadPageState extends State<TerritoireDownloadPage> {
  final MapController _mapController = MapController();

  bool _selSat = true;
  bool _selTopo = true;

  // Précision : 14 = Bon, 16 = Précis, 17 = Très précis
  int _maxZoom = 16;
  int get _tileLimit => _maxZoom <= 14 ? 5000 : _maxZoom <= 16 ? 20000 : 80000;

  bool _downloading = false;
  bool _downloadDone = false;
  String _status = '';
  double? _progress;

  List<MbtilesZone> _zones = [];
  String? _activeZoneName;

  StreamSubscription<MapEvent>? _mapSub;
  Timer? _estimateDebounce;
  int _estTiles = 0;
  bool _zoneTooLarge = false;

  @override
  void initState() {
    super.initState();
    if (widget.ecoOnly) { _selSat = false; _selTopo = false; }
    _loadZones();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateEstimate();
      _mapSub = _mapController.mapEventStream.listen((_) {
        _estimateDebounce?.cancel();
        _estimateDebounce = Timer(const Duration(milliseconds: 300), _updateEstimate);
      });
    });
  }

  @override
  void dispose() {
    _mapSub?.cancel();
    _estimateDebounce?.cancel();
    super.dispose();
  }

  void _updateEstimate() {
    if (!mounted) return;
    try {
      final camera = _mapController.camera;
      final camSize = camera.nonRotatedSize;
      final sqSide = math.min(camSize.width, camSize.height) - 80.0;
      final sqLeft = (camSize.width - sqSide) / 2;
      final sqTop  = (camSize.height - sqSide) / 2;
      final tl = camera.screenOffsetToLatLng(Offset(sqLeft, sqTop));
      final br = camera.screenOffsetToLatLng(Offset(sqLeft + sqSide, sqTop + sqSide));
      final count = MbtilesService.estimateTileCount(
        br.latitude, tl.longitude, tl.latitude, br.longitude,
        maxZoom: _maxZoom,
      );
      setState(() {
        _estTiles = count;
        _zoneTooLarge = count > _tileLimit;
      });
    } catch (_) {}
  }

  Future<void> _loadZones() async {
    final list = await MbtilesService.listZones();
    final active = await MbtilesService.getActiveZone();
    if (mounted) setState(() { _zones = list; _activeZoneName = active; });
  }

  String _satUrl(String source) {
    final token = widget.mapboxToken ?? '';
    switch (source) {
      case 'esri':   return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case 'mapbox': return 'https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/{z}/{x}/{y}?access_token=$token';
      case 'topo':   return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      default:       return '';
    }
  }

  // Calcule les bounds du cadre carré affiché
  ({double minLat, double minLon, double maxLat, double maxLon}) _squareBounds() {
    final camera = _mapController.camera;
    final camSize = camera.nonRotatedSize;
    final sqSide = math.min(camSize.width, camSize.height) - 80.0;
    final sqLeft = (camSize.width - sqSide) / 2;
    final sqTop  = (camSize.height - sqSide) / 2;
    final tl = camera.screenOffsetToLatLng(Offset(sqLeft, sqTop));
    final br = camera.screenOffsetToLatLng(Offset(sqLeft + sqSide, sqTop + sqSide));
    return (
      minLat: br.latitude,
      maxLat: tl.latitude,
      minLon: tl.longitude,
      maxLon: br.longitude,
    );
  }

  Future<void> _download() async {
    if (_downloading) return;
    final nomCtrl = TextEditingController();
    final nom = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Nom de la zone', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nomCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'ex: ZEC Magasinipi, Lac Pikauba…',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6B35))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final v = nomCtrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            child: const Text('Télécharger', style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    );
    if (nom == null || nom.isEmpty) return;

    final bounds = _squareBounds();
    final minLat = bounds.minLat, maxLat = bounds.maxLat;
    final minLon = bounds.minLon, maxLon = bounds.maxLon;

    setState(() { _downloading = true; _status = 'Démarrage…'; _progress = null; });

    try {
      // 1. Carte écoforestière (optionnelle — pas de données dans tous les secteurs)
      setState(() => _status = 'Carte écoforestière…');
      final ecoCount = TerritoireService.estimateTileCount(minLat, minLon, maxLat, maxLon);
      if (ecoCount <= 4) {
        try {
          await TerritoireService.downloadTerritoire(
            nom: nom,
            minLat: minLat, minLon: minLon,
            maxLat: maxLat, maxLon: maxLon,
            onStatus: (s) { if (mounted) setState(() => _status = 'Éco · $s'); },
          );
        } catch (_) {
          // Pas de données éco dans ce secteur (lac, zone urbaine…) — on continue
        }
      }

      // 2. Tuiles satellite → fichier .mbtiles (toutes sources fusionnées)
      if (_selSat) {
        final sources = [
          ('Satellite ESRI',     'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'),
          ('Satellite Mapbox',   _satUrl('mapbox')),
          ('Satellite MRNF QC',  'https://servicesmatriciels.mern.gouv.qc.ca/erdas-iws/ogc/wmts/Imagerie_Continue?layer=Imagerie_GQ&style=default&tilematrixset=GoogleMapsCompatibleExt2:epsg:3857&Service=WMTS&Request=GetTile&Version=1.0.0&Format=image/jpeg&TileMatrix={z}&TileCol={x}&TileRow={y}'),
          ('Satellite Sentinel', 'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2023_3857/default/g/{z}/{y}/{x}.jpg'),
        ];
        final satCount = MbtilesService.estimateTileCount(minLat, minLon, maxLat, maxLon, maxZoom: _maxZoom);
        if (satCount <= _tileLimit) {
          for (int i = 0; i < sources.length; i++) {
            final (label, url) = sources[i];
            if (url.isEmpty) continue;
            if (mounted) setState(() { _progress = 0; _status = '$label (${i + 1}/${sources.length})…'; });
            try {
              await MbtilesService.downloadZone(
                name: nom,
                urlTemplate: url,
                minLat: minLat, minLon: minLon,
                maxLat: maxLat, maxLon: maxLon,
                maxZoom: _maxZoom,
                onProgress: (done, total, s) {
                  if (mounted) setState(() {
                    _progress = total > 0 ? done / total : null;
                    _status = '$label · $s';
                  });
                },
              );
            } catch (_) {}
          }
        }
      }

      // 3. Relief/sentiers → fichier .mbtiles séparé
      if (_selTopo) {
        final topoCount = MbtilesService.estimateTileCount(
            minLat, minLon, maxLat, maxLon, maxZoom: _maxZoom);
        if (topoCount <= _tileLimit) {
          if (mounted) setState(() { _progress = 0; _status = 'Relief et sentiers…'; });
          try {
            await MbtilesService.downloadZone(
              name: '${nom}_topo',
              urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
              minLat: minLat, minLon: minLon,
              maxLat: maxLat, maxLon: maxLon,
              maxZoom: _maxZoom,
              onProgress: (done, total, s) {
                if (mounted) setState(() {
                  _progress = total > 0 ? done / total : null;
                  _status = 'Topo · $s';
                });
              },
            );
          } catch (_) {}
        }
      }

      await TerritoireService.setActiveTerritoire(nom);
      await MbtilesService.setActiveZone(nom);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('offline_max_zoom', _maxZoom);
      await _loadZones();
      if (mounted) setState(() => _downloadDone = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1C1C1C),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      ));
    } finally {
      if (mounted) setState(() { _downloading = false; _status = ''; _progress = null; });
    }
  }

  Future<void> _activate(String name) async {
    await MbtilesService.setActiveZone(name);
    await TerritoireService.setActiveTerritoire(name);
    setState(() => _activeZoneName = name);
  }

  Future<void> _delete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Supprimer ?', style: TextStyle(color: Colors.white)),
        content: Text('« $name » sera supprimée.', style: const TextStyle(color: Colors.white60)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await MbtilesService.deleteZone(name);
    await TerritoireService.deleteTerritoire(name);
    await _loadZones();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Zone hors réseau', style: TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(children: [

        // ── Carte de cadrage ──
        Expanded(
          flex: 5,
          child: Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.initialCenter,
                initialZoom: widget.initialZoom.clamp(5.0, 13.0),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.bastienbouchard.ecomap',
                  tileProvider: SatelliteTileProvider(),
                ),
              ],
            ),
            // Cadre carré de sélection
            IgnorePointer(child: LayoutBuilder(
              builder: (ctx, constraints) {
                final side = math.min(constraints.maxWidth, constraints.maxHeight) - 80.0;
                return Center(child: Container(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFFF6B35), width: 2),
                    color: const Color(0xFFFF6B35).withOpacity(0.06),
                  ),
                ));
              },
            )),
            Positioned(top: 10, left: 0, right: 0, child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Cadre la zone à télécharger',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ))),
          ]),
        ),

        // ── Options ──
        Container(
          color: const Color(0xFF202020),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Couches à télécharger',
                style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('🌿 Carte éco', true, null, subtitle: 'obligatoire'),
              if (!widget.ecoOnly) _chip('🛰️ Photos satellite', _selSat,
                  (v) => setState(() => _selSat = v), subtitle: 'fichier .mbtiles'),
              if (!widget.ecoOnly) _chip('⛰️ Relief et sentiers', _selTopo,
                  (v) => setState(() => _selTopo = v), subtitle: 'topographie'),
            ]),
            const SizedBox(height: 12),
            const Text('Précision',
                style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Row(children: [
              _zoomChip('Bon',         14, 'rapide'),
              const SizedBox(width: 8),
              _zoomChip('Précis',      16, 'recommandé'),
              const SizedBox(width: 8),
              _zoomChip('Très précis', 17, 'long'),
            ]),
            const SizedBox(height: 8),
            if (_estTiles > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _zoneTooLarge ? const Color(0xFF3A1A00) : const Color(0xFF1E2A1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _zoneTooLarge
                        ? Colors.orange.withOpacity(0.5)
                        : const Color(0xFF4CAF50).withOpacity(0.3),
                  ),
                ),
                child: Row(children: [
                  Icon(
                    _zoneTooLarge ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                    size: 14,
                    color: _zoneTooLarge ? Colors.orange : const Color(0xFF4CAF50),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    _zoneTooLarge
                        ? 'Zone trop grande — dézoom ou réduis la précision'
                        : '~$_estTiles tuiles · format MBTiles · Dézoom pour agrandir',
                    style: TextStyle(
                      color: _zoneTooLarge ? Colors.orange : Colors.white54,
                      fontSize: 11,
                    ),
                  )),
                ]),
              ),
            const SizedBox(height: 10),
            _downloading
                ? Column(children: [
                    LinearProgressIndicator(
                      value: _progress,
                      color: const Color(0xFF4CAF50),
                      backgroundColor: Colors.white12,
                      minHeight: 3,
                    ),
                    const SizedBox(height: 6),
                    Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ])
                : _downloadDone
                    ? SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Retourner sur la carte'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _download,
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Télécharger cette zone'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B35),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
          ]),
        ),

        // ── Zones téléchargées ──
        if (_zones.isNotEmpty) ...[
          const Divider(height: 1, color: Colors.white12),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text('Mes zones', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          ),
          Expanded(
            flex: 3,
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 8),
              itemCount: _zones.length,
              itemBuilder: (_, i) {
                final z = _zones[i];
                final isActive = z.name == _activeZoneName;
                return ListTile(
                  dense: true,
                  onTap: () => _activate(z.name),
                  leading: Icon(
                    isActive ? Icons.check_circle_rounded : Icons.map_outlined,
                    color: isActive ? const Color(0xFF4CAF50) : Colors.white38,
                    size: 20,
                  ),
                  title: Text(z.name,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.white70,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 14,
                      )),
                  subtitle: Text(
                    '${z.sizeMb.toStringAsFixed(1)} MB · zoom ${z.maxZoom}${isActive ? ' · Active' : ''}',
                    style: TextStyle(
                      color: isActive ? const Color(0xFF4CAF50) : Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 18),
                    onPressed: () => _delete(z.name),
                  ),
                );
              },
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Aucune zone téléchargée.', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
      ]),
    );
  }

  Widget _zoomChip(String label, int zoom, String subtitle) {
    final active = _maxZoom == zoom;
    return Expanded(
      child: GestureDetector(
        onTap: () { setState(() => _maxZoom = zoom); _updateEstimate(); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2A3550) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? const Color(0xFF4A90E2).withOpacity(0.8) : Colors.white12,
            ),
          ),
          child: Column(children: [
            Text(label, style: TextStyle(
              color: active ? Colors.white : Colors.white54,
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            )),
            Text(subtitle, style: TextStyle(
              color: active ? const Color(0xFF4A90E2) : Colors.white24,
              fontSize: 10,
            )),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, ValueChanged<bool>? onChanged, {String? subtitle}) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged(!active),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2D3A2D) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? const Color(0xFF4CAF50).withOpacity(0.7) : Colors.white12,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (active) const Icon(Icons.check_rounded, color: Color(0xFF4CAF50), size: 13),
            if (active) const SizedBox(width: 4),
            Text(label, style: TextStyle(
              color: active ? Colors.white : Colors.white38,
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            )),
          ]),
          if (subtitle != null)
            Text(subtitle, style: TextStyle(
              color: active ? Colors.white38 : Colors.white24,
              fontSize: 10,
            )),
        ]),
      ),
    );
  }
}
