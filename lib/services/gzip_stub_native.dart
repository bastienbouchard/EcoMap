import 'dart:io';
import 'dart:convert';

Future<String> decompressGzip(List<int> bytes) async {
  return utf8.decode(gzip.decode(bytes));
}
