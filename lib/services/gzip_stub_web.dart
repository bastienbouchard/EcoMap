import 'dart:js_util' as js_util;
import 'dart:typed_data';

Future<String> decompressGzip(List<int> bytes) {
  final uint8 = Uint8List.fromList(bytes);
  final promise = js_util.callMethod(
    js_util.globalThis,
    'ecoMapDecompressGzip',
    [uint8],
  );
  return js_util.promiseToFuture<String>(promise);
}
