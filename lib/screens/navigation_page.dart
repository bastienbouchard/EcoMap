import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../painters/painters.dart';

class NavigationPage extends StatefulWidget {
  final List<LatLng> parcours;
  final double score;
  final double? windDeg;

  const NavigationPage({super.key, required this.parcours, required this.score, this.windDeg});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  double _currentHeading = 0;
  int _currentWaypointIndex = 0;
  double _distanceToNext = 0;
  double _bearingToNext = 0;
  StreamSubscription<Position>? _positionSubscription;
  double _totalDistance = 0;
  double _completedDistance = 0;

  @override
  void initState() {
    super.initState();
    _calculateTotalDistance();
    _startTracking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _calculateTotalDistance() {
    double total = 0;
    for (int i = 0; i < widget.parcours.length - 1; i++) {
      total += const Distance().as(LengthUnit.Meter, widget.parcours[i], widget.parcours[i + 1]);
    }
    setState(() => _totalDistance = total);
  }

  void _startTracking() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _updatePosition(pos);
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen(_updatePosition);
    } catch (e) {}
  }

  void _updatePosition(Position position) {
    final newPos = LatLng(position.latitude, position.longitude);
    setState(() => _currentHeading = position.heading);
    _updateWaypoint(newPos);
  }

  void _updateWaypoint(LatLng currentPos) {
    if (_currentWaypointIndex >= widget.parcours.length) return;
    final nextWaypoint = widget.parcours[_currentWaypointIndex];
    final distance = const Distance().as(LengthUnit.Meter, currentPos, nextWaypoint);
    setState(() {
      _distanceToNext = distance;
      _bearingToNext = _calculateBearing(currentPos, nextWaypoint);
    });
    if (distance < 20 && _currentWaypointIndex < widget.parcours.length - 1) {
      setState(() {
        _completedDistance += const Distance().as(
          LengthUnit.Meter,
          widget.parcours[_currentWaypointIndex],
          widget.parcours[_currentWaypointIndex + 1],
        );
        _currentWaypointIndex++;
      });
    }
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final dLon = (to.longitude - from.longitude) * pi / 180;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  String _getDirectionText(double relativeBearing) {
    if (relativeBearing.abs() < 15) return 'Tout droit';
    if (relativeBearing > 15 && relativeBearing < 45) return 'Légèrement à droite';
    if (relativeBearing >= 45 && relativeBearing < 135) return 'Tournez à droite';
    if (relativeBearing >= 135 && relativeBearing <= 180) return 'Demi-tour à droite';
    if (relativeBearing < -15 && relativeBearing > -45) return 'Légèrement à gauche';
    if (relativeBearing <= -45 && relativeBearing > -135) return 'Tournez à gauche';
    if (relativeBearing <= -135) return 'Demi-tour à gauche';
    return 'Tout droit';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalDistance > 0 ? (_completedDistance / _totalDistance).clamp(0.0, 1.0) : 0.0;
    final relativeBearing = _bearingToNext - _currentHeading;
    final normalizedBearing = ((relativeBearing + 180) % 360) - 180;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(progress),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            final compassSize = (constraints.maxHeight * 0.80).clamp(180.0, 300.0);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: compassSize, height: compassSize,
                  child: CustomPaint(painter: CompassPainter(
                    rotation: -_currentHeading * pi / 180,
                    targetBearing: _bearingToNext,
                    windDeg: widget.windDeg,
                  )),
                ),
                const SizedBox(height: 20),
                _buildDistanceCard(normalizedBearing),
              ],
            );
          })),
          _buildLegend(),
          const SizedBox(height: 8),
          _buildBottomStats(progress),
        ]),
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _legendDot(const Color(0xFFFF6B35), 'Destination'),
          if (widget.windDeg != null)
            _legendDot(const Color(0xFF4CAF50), 'Face au vent'),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _buildHeader(double progress) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)]),
        border: Border(bottom: BorderSide(color: const Color(0xFFFF6B35).withOpacity(0.3))),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF3D3D3D), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.arrow_back, color: Color(0xFFFF6B35)),
          ),
        ),
        const SizedBox(width: 16),
        const Text('Navigation', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildDistanceCard(double normalizedBearing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
      ),
      child: Column(children: [
        Text('${_distanceToNext.round()} m', style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 48, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_getDirectionText(normalizedBearing), style: const TextStyle(color: Colors.white70, fontSize: 18)),
      ]),
    );
  }

  Widget _buildBottomStats(double progress) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)]),
        border: Border(top: BorderSide(color: const Color(0xFFFF6B35).withOpacity(0.3))),
      ),
      child: Column(children: [
        Row(children: [
          const Text('Progression', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const Spacer(),
          Text('${(progress * 100).round()}%', style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: progress, minHeight: 12, backgroundColor: const Color(0xFF3D3D3D), color: const Color(0xFFFF6B35)),
        ),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat('Point', '${_currentWaypointIndex + 1}/${widget.parcours.length}', Icons.flag),
          _stat('Distance totale', '${(_totalDistance / 1000).toStringAsFixed(1)} km', Icons.straighten),
          _stat('Restant', '${((_totalDistance - _completedDistance) / 1000).toStringAsFixed(1)} km', Icons.timeline),
        ]),
      ]),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Column(children: [
      Icon(icon, color: const Color(0xFFFF6B35), size: 24),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }
}
