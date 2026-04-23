import 'dart:math';
import 'package:flutter/material.dart';

class ScaleBar extends StatelessWidget {
  final double zoom;
  final double lat;

  const ScaleBar({super.key, required this.zoom, required this.lat});

  @override
  Widget build(BuildContext context) {
    final metersPerPx = 156543.03392 * cos(lat * pi / 180) / pow(2, zoom);
    const targets = [10, 25, 50, 100, 250, 500, 1000, 2000, 5000, 10000, 25000, 50000];
    final targetMeters = 90 * metersPerPx;
    double dist = targets.last.toDouble();
    for (final d in targets) {
      if (d >= targetMeters) { dist = d.toDouble(); break; }
    }
    final barWidth = (dist / metersPerPx).clamp(30.0, 100.0);
    final label = dist >= 1000 ? '${(dist / 1000).round()} km' : '${dist.round()} m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withOpacity(0.75),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(width: 2, height: 8, color: Colors.white70),
            Container(width: barWidth - 4, height: 3, color: Colors.white70),
            Container(width: 2, height: 8, color: Colors.white70),
          ]),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}
