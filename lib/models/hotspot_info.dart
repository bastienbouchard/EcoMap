import 'package:latlong2/latlong.dart';

class HotspotInfo {
  final LatLng position;
  final int score;
  final Map props;

  const HotspotInfo({
    required this.position,
    required this.score,
    required this.props,
  });
}
