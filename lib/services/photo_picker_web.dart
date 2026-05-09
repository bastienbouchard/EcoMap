import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> pickPhoto() async {
  final completer = Completer<Uint8List?>();
  final input = html.FileUploadInputElement()..accept = 'image/*';
  input.click();
  input.onChange.listen((_) {
    final file = input.files?.first;
    if (file == null) { completer.complete(null); return; }
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    reader.onLoadEnd.listen((_) {
      completer.complete(reader.result as Uint8List?);
    });
  });
  return completer.future;
}
