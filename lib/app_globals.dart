import 'package:sqflite/sqflite.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

Database? db;
late Map<String, dynamic> geoJson;
int mbtilesMinZoom = 8;
int mbtilesMaxZoom = 16;
CacheOptions? tileCache;
