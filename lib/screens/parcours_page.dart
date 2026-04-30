import 'package:flutter/material.dart';

class ParcoursPage extends StatefulWidget {
  final double distance;
  final ValueChanged<double> onDistanceChanged;
  final bool loading;
  final VoidCallback onGenerate;

  const ParcoursPage({
    super.key,
    required this.distance,
    required this.onDistanceChanged,
    required this.loading,
    required this.onGenerate,
  });

  @override
  State<ParcoursPage> createState() => _ParcoursPageState();
}

class _ParcoursPageState extends State<ParcoursPage> {
  late double _distance;

  @override
  void initState() {
    super.initState();
    _distance = widget.distance;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Générateur de parcours', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Color(0xFFFF6B35)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(children: [
            const Text('Parcours optimisé', style: TextStyle(
                color: Color(0xFFFF6B35), fontSize: 13,
                fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            const Text(
              'Génère un itinéraire optimisé selon l\'habitat de l\'orignal et le vent. Le parcours évite les plans d\'eau et les pentes abruptes.',
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
          ]),
          const SizedBox(height: 12),
          _card(children: [
            const Text('Distance', style: TextStyle(
                color: Color(0xFFFF6B35), fontSize: 13,
                fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.straighten, color: Colors.white38, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFFFF6B35),
                    inactiveTrackColor: const Color(0xFF3D3D3D),
                    thumbColor: const Color(0xFFFF6B35),
                    overlayColor: const Color(0xFFFF6B35).withOpacity(0.2),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _distance,
                    min: 1.0,
                    max: 10.0,
                    divisions: 18,
                    onChanged: (val) {
                      setState(() => _distance = val);
                      widget.onDistanceChanged(val);
                    },
                  ),
                ),
              ),
              Container(
                width: 60,
                alignment: Alignment.center,
                child: Text('${_distance.toStringAsFixed(1)} km',
                    style: const TextStyle(color: Color(0xFFFF6B35),
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ]),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: widget.loading ? null : () {
                Navigator.pop(context);
                widget.onGenerate();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                disabledBackgroundColor: const Color(0xFF8B4513),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: widget.loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.gps_fixed, size: 20),
              label: Text(widget.loading ? 'Génération...' : 'Générer le parcours',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
