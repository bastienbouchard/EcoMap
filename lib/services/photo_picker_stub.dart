import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

Future<Uint8List?> pickPhoto() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 60,
    maxWidth: 900,
  );
  if (picked == null) return null;
  return picked.readAsBytes();
}
