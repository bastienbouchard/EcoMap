import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/hotspot_info.dart';
import '../screens/navigation_page.dart';

void showHotspotDetail(BuildContext context, HotspotInfo info,
    {LatLng? currentPosition, double? windDeg,
    bool isPinned = false, VoidCallback? onTogglePin}) {
  final p = info.props;
  const couvLabels = {'F': 'Feuillu', 'M': 'Mixte', 'R': 'Résineux'};
  final couvCode = (p['type_couv'] ?? '').toString();
  final couv = couvLabels[couvCode] ?? (couvCode.isEmpty ? '—' : couvCode);

  final ess = (p['gr_ess'] ?? '—').toString();

  const ageLabels = {
    'J': '< 10 ans', 'JIN': '< 10 ans',
    '10': '10–20 ans', '20': '20–30 ans', '30': '30–40 ans',
    '40': '40–50 ans', '50': '50–60 ans', '60': '60–80 ans',
    '80': '80–100 ans', '100': '> 100 ans', 'VIN': 'Vieux',
  };
  final ageCode = (p['cl_age'] ?? '').toString();
  final age = ageLabels[ageCode.toUpperCase()] ?? (ageCode.isEmpty ? '—' : ageCode);

  const draiLabels = {
    '0': 'Excessif', '1': 'Rapide', '2': 'Bien drainé',
    '3': 'Modéré', '4': 'Imparfait', '5': 'Mauvais / tourbeux',
    '6': 'Très mauvais / inondé',
  };
  final draiCode = (p['cl_drai'] ?? '').toString();
  final drai = draiLabels[draiCode] ?? (draiCode.isEmpty ? '—' : draiCode);

  final origineCode = (p['origine'] ?? '').toString();
  const origineLabels = {
    'CP': 'Coupe',
    'BR': 'Brûlis',
    'EP': 'Épidémie',
    'CH': 'Chablis',
    'DT': 'Dépérissement',
    'ENS': 'Enfeuillement',
    'P': 'Plantation',
    'MS': 'Mortalité',
  };
  final origine = origineLabels[origineCode] ?? (origineCode.isEmpty ? '—' : origineCode);
  final depSur = (p['dep_sur'] ?? '').toString();
  final typeEco = (p['type_eco'] ?? '—').toString();

  int sAge;
  if (ageCode.isEmpty) {
    sAge = 0;
  } else if (ageCode == 'J' || ageCode == 'JIN' || ageCode == '10') {
    sAge = 5;
  } else if (ageCode == '20') {
    sAge = 4;
  } else if (ageCode == '30') {
    sAge = 3;
  } else if (ageCode == '40' || ageCode == '50') {
    sAge = 2;
  } else {
    sAge = 1; // 60, 80, 100, VIN — forêt mature, donnée présente
  }

  int sDrai;
  if (draiCode.isEmpty) {
    sDrai = 0;
  } else if (draiCode == '6') {
    sDrai = 5; // marécageux / inondé
  } else if (draiCode == '5') {
    sDrai = 4; // tourbeux
  } else if (draiCode == '4') {
    sDrai = 3; // imparfaitement drainé
  } else if (draiCode == '3') {
    sDrai = 2; // modéré
  } else {
    sDrai = 1; // bien drainé / rapide / excessif
  }

  int sEau;
  if (typeEco.toUpperCase().contains('RIV') || draiCode == '6') {
    sEau = 5;
  } else if (depSur.startsWith('4') || draiCode == '5') {
    sEau = 4;
  } else if (depSur.startsWith('3') || draiCode == '4') {
    sEau = 3;
  } else if (draiCode == '3') {
    sEau = 2;
  } else if (draiCode.isNotEmpty) {
    sEau = 1; // donnée de drainage disponible
  } else {
    sEau = 0;
  }

  int sCouv = couvCode == 'F' ? 4 : couvCode == 'M' ? 3 : couvCode == 'R' ? 2 : 0;
  int sEss = 0;
  final essU = ess.toUpperCase();
  if (essU.contains('PE')) sEss = 5;
  else if (essU.contains('AU') || essU.contains('SA')) sEss = 4;
  else if (essU.contains('BP')) sEss = 3;
  else if (essU.contains('EB')) sEss = 1;
  int sOri = origineCode == 'CP' ? 5 : origineCode == 'BR' ? 4 : origineCode == 'EP' ? 2 : 0;

  final bars = [
    ('Couverture', sCouv),
    ('Peuplement', sEss),
    ('Âge', sAge),
    ('Perturbation', sOri),
    ('Drainage', sDrai),
    ('Cours d\'eau', sEau),
  ];

  bool localPinned = isPinned;

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1A1A1A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🔥 ', style: TextStyle(fontSize: 22)),
            Expanded(child: Text('Zone active',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
            if (onTogglePin != null)
              TextButton.icon(
                onPressed: () {
                  onTogglePin?.call();
                  setSheetState(() { localPinned = !localPinned; });
                },
                icon: Icon(localPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    color: const Color(0xFFFFD700), size: 16),
                label: Text(localPinned ? 'Désépingler' : 'Épingler',
                    style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
              ),
            if (currentPosition != null)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NavigationPage(
                      parcours: [currentPosition, info.position],
                      score: 0,
                      windDeg: windDeg,
                    ),
                  ));
                },
                icon: const Icon(Icons.navigation, size: 16),
                label: const Text('Naviguer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _chip('Couverture: $couv'),
            _chip('Peuplement: $ess'),
            _chip('Âge: $age'),
            _chip('Perturbation: $origine'),
            _chip('Drainage: $drai'),
            _chip('${info.position.latitude.toStringAsFixed(4)}° N'),
            _chip('${info.position.longitude.abs().toStringAsFixed(4)}° O'),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: 5,
              barGroups: bars.asMap().entries.map((e) => BarChartGroupData(
                x: e.key,
                barRods: [BarChartRodData(
                  toY: e.value.$2.toDouble(),
                  color: e.value.$2 >= 4 ? const Color(0xFF2D5016) : e.value.$2 >= 2 ? const Color(0xFFFF6B35) : const Color(0xFF555555),
                  width: 26,
                  borderRadius: BorderRadius.circular(4),
                )],
              )).toList(),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (val, _) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(bars[val.toInt()].$1, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                  ),
                )),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(enabled: false),
            )),
          ),
        ],
      ),
    )),
  );
}

Widget _chip(String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFF2D2D2D),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF3D3D3D)),
    ),
    child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
  );
}
