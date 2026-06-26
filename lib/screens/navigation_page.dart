import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../painters/painters.dart';
import '../services/compass_heading.dart';

class NavigationPage extends StatefulWidget {
  final List<LatLng> parcours;
  final double score;
  final double? windDeg;

  const NavigationPage({super.key, required this.parcours, required this.score, this.windDeg});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> with SingleTickerProviderStateMixin {
  double _currentHeading = 0;
  int _currentWaypointIndex = 1;
  double _distanceToNext = 0;
  double _bearingToNext = 0;
  StreamSubscription<Position>? _positionSubscription;
  double _totalDistance = 0;
  double _completedDistance = 0;

  // Vitesse de marche : 3 km/h par défaut, ajustée toutes les 5 min
  double _walkingSpeedKmh = 3.0;
  DateTime? _lastSpeedUpdate;
  double _distanceAtLastSpeedUpdate = 0;

  StreamSubscription<double>? _compassSubscription;
  bool _compassPermissionGranted = false;
  double _currentSegmentLength = 0;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _calculateTotalDistance();
    _startTracking();
    _initCompass();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initCompass() async {
    final granted = await requestCompassPermission();
    if (!mounted || !granted) return;
    _compassSubscription = compassHeadingStream().listen((heading) {
      if (mounted) setState(() {
        _compassPermissionGranted = true;
        _currentHeading = heading;
      });
    });
  }

  Future<void> _activateCompass() async {
    if (_compassSubscription != null) return;
    final granted = await requestCompassPermission();
    if (!mounted || !granted) return;
    _compassSubscription = compassHeadingStream().listen((heading) {
      if (mounted) setState(() {
        _compassPermissionGranted = true;
        _currentHeading = heading;
      });
    });
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
    // GPS heading seulement si le magnétomètre web n'est pas actif
    if (!_compassPermissionGranted) {
      setState(() => _currentHeading = position.heading);
    }
    _updateWaypoint(newPos);
    _updateSpeed();
  }

  void _updateSpeed() {
    final now = DateTime.now();
    _lastSpeedUpdate ??= now;
    if (now.difference(_lastSpeedUpdate!).inMinutes >= 5) {
      final distDelta = _completedDistance - _distanceAtLastSpeedUpdate;
      final timeDeltaH = now.difference(_lastSpeedUpdate!).inSeconds / 3600.0;
      if (timeDeltaH > 0 && distDelta > 20) {
        final speed = (distDelta / 1000) / timeDeltaH;
        if (speed >= 0.5 && speed <= 15) {
          setState(() => _walkingSpeedKmh = speed);
        }
      }
      _lastSpeedUpdate = now;
      _distanceAtLastSpeedUpdate = _completedDistance;
    }
  }

  String _formatRemaining(double effectiveCompleted) {
    final remainingKm = (_totalDistance - effectiveCompleted) / 1000;
    if (remainingKm <= 0) return '0 min';
    final minutes = (remainingKm / _walkingSpeedKmh * 60).round();
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '${h}h$m';
  }

  void _updateWaypoint(LatLng currentPos) {
    if (_currentWaypointIndex >= widget.parcours.length) return;
    final nextWaypoint = widget.parcours[_currentWaypointIndex];
    final distance = const Distance().as(LengthUnit.Meter, currentPos, nextWaypoint);
    final segLen = const Distance().as(
      LengthUnit.Meter,
      widget.parcours[_currentWaypointIndex - 1],
      widget.parcours[_currentWaypointIndex],
    );
    setState(() {
      _distanceToNext = distance;
      _bearingToNext = _calculateBearing(currentPos, nextWaypoint);
      _currentSegmentLength = segLen;
    });
    if (distance < 20) {
      setState(() {
        _completedDistance += segLen;
        _currentSegmentLength = 0;
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
    final effectiveCompleted = _completedDistance +
        (_currentSegmentLength - _distanceToNext).clamp(0.0, _currentSegmentLength);
    final progress = _totalDistance > 0 ? (effectiveCompleted / _totalDistance).clamp(0.0, 1.0) : 0.0;
    final relativeBearing = _bearingToNext - _currentHeading;
    final normalizedBearing = ((relativeBearing + 180) % 360) - 180;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(progress),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            final compassSize = (constraints.maxHeight * 0.62).clamp(160.0, 270.0);
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
                if (!_compassPermissionGranted) ...[
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, _) => GestureDetector(
                      onTap: _activateCompass,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Color.fromRGBO(61, 61, 61, 1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Color.fromRGBO(255, 107, 53, _pulseAnim.value), width: 1.5),
                          boxShadow: [BoxShadow(
                            color: Color.fromRGBO(255, 107, 53, _pulseAnim.value * 0.5),
                            blurRadius: 8, spreadRadius: 1,
                          )],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.explore, color: Color.fromRGBO(255, 107, 53, _pulseAnim.value), size: 16),
                          const SizedBox(width: 6),
                          Text('Activer la boussole', style: TextStyle(color: Color.fromRGBO(255, 107, 53, _pulseAnim.value), fontSize: 13)),
                        ]),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _buildLegend(),
                const SizedBox(height: 8),
                _buildDistanceCard(normalizedBearing, effectiveCompleted),
              ],
            );
          })),
          const SizedBox(height: 8),
          _buildBottomStats(progress, effectiveCompleted),
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
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.navigation_rounded, color: Color(0xFFFF6B35), size: 15),
            const SizedBox(width: 6),
            const Text('Destination',
                style: TextStyle(color: Color(0xFFFF6B35), fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          if (widget.windDeg != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              CustomPaint(
                size: const Size(15, 15),
                painter: _MiniWindZonePainter(const Color(0xFF4CAF50)),
              ),
              const SizedBox(width: 6),
              const Text('Face au vent',
                  style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
        ],
      ),
    );
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

  Widget _buildDistanceCard(double normalizedBearing, double effectiveCompleted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
      ),
      child: Column(children: [
        Text('${_distanceToNext.round()} m', style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(_getDirectionText(normalizedBearing), style: const TextStyle(color: Colors.white70, fontSize: 16)),
      ]),
    );
  }

  Widget _buildBottomStats(double progress, double effectiveCompleted) {
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
          _stat('Distance totale', '${(_totalDistance / 1000).toStringAsFixed(1)} km', Icons.straighten),
          _stat('Restant', '${((_totalDistance - effectiveCompleted) / 1000).toStringAsFixed(1)} km', Icons.timeline),
          _stat('Temps est.', _formatRemaining(effectiveCompleted), Icons.timer_outlined),
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

class _MiniWindZonePainter extends CustomPainter {
  final Color color;
  const _MiniWindZonePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;
    final paint = Paint()..color = color.withOpacity(0.8)..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(cx, cy)
      ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: r),
          -pi * 5 / 6, pi * 2 / 3, false)
      ..close();
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(_MiniWindZonePainter old) => old.color != color;
}
