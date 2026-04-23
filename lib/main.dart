import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'app_globals.dart';
import 'screens/map_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initMBTiles();
  await _loadGeoJson();
  runApp(const EcoMapApp());
}

Future<void> _initMBTiles() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = '${dir.path}/eco.mbtiles';
  final data = await rootBundle.load('assets/tiles/eco.mbtiles');
  final bytes = data.buffer.asUint8List();
  await File(dbPath).writeAsBytes(bytes);
  db = await openDatabase(dbPath, readOnly: true);
}

Future<void> _loadGeoJson() async {
  final str = await rootBundle.loadString('assets/eco_zone.geojson');
  geoJson = json.decode(str) as Map<String, dynamic>;
}

class EcoMapApp extends StatelessWidget {
  const EcoMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFFF6B35),
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFFF6B35),
          secondary: const Color(0xFF8B4513),
        ),
      ),
      home: const MapPage(),
    );
  }
}
