import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const _roadsUrl =
    'https://pub-5c51ef289e6943dbb647c2a2d1baa3bf.r2.dev/chemins/chemins_prov.geojson.gz';

class RoadSegment {
  final String cl;
  final List<List<double>> points; // chaque élément: [lat, lon]
  const RoadSegment({required this.cl, required this.points});
}

class RoadService {
  static Future<String> _localPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/chemins/chemins_prov.geojson.gz';
  }

  static Future<bool> isDownloaded() async {
    final path = await _localPath();
    return File(path).existsSync();
  }

  static Future<void> download({void Function(String)? onStatus}) async {
    onStatus?.call('Téléchargement des chemins forestiers...');
    final resp = await http
        .get(Uri.parse(_roadsUrl))
        .timeout(const Duration(seconds: 120));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final path = await _localPath();
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(resp.bodyBytes);
    onStatus?.call('Chemins forestiers téléchargés');
  }

  static Future<void> delete() async {
    final path = await _localPath();
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  static Future<List<RoadSegment>> loadSegments() async {
    final path = await _localPath();
    final file = File(path);
    if (!file.existsSync()) return [];
    final bytes = await file.readAsBytes();
    final raw = await compute(_parseRoads, bytes);
    return raw.map((item) {
      final list = item as List;
      final cl = list[0] as String;
      final pts = (list[1] as List).map((p) {
        final pair = p as List;
        return [pair[0] as double, pair[1] as double];
      }).toList();
      return RoadSegment(cl: cl, points: pts);
    }).toList();
  }

  static List<dynamic> _parseRoads(Uint8List bytes) {
    String jsonStr;
    try {
      jsonStr = utf8.decode(GZipCodec().decode(bytes));
    } catch (_) {
      jsonStr = utf8.decode(bytes);
    }

    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final features = data['features'] as List;
    final result = <dynamic>[];

    void addLine(List line, String cl) {
      if (line.length < 2) return;
      final pts = line.map((c) {
        final p = c as List;
        return <double>[p[1].toDouble(), p[0].toDouble()];
      }).toList();
      result.add([cl, pts]);
    }

    for (final feat in features) {
      final geom = feat['geometry'];
      if (geom == null) continue;
      final props = feat['properties'] as Map<String, dynamic>;
      final cl = (props['cl'] as String?) ?? '05';
      final type = geom['type'] as String;
      final coords = geom['coordinates'] as List;

      if (type == 'MultiLineString') {
        for (final line in coords) addLine(line as List, cl);
      } else if (type == 'LineString') {
        addLine(coords, cl);
      }
    }
    return result;
  }
}
