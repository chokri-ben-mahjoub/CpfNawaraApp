import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Côté de la photo de profil enregistrée (pixels).
const profilePhotoSize = 320;

/// Redresse, recadre au centre en carré et réduit une photo de profil
/// (JPEG d'environ 20 à 40 Ko). `null` si le fichier n'est pas une image
/// lisible. Fonction de premier niveau : appelable avec `compute`.
Uint8List? compressProfilePhoto(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null; // fichier abîmé ou format inconnu
  }
  if (decoded == null) return null;
  final source = img.bakeOrientation(decoded);
  final side = source.width < source.height ? source.width : source.height;
  final square = img.copyCrop(
    source,
    x: (source.width - side) ~/ 2,
    y: (source.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final resized = side <= profilePhotoSize
      ? square
      : img.copyResize(
          square,
          width: profilePhotoSize,
          height: profilePhotoSize,
          interpolation: img.Interpolation.average,
        );
  return img.encodeJpg(resized, quality: 82);
}
