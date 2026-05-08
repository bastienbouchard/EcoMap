import 'dart:async';
import 'dart:js' as js;
import 'dart:typed_data';

Future<String> decompressGzip(List<int> bytes) {
  final completer = Completer<String>();
  final uint8 = Uint8List.fromList(bytes);
  js.context.callMethod('ecoMapDecompressGzip', [
    uint8,
    js.allowInterop((String result) => completer.complete(result)),
    js.allowInterop((dynamic err) => completer.completeError('gzip: $err')),
  ]);
  return completer.future;
}
