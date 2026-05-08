import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/territoire_service.dart';

class TerritoireDownloadPage extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  const TerritoireDownloadPage({super.key, required this.initialCenter, required this.initialZoom});

  @override
  State<TerritoireDownloadPage> createState() => _TerritoireDownloadPageState();
}

class _TerritoireDownloadPageState extends State<TerritoireDownloadPage> {
  final MapController _mapController = MapController();
  bool _downloading = false;
  String _status = '';
  List<Map<String, dynamic>> _territoires = [];

  @override
  void initState() {
    super.initState();
    _loadTerritoires();
  }

  Future<void> _loadTerritoires() async {
    final list = await TerritoireService.listTerritoires();
    if (mounted) setState(() => _territoires = list);
  }

  Future<void> _download() async {
    final bounds = _mapController.camera.visibleBounds;

    final nomCtrl = TextEditingController(
      text: 'Zone ${DateTime.now().day}-${DateTime.now().month}',
    );

    final nom = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Nom du territoire', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nomCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6B35))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, nomCtrl.text.trim()),
            child: const Text('Télécharger', style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    );

    if (nom == null || nom.isEmpty) return;

    setState(() { _downloading = true; _status = ''; });

    try {
      await TerritoireService.downloadTerritoire(
        nom: nom,
        minLat: bounds.south,
        minLon: bounds.west,
        maxLat: bounds.north,
        maxLon: bounds.east,
        onStatus: (s) => setState(() => _status = s),
      );
      await _loadTerritoires();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$nom téléchargé avec succès !'),
              backgroundColor: const Color(0xFFFF6B35)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { _downloading = false; _status = ''; });
    }
  }

  Future<void> _delete(String id) async {
    await TerritoireService.deleteTerritoire(id);
    await _loadTerritoires();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Télécharger territoire', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
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
                    ),
                  ],
                ),
                // Cadre de sélection
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFF6B35), width: 2),
                    ),
                  ),
                ),
                // Bouton télécharger
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _downloading
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B35))),
                                const SizedBox(width: 12),
                                Text(_status, style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _download,
                            icon: const Icon(Icons.download),
                            label: const Text('Télécharger cette zone'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B35),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          // Liste des territoires téléchargés
          if (_territoires.isNotEmpty)
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Territoires téléchargés',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _territoires.length,
                      itemBuilder: (_, i) {
                        final t = _territoires[i];
                        return ListTile(
                          leading: const Icon(Icons.map, color: Color(0xFFFF6B35)),
                          title: Text(t['id'], style: const TextStyle(color: Colors.white)),
                          subtitle: Text('${t['taille_mb']} MB',
                              style: const TextStyle(color: Colors.white54)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.white38),
                            onPressed: () => _delete(t['id']),
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
}
