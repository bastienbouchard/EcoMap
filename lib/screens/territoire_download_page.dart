import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../services/territoire_service.dart';
import '../services/satellite_cache_service.dart';

enum _SelectionMode { screen, draw }

class TerritoireDownloadPage extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final String? satUrlTemplate;
  final String? satSource;
  const TerritoireDownloadPage({
    super.key,
    required this.initialCenter,
    required this.initialZoom,
    this.satUrlTemplate,
    this.satSource,
  });

  @override
  State<TerritoireDownloadPage> createState() => _TerritoireDownloadPageState();
}

class _TerritoireDownloadPageState extends State<TerritoireDownloadPage> {
  final MapController _mapController = MapController();
  bool _downloading = false;
  bool _downloaded = false;
  String _status = '';
  List<Map<String, dynamic>> _territoires = [];
  String? _activeId;
  _SelectionMode _mode = _SelectionMode.screen;

  // satellite pre-download
  bool _downloadingSat = false;
  int _satProgress = 0;
  int _satTotal = 0;
  String _satStatus = '';

  // dessin
  List<Offset> _drawPoints = [];
  List<LatLng> _drawnLatLng = [];
  bool _drawing = false;

  @override
  void initState() {
    super.initState();
    _loadTerritoires();
  }

  Future<void> _loadTerritoires() async {
    final list = await TerritoireService.listTerritoires();
    final activeId = await TerritoireService.getActiveTerritoire();
    if (mounted) setState(() { _territoires = list; _activeId = activeId; });
  }

  Future<void> _activate(String id) async {
    await TerritoireService.setActiveTerritoire(id);
    setState(() => _activeId = id);
  }

