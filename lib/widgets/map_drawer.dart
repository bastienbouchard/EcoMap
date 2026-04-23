import 'package:flutter/material.dart';

class MapDrawer extends StatelessWidget {
  final bool showPolygons;
  final ValueChanged<bool> onPolygonsChanged;
  final double opacity;
  final ValueChanged<double> onOpacityChanged;
  final double distanceParcours;
  final ValueChanged<double> onDistanceChanged;
  final bool loadingParcours;
  final VoidCallback onGenerateParcours;

  const MapDrawer({
    super.key,
    required this.showPolygons,
    required this.onPolygonsChanged,
    required this.opacity,
    required this.onOpacityChanged,
    required this.distanceParcours,
    required this.onDistanceChanged,
    required this.loadingParcours,
    required this.onGenerateParcours,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(context),
            _section('Couches', [
              SwitchListTile(
                title: const Text('Zones d\'habitat', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Zones colorées par qualité d\'habitat', style: TextStyle(color: Colors.white38, fontSize: 11)),
                value: showPolygons,
                activeColor: const Color(0xFF2D5016),
                onChanged: onPolygonsChanged,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.layers, color: Color(0xFFFF6B35), size: 16),
                const SizedBox(width: 8),
                const Text('Opacité carte', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const Spacer(),
                Text('${(opacity * 100).round()}%', style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 13)),
              ]),
              _opacitySlider(context),
            ]),
            _section('Génération de parcours', [
              const Text(
                'Génère un itinéraire optimisé selon l\'habitat de l\'orignal et le vent.',
                style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Distance:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                Expanded(child: _distanceSlider(context)),
                Text('${distanceParcours.toStringAsFixed(1)} km',
                  style: const TextStyle(color: Color(0xFFFF6B35), fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loadingParcours ? null : () {
                    Navigator.pop(context);
                    onGenerateParcours();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    disabledBackgroundColor: const Color(0xFF8B4513),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: loadingParcours
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.gps_fixed, size: 16),
                          SizedBox(width: 8),
                          Text('Générer le parcours', style: TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                ),
              ),
            ]),
            _section('À propos', [
              const Text(
                'EcoMap analyse les données écoforestières du Québec (IEQM) pour identifier les meilleurs habitats d\'orignal selon les critères scientifiques : couverture végétale, espèces, âge du peuplement, drainage et proximité des cours d\'eau.',
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 8),
              const Text('Données: PRODUITS_IEQM_22D', style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)]),
        border: Border(bottom: BorderSide(color: const Color(0xFFFF6B35).withOpacity(0.3))),
      ),
      child: Row(children: [
        Image.asset('assets/logo.png', height: 40),
        const SizedBox(width: 12),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('EcoMap', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          Text('Habitat orignal', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12)),
        ]),
      ]),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 10),
        ...children,
        const SizedBox(height: 8),
        const Divider(color: Color(0xFF2D2D2D)),
      ]),
    );
  }

  Widget _opacitySlider(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: const Color(0xFFFF6B35),
        inactiveTrackColor: const Color(0xFF3D3D3D),
        thumbColor: const Color(0xFFFF6B35),
        overlayColor: const Color(0xFFFF6B35).withOpacity(0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        trackHeight: 3,
      ),
      child: Slider(value: opacity, min: 0, max: 1, onChanged: onOpacityChanged),
    );
  }

  Widget _distanceSlider(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: const Color(0xFFFF6B35),
        inactiveTrackColor: const Color(0xFF3D3D3D),
        thumbColor: const Color(0xFFFF6B35),
        overlayColor: const Color(0xFFFF6B35).withOpacity(0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        trackHeight: 3,
      ),
      child: Slider(
        value: distanceParcours,
        min: 1.0,
        max: 10.0,
        divisions: 18,
        label: '${distanceParcours.toStringAsFixed(1)} km',
        onChanged: onDistanceChanged,
      ),
    );
  }
}
