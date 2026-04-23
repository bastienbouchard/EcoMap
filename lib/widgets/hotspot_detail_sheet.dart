import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/hotspot_info.dart';

void showHotspotDetail(BuildContext context, HotspotInfo info) {
  final p = info.props;
  final couv = (p['type_couv'] ?? '—').toString();
  final ess = (p['gr_ess'] ?? '—').toString();
  final age = (p['cl_age'] ?? '—').toString();
  final origine = (p['origine'] ?? '—').toString();
  final drai = (p['cl_drai'] ?? '—').toString();
  final depSur = (p['dep_sur'] ?? '—').toString();
  final typeEco = (p['type_eco'] ?? '—').toString();

  int sCouv = couv == 'F' ? 4 : couv == 'M' ? 3 : couv == 'R' ? 2 : 0;
  int sEss = 0;
  final essU = ess.toUpperCase();
  if (essU.contains('PE')) sEss = 5;
  else if (essU.contains('AU') || essU.contains('SA')) sEss = 4;
  else if (essU.contains('BP')) sEss = 3;
  else if (essU.contains('EB')) sEss = 1;
  final ageU = age.toUpperCase();
  int sAge = ageU == 'J' ? 5 : (ageU == '10' || ageU == '20') ? 4 : (ageU == 'JIN' || ageU == '30') ? 2 : 0;
  int sOri = origine == 'CP' ? 5 : origine == 'BR' ? 4 : origine == 'EP' ? 2 : 0;
  int sDrai = (drai == '4' || drai == '5') ? 4 : 0;
  int sEau = (depSur.startsWith('3') || depSur.startsWith('4') ||
      typeEco.toUpperCase().contains('RIV') || drai == '6') ? 3 : 0;

  final bars = [
    ('Couverture', sCouv),
    ('Espèces', sEss),
    ('Âge', sAge),
    ('Origine', sOri),
    ('Drainage', sDrai),
    ('Cours d\'eau', sEau),
  ];

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1A1A1A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🔥 ', style: TextStyle(fontSize: 22)),
            Text('Point chaud — ${info.score} pts',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: info.score >= 18 ? const Color(0xFF1A3A08) : info.score >= 13 ? const Color(0xFF2D5016) : const Color(0xFF5A8A1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${info.score} pts', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _chip('Couverture: $couv'),
            _chip('Espèces: $ess'),
            _chip('Âge: $age'),
            _chip('Origine: $origine'),
            _chip('Drainage: $drai'),
            _chip('Type éco: $typeEco'),
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
    ),
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