  // Convertit un Offset écran en LatLng (projection Mercator manuelle)
  LatLng _toLatLng(Offset pos, BoxConstraints constraints) {
    final camera = _mapController.camera;
    final zoom = camera.zoom;
    final center = camera.center;
    final worldSize = 256.0 * math.pow(2, zoom);

    final centerLatRad = center.latitude * math.pi / 180;
    final centerX = (center.longitude + 180) / 360 * worldSize;
    final mercN = math.log(math.tan(math.pi / 4 + centerLatRad / 2));
    final centerY = (1 - mercN / math.pi) / 2 * worldSize;

    final touchX = centerX + (pos.dx - constraints.maxWidth / 2);
    final touchY = centerY + (pos.dy - constraints.maxHeight / 2);

    final lon = touchX / worldSize * 360 - 180;
    final n = math.pi - 2 * math.pi * touchY / worldSize;
    final lat = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));

    return LatLng(lat, lon);
  }

  Future<void> _download({List<LatLng>? polygon}) async {
    double minLat, maxLat, minLon, maxLon;

    if (polygon != null && polygon.length >= 3) {
      minLat = polygon.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
      maxLat = polygon.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
      minLon = polygon.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
      maxLon = polygon.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    } else {
      final bounds = _mapController.camera.visibleBounds;
      minLat = bounds.south; maxLat = bounds.north;
      minLon = bounds.west;  maxLon = bounds.east;
    }

    final tileCount = TerritoireService.estimateTileCount(minLat, minLon, maxLat, maxLon);
    if (tileCount > 4) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text('Zone trop grande', style: TextStyle(color: Colors.white)),
          content: Text(
            'Cette zone couvre $tileCount secteurs — limite maximale : 4.\n\n'
            'Zoome sur ton secteur de chasse précis et réessaie.\n\n'
            '4 secteurs = environ 100 × 200 km, largement suffisant.',
            style: const TextStyle(color: Colors.white70, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK, je zoom', style: TextStyle(color: Color(0xFFFF6B35))),
            ),
          ],
        ),
      );
      return;
    }

    final nomCtrl = TextEditingController();

    final nom = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Nom de la carte', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nomCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'ex: ZEC Magasinipi, Pourvoirie Lafond…',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6B35))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
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
    setState(() { _downloading = true; _status = ''; });
    String? _lastStatus;

    try {
      await TerritoireService.downloadTerritoire(
        nom: nom,
        minLat: minLat, minLon: minLon,
        maxLat: maxLat, maxLon: maxLon,
        onStatus: (s) { _lastStatus = s; setState(() => _status = s); },
      );
      await TerritoireService.setActiveTerritoire(nom);
      await _loadTerritoires();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '$nom téléchargé !\n${_lastStatus ?? ""}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          backgroundColor: const Color(0xFF1C1C1C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: const Color(0xFF4CAF50).withOpacity(0.5)),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          duration: const Duration(seconds: 8),
        ));
        setState(() { _drawnLatLng = []; _drawPoints = []; _downloaded = true; });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e', style: const TextStyle(color: Colors.white, fontSize: 13)),
          backgroundColor: const Color(0xFF1C1C1C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: const Color(0xFFFF6B35).withOpacity(0.5)),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() { _downloading = false; _status = ''; });
    }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Supprimer la carte ?', style: TextStyle(color: Colors.white)),
        content: Text('« $id » sera supprimée.', style: const TextStyle(color: Colors.white60)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;
    await TerritoireService.deleteTerritoire(id);
    await _loadTerritoires();
  }

  Future<void> _downloadSatellite({List<LatLng>? polygon}) async {
    if (widget.satUrlTemplate == null) return;
    double minLat, maxLat, minLon, maxLon;

    if (polygon != null && polygon.length >= 3) {
      minLat = polygon.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
      maxLat = polygon.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
      minLon = polygon.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
      maxLon = polygon.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    } else {
      final bounds = _mapController.camera.visibleBounds;
      minLat = bounds.south; maxLat = bounds.north;
      minLon = bounds.west;  maxLon = bounds.east;
    }

    final count = SatelliteCacheService.estimateTileCount(minLat, minLon, maxLat, maxLon);

    if (count > 3000) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Zone trop grande ($count tuiles). Zoome sur ton secteur de chasse.'),
        backgroundColor: const Color(0xFF1C1C1C),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      ));
      return;
    }

    final sizeMb = (count * 30 / 1024).round();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Pré-charger satellite', style: TextStyle(color: Colors.white)),
        content: Text(
          '$count tuiles satellitaires (${widget.satSource ?? ''}) seront téléchargées '
          'pour cette zone.\n\n~$sizeMb MB · zoom 10–14',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Télécharger', style: TextStyle(color: Color(0xFF42A5F5))),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _downloadingSat = true; _satProgress = 0; _satTotal = 0; _satStatus = 'Démarrage…';
    });
    try {
      await SatelliteCacheService.downloadTiles(
        urlTemplate: widget.satUrlTemplate!,
        minLat: minLat, minLon: minLon,
        maxLat: maxLat, maxLon: maxLon,
        onProgress: (done, total, status) {
          if (mounted) setState(() { _satProgress = done; _satTotal = total; _satStatus = status; });
        },
      );
      final cached = await SatelliteCacheService.countCachedTiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Satellite pré-chargé ! ($cached tuiles en cache)',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1C1C1C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: const Color(0xFF42A5F5).withOpacity(0.5)),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1C1C1C),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        ));
      }
    } finally {
      if (mounted) setState(() => _downloadingSat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Cartes éco', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // ── Explication offline ──
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.4)),
            ),
            child: const Row(children: [
              Icon(Icons.download_for_offline_outlined, color: Color(0xFF4CAF50), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sans réseau en forêt, télécharge ta carte éco ici avant de partir — les algorithmes (affût, saline, parcours) en ont besoin.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ]),
          ),
          // ── Sélecteur de mode ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(children: [
              _modeBtn('Zone visible', Icons.crop_free, _SelectionMode.screen),
              const SizedBox(width: 10),
              _modeBtn('Dessiner', Icons.gesture, _SelectionMode.draw),
            ]),
          ),
          if (_mode == _SelectionMode.draw)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Text('Trace ta zone au doigt sur la carte',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),

          // ── Carte ──
          Expanded(
            flex: 3,
            child: LayoutBuilder(builder: (ctx, constraints) {
              return Stack(children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.initialCenter,
                    initialZoom: widget.initialZoom,
                    interactionOptions: InteractionOptions(
                      flags: _mode == _SelectionMode.draw
                          ? InteractiveFlag.none
                          : InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.bastienbouchard.ecomap',
                    ),
                    if (_drawnLatLng.length >= 2)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: [..._drawnLatLng, _drawnLatLng.first],
                          color: const Color(0xFFFF6B35),
                          strokeWidth: 2.5,
                        ),
                      ]),
                  ],
                ),

                // Cadre zone visible
                if (_mode == _SelectionMode.screen)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFFF6B35), width: 2),
                        ),
                      ),
                    ),
                  ),

                // Overlay de dessin
                if (_mode == _SelectionMode.draw)
                  Positioned.fill(
                    child: GestureDetector(
                      onPanStart: (d) {
                        setState(() {
                          _drawing = true;
                          _drawPoints = [d.localPosition];
                          _drawnLatLng = [_toLatLng(d.localPosition, constraints)];
                        });
                      },
                      onPanUpdate: (d) {
                        // Échantillonne 1 point tous les 8px pour éviter trop de points
                        if (_drawPoints.isEmpty ||
                            (d.localPosition - _drawPoints.last).distance > 8) {
                          setState(() {
                            _drawPoints.add(d.localPosition);
                            _drawnLatLng.add(_toLatLng(d.localPosition, constraints));
                          });
                        }
                      },
                      onPanEnd: (_) => setState(() => _drawing = false),
                      child: CustomPaint(
                        painter: _DrawPainter(_drawPoints, _drawing),
                      ),
                    ),
                  ),

                // Bouton télécharger
                Positioned(
                  bottom: 16 + MediaQuery.of(ctx).viewPadding.bottom, left: 0, right: 0,
                  child: Center(
                    child: _downloading
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Color(0xFFFF6B35))),
                              const SizedBox(width: 12),
                              Text(_status, style: const TextStyle(color: Colors.white)),
                            ]))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            _downloaded
                                ? ElevatedButton.icon(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.map_rounded),
                                    label: const Text('Retour sur la carte'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2D5016),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    ),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: (_mode == _SelectionMode.draw && _drawnLatLng.length < 3)
                                        ? null
                                        : () => _download(
                                              polygon: _mode == _SelectionMode.draw
                                                  ? _drawnLatLng
                                                  : null,
                                            ),
                                    icon: const Icon(Icons.download),
                                    label: Text(_mode == _SelectionMode.draw
                                        ? 'Télécharger la zone dessinée'
                                        : 'Télécharger cette zone'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF6B35),
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: Colors.white24,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    ),
                                  ),
                            if (_mode == _SelectionMode.draw && _drawnLatLng.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.white54),
                                tooltip: 'Effacer',
                                onPressed: () => setState(() {
                                  _drawnLatLng = []; _drawPoints = [];
                                }),
                              ),
                            ],
                          ]),
                  ),
                ),
              ]);
            }),
          ),

          // ── Pré-chargement satellite ──
          if (widget.satUrlTemplate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1A2A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF42A5F5).withOpacity(0.35)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: _downloadingSat
                    ? Row(children: [
                        const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF42A5F5)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Satellite ${widget.satSource ?? ''} · $_satStatus',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: _satTotal > 0 ? _satProgress / _satTotal : null,
                              color: const Color(0xFF42A5F5),
                              backgroundColor: Colors.white12,
                            ),
                          ],
                        )),
                      ])
                    : Row(children: [
                        const Icon(Icons.satellite_alt, color: Color(0xFF42A5F5), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Satellite ${widget.satSource ?? ''} — zoom 10–14 pour hors-ligne',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _downloading
                              ? null
                              : () => _downloadSatellite(
                                    polygon: _mode == _SelectionMode.draw
                                        ? (_drawnLatLng.length >= 3 ? _drawnLatLng : null)
                                        : null,
                                  ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.white12,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            textStyle: const TextStyle(fontSize: 13),
                          ),
                          child: const Text('Pré-charger'),
                        ),
                      ]),
              ),
            ),

          // ── Liste des territoires ──
          if (_territoires.isNotEmpty)
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Text('Cartes téléchargées',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
                      itemCount: _territoires.length,
                      itemBuilder: (_, i) {
                        final t = _territoires[i];
                        final isActive = t['id'] == _activeId;
                        return ListTile(
                          onTap: () => _activate(t['id'] as String),
                          leading: Icon(
                            isActive ? Icons.check_circle : Icons.map_outlined,
                            color: isActive ? const Color(0xFF4CAF50) : const Color(0xFFFF6B35),
                          ),
                          title: Text(t['id'],
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              )),
                          subtitle: Text(
                            '${t['taille_mb']} MB${isActive ? ' · Active' : ''}',
                            style: TextStyle(
                              color: isActive ? const Color(0xFF4CAF50) : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _delete(t['id'] as String),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeBtn(String label, IconData icon, _SelectionMode mode) {
    final active = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _mode = mode;
          _drawnLatLng = [];
          _drawPoints = [];
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFF6B35) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? const Color(0xFFFF6B35) : Colors.white24),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: active ? Colors.white : Colors.white54, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class _DrawPainter extends CustomPainter {
  final List<Offset> points;
  final bool drawing;
  const _DrawPainter(this.points, this.drawing);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = const Color(0xFFFF6B35)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) { path.lineTo(p.dx, p.dy); }
    if (!drawing) path.close();
    canvas.drawPath(path, paint);

    final fillPaint = Paint()
      ..color = const Color(0xFFFF6B35).withOpacity(0.15)
      ..style = PaintingStyle.fill;
    if (!drawing) canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(_DrawPainter old) =>
      old.points.length != points.length || old.drawing != drawing;
}
