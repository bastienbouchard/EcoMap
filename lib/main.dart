import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'app_globals.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/connectivity_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); } catch (_) {}
  try { await AuthService.restoreSession(); } catch (_) {}
  try { await ConnectivityService.init(); } catch (_) {}
  if (!kIsWeb) try { await _initTileCache(); } catch (_) {}
  if (!kIsWeb) try { await _initMBTiles(); } catch (_) {}
  try { await _loadGeoJson(); } catch (_) {}
  runApp(const EcoMapApp());
}

Future<void> _initTileCache() async {
  final dir = await getApplicationDocumentsDirectory();
  tileCache = CacheOptions(
    store: FileCacheStore('${dir.path}/tile_cache'),
    policy: CachePolicy.request,
    maxStale: const Duration(days: 30),
    hitCacheOnErrorExcept: [],
  );
}

Future<void> _initMBTiles() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = '${dir.path}/eco.mbtiles';
  if (!File(dbPath).existsSync()) {
    final data = await rootBundle.load('assets/tiles/eco.mbtiles');
    await File(dbPath).writeAsBytes(data.buffer.asUint8List());
  }
  db = await openDatabase(dbPath, readOnly: true);
  try {
    final minR = await db?.rawQuery("SELECT value FROM metadata WHERE name='minzoom'") ?? [];
    final maxR = await db?.rawQuery("SELECT value FROM metadata WHERE name='maxzoom'") ?? [];
    if (minR.isNotEmpty) mbtilesMinZoom = int.parse(minR.first['value'] as String);
    if (maxR.isNotEmpty) mbtilesMaxZoom = int.parse(maxR.first['value'] as String);
  } catch (_) {}
}

Map<String, dynamic> _decodeJson(String s) => json.decode(s) as Map<String, dynamic>;

Future<void> _loadGeoJson() async {
  geoJson = {'type': 'FeatureCollection', 'features': []};
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
      home: const SplashScreen(),
    );
  }
}
