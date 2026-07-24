import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class SuivisPage extends StatefulWidget {
  final List<({String nom, DateTime date, List<LatLng> points})> tracks;
  final void Function(int idx, String newNom) onRename;
  final void Function(int idx) onDelete;
  final void Function(int idx) onCenterMap;

  const SuivisPage({
    super.key,
    required this.tracks,
    required this.onRename,
    required this.onDelete,
    required this.onCenterMap,
  });

  @override
  State<SuivisPage> createState() => _SuivisPageState();
}

class _SuivisPageState extends State<SuivisPage> {
  late List<({String nom, DateTime date, List<LatLng> points, int globalIdx})> _items;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  void _rebuild() {
    _items = List.generate(widget.tracks.length, (i) => (
      nom: widget.tracks[i].nom,
      date: widget.tracks[i].date,
      points: widget.tracks[i].points,
      globalIdx: i,
    )).reversed.toList();
  }

  double _calcDist(List<LatLng> pts) {
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i]; final b = pts[i + 1];
      final c = cos(a.latitude * pi / 180);
      total += sqrt(pow((b.latitude - a.latitude) * 111000, 2) +
                    pow((b.longitude - a.longitude) * 111000 * c, 2));
    }
    return total;
  }

  String _distStr(List<LatLng> pts) {
    final d = _calcDist(pts);
    if (d >= 1000) return '${(d / 1000).toStringAsFixed(1)} km';
    return '${d.round()} m';
  }

  String _dateLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}  '
      '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  void _showRenameDialog(int localIdx) {
    final item = _items[localIdx];
    final ctrl = TextEditingController(text: item.nom);
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
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              final newNom = ctrl.text.trim();
              if (newNom.isNotEmpty) {
                setState(() {
                  _items[localIdx] = (
                    nom: newNom,
                    date: item.date,
                    points: item.points,
                    globalIdx: item.globalIdx,
                  );
                });
                widget.onRename(item.globalIdx, newNom);
              }
              Navigator.pop(context);
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(int localIdx) {
    final item = _items[localIdx];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce suivi ?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          item.nom.isNotEmpty ? item.nom : _dateLabel(item.date),
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final globalIdx = item.globalIdx;
              setState(() => _items.removeAt(localIdx));
              widget.onDelete(globalIdx);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        title: Text(
          'Registre des suivis${_items.isNotEmpty ? "  (${_items.length})" : ""}',
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _items.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.route_rounded, color: Colors.white24, size: 52),
                SizedBox(height: 12),
                Text('Aucun suivi enregistré',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              ]),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, localIdx) {
                final t = _items[localIdx];
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.route_rounded,
                          color: Color(0xFF4A90E2), size: 20),
                    ),
                    title: Text(
                      t.nom.isNotEmpty ? t.nom : _dateLabel(t.date),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '${t.nom.isNotEmpty ? "${_dateLabel(t.date)}  •  " : ""}'
                        '${_distStr(t.points)}  •  ${t.points.length} pts',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.my_location_rounded,
                            color: Color(0xFF4A90E2), size: 20),
                        tooltip: 'Voir sur la carte',
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onCenterMap(t.globalIdx);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: Colors.white54, size: 20),
                        tooltip: 'Renommer',
                        onPressed: () => _showRenameDialog(localIdx),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.white24, size: 20),
                        tooltip: 'Supprimer',
                        onPressed: () => _confirmDelete(localIdx),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
