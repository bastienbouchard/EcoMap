import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../services/territoire_service.dart';
import '../services/satellite_cache_service.dart';

class TerritoireDownloadPage extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final String? satUrlTemplate;
  final String? satSource;
  final String? mapboxToken;
  const TerritoireDownloadPage({
    super.key,
    required this.initialCenter,
    required this.initialZoom,
    this.satUrlTemplate,
    this.satSource,
    this.mapboxToken,
  });

  @override
  State<TerritoireDownloadPage> createState() => _TerritoireDownloadPageState();
}

class _TerritoireDownloadPageState extends State<TerritoireDownloadPage> {
  final MapController _mapController = MapController();

  // Sélection des couches à télécharger
  bool _selEco = true; // obligatoire
  bool _selSat = true;  // ESRI + Mapbox
  bool _selTopo = true;

  // Progression
  bool _downloading = false;
  String _status = '';
  double? _progress;

  // Zones téléchargées
  List<Map<String, dynamic>> _zones = [];
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  Future<void> _loadZones() async {
    final list = await TerritoireService.listTerritoires();
    final active = await TerritoireService.getActiveTerritoire();
    if (mounted) setState(() { _zones = list; _activeId = active; });
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () { final v = nomCtrl.text.trim(); if (v.isNotEmpty) Navigator.pop(context, v); },
            child: const Text('Télécharger', style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    );
    if (nom == null || nom.isEmpty) return;

    final bounds = _mapController.camera.visibleBounds;
    final minLat = bounds.south; final maxLat = bounds.north;
    final minLon = bounds.west;  final maxLon = bounds.east;

    setState(() { _downloading = true; _status = 'Démarrage…'; _progress = null; });

    try {
      // 1. Carte écoforestière (toujours incluse)
      setState(() => _status = 'Carte écoforestière…');
      final ecoCount = TerritoireService.estimateTileCount(minLat, minLon, maxLat, maxLon);
      if (ecoCount <= 4) {
        await TerritoireService.downloadTerritoire(
          nom: nom,
          minLat: minLat, minLon: minLon,
          maxLat: maxLat, maxLon: maxLon,
          onStatus: (s) { if (mounted) setState(() => _status = 'Éco · $s'); },
        );
      }

      // 2. Tuiles satellite/topo selon sélection
      final sources = <Map<String, String>>[
        if (_selSat) {'label': 'Satellite ESRI (1/4)',    'url': _satUrl('esri')},
        if (_selSat) {'label': 'Satellite Mapbox (2/4)',  'url': _satUrl('mapbox')},
        if (_selSat) {'label': 'Satellite MRNF QC (3/4)', 'url': 'https://servicesmatriciels.mern.gouv.qc.ca/erdas-iws/ogc/wmts/Imagerie_Continue?layer=Imagerie_GQ&style=default&tilematrixset=GoogleMapsCompatibleExt2:epsg:3857&Service=WMTS&Request=GetTile&Version=1.0.0&Format=image/jpeg&TileMatrix={z}&TileCol={x}&TileRow={y}'},
        if (_selSat) {'label': 'Satellite Sentinel (4/4)', 'url': 'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2023_3857/default/g/{z}/{y}/{x}.jpg'},
        if (_selTopo) {'label': 'Relief et sentiers',      'url': _satUrl('topo')},
      ];
      final satCount = SatelliteCacheService.estimateTileCount(minLat, minLon, maxLat, maxLon);
      if (satCount <= 3000) {
        for (int i = 0; i < sources.length; i++) {
          final src = sources[i];
          if (src['url']!.isEmpty) continue;
          if (mounted) setState(() { _progress = 0; _status = '${src['label']} (${i + 1}/${sources.length})…'; });
          try {
            await SatelliteCacheService.downloadTiles(
              urlTemplate: src['url']!,
              minLat: minLat, minLon: minLon,
              maxLat: maxLat, maxLon: maxLon,
              onProgress: (done, total, s) {
                if (mounted) setState(() { _progress = total > 0 ? done / total : null; _status = '${src['label']} · $s'; });
              },
            );
          } catch (_) {}
        }
      }

      await TerritoireService.setActiveTerritoire(nom);
      await _loadZones();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('« $nom » disponible hors réseau !', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1C1C1C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: const Color(0xFF4CAF50).withOpacity(0.5))),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          duration: const Duration(seconds: 5),
        ));
      }
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

  Future<void> _activate(String id) async {
    await TerritoireService.setActiveTerritoire(id);
    setState(() => _activeId = id);
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Supprimer ?', style: TextStyle(color: Colors.white)),
        content: Text('« $id » sera supprimée.', style: const TextStyle(color: Colors.white60)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    await TerritoireService.deleteTerritoire(id);
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
                initialZoom: widget.initialZoom,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.bastienbouchard.ecomap',
                  tileProvider: SatelliteTileProvider(),
                ),
              ],
            ),
            // Cadre de sélection
            IgnorePointer(child: Center(child: Container(
              margin: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFF6B35), width: 2),
              ),
              child: Container(color: const Color(0xFFFF6B35).withOpacity(0.06)),
            ))),
            // Indication zoom
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

        // ── Sélection des couches ──
        Container(
          color: const Color(0xFF202020),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Couches à télécharger', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('🌿 Carte éco', true, null, subtitle: 'obligatoire'),
              _chip('🛰️ Photos satellite', _selSat, (v) => setState(() => _selSat = v), subtitle: 'vue aérienne'),
              _chip('⛰️ Relief et sentiers', _selTopo, (v) => setState(() => _selTopo = v), subtitle: 'topographie'),
            ]),
            const SizedBox(height: 12),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: const Text('Mes zones', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          ),
          Expanded(
            flex: 3,
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 8),
              itemCount: _zones.length,
              itemBuilder: (_, i) {
                final z = _zones[i];
                final isActive = z['id'] == _activeId;
                return ListTile(
                  dense: true,
                  onTap: () => _activate(z['id'] as String),
                  leading: Icon(
                    isActive ? Icons.check_circle_rounded : Icons.map_outlined,
                    color: isActive ? const Color(0xFF4CAF50) : Colors.white38,
                    size: 20,
                  ),
                  title: Text(z['id'] as String,
                      style: TextStyle(color: isActive ? Colors.white : Colors.white70,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 14)),
                  subtitle: Text('${z['taille_mb']} MB${isActive ? ' · Active' : ''}',
                      style: TextStyle(color: isActive ? const Color(0xFF4CAF50) : Colors.white38, fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 18),
                    onPressed: () => _delete(z['id'] as String),
                  ),
                );
              },
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.all(16),
            child: const Text('Aucune zone téléchargée.', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
      ]),
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
            if (active)
              const Icon(Icons.check_rounded, color: Color(0xFF4CAF50), size: 13),
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
