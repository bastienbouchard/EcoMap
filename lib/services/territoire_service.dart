import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const _functionUrl =
    'https://us-central1-moosesense-a84cf.cloudfunctions.net/get_ecoforestier';

class TerritoireService {
  static Future<String> _territoirePath(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/territoires/$id.geojson';
  }

  static Future<List<Map<String, dynamic>>> listTerritoires() async {
    if (kIsWeb) return [];
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/territoires');
    if (!folder.existsSync()) return [];
    return folder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.geojson'))
        .map((f) {
          final nom = f.path.split('/').last.replaceAll('.geojson', '');
          final size = (f.lengthSync() / 1024 / 1024);
          return {'id': nom, 'taille_mb': size.toStringAsFixed(1)};
        })
        .toList();
  }

  static Future<Map<String, dynamic>?> loadTerritoire(String id) async {
    if (kIsWeb) return null;
    final path = await _territoirePath(id);
    final file = File(path);
    if (!file.existsSync()) return null;
    return json.decode(await file.readAsString());
  }

  static Future<void> downloadTerritoire({
    required String nom,
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('Connexion au serveur...');

    final uri = Uri.parse(_functionUrl).replace(queryParameters: {
      'min_lat': minLat.toString(),
      'min_lon': minLon.toString(),
      'max_lat': maxLat.toString(),
      'max_lon': maxLon.toString(),
    });

    onStatus?.call('Téléchargement des polygones forestiers...');
    final resp = await http.get(uri).timeout(const Duration(minutes: 10));

    if (resp.statusCode != 200) {
      throw Exception('Erreur serveur: ${resp.statusCode}');
    }

    onStatus?.call('Sauvegarde locale...');
    final path = await _territoirePath(nom);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(resp.body);
    onStatus?.call('Terminé !');
  }

  static Future<void> deleteTerritoire(String id) async {
    if (kIsWeb) return;
    final path = await _territoirePath(id);
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}
