import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

Future<Uint8List?> pickPhoto({bool fromCamera = false}) async {
  final picked = await ImagePicker().pickImage(
    source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    imageQuality: 60,
    maxWidth: 900,
  );
  if (picked == null) return null;
  return picked.readAsBytes();
}
