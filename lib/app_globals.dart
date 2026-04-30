import 'package:sqflite/sqflite.dart';

late Database db;
late Map<String, dynamic> geoJson;
int mbtilesMinZoom = 8;
int mbtilesMaxZoom = 16;
