import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../screens/meteo_page.dart';
import '../screens/parcours_page.dart';
import '../screens/about_page.dart';

class MapDrawer extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double? windDeg;
  final double? windSpeed;
  final List<Map<String, dynamic>> observations;
  final void Function(LatLng pos) onObservationTap;
  final void Function(int idx) onDeleteObservation;
  final double distanceParcours;
  final ValueChanged<double> onDistanceChanged;
  final bool loadingParcours;
  final VoidCallback onGenerateParcours;

  const MapDrawer({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.windDeg,
    required this.windSpeed,
    required this.observations,
    required this.onObservationTap,
    required this.onDeleteObservation,
    required this.distanceParcours,
    required this.onDistanceChanged,
    required this.loadingParcours,
    required this.onGenerateParcours,
  });

  void _navigate(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8),
                children: [
                  _navItem(context, Icons.map_rounded, 'Accueil',
                      color: const Color(0xFFFF6B35),
                      onTap: () => Navigator.pop(context)),
                  _navItem(context, Icons.wb_sunny_rounded, 'Météo',
                      color: const Color(0xFF4FC3F7),
                      onTap: () => _navigate(context, MeteoPage(
                        latitude: latitude,
                        longitude: longitude,
                        windDeg: windDeg,
                        windSpeed: windSpeed,
                      ))),
                  _navItem(context, Icons.route_rounded, 'Générateur de parcours',
                      color: const Color(0xFF66BB6A),
                      onTap: () => _navigate(context, ParcoursPage(
                        distance: distanceParcours,
                        onDistanceChanged: onDistanceChanged,
                        loading: loadingParcours,
                        onGenerate: onGenerateParcours,
                      ))),
                  const Divider(color: Color(0xFF2D2D2D), indent: 20, endIndent: 20),
                  _navItem(context, Icons.info_outline_rounded, 'À propos',
                      color: const Color(0xFFBDBDBD),
                      onTap: () => _navigate(context, const AboutPage())),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
          Text('OrignalScan', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          Text('Habitat orignal', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12)),
        ]),
      ]),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String label,
      {required VoidCallback onTap, Color color = const Color(0xFFFF6B35)}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        trailing: Icon(Icons.chevron_right, color: color.withOpacity(0.5), size: 18),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
    );
  }
}
