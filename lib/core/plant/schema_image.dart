import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Image de fond d'un schéma, prête à enregistrer (JPEG en base64).
class SchemaImage {
  final String base64;
  final int width;
  final int height;
  const SchemaImage(this.base64, this.width, this.height);
}

/// Taille maximale de l'image encodée : le schéma est synchronisé comme un
/// document Firestore, limité à 1 Mo.
const schemaImageMaxBase64 = 700000;

/// Redresse, réduit et compresse une photo ou un scan de schéma (JPEG) pour
/// rester sous [schemaImageMaxBase64]. `null` si le fichier n'est pas une
/// image lisible ou reste trop lourd. Fonction de premier niveau : appelable
/// avec `compute` (hors du fil de l'interface).
SchemaImage? compressSchemaImage(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null; // fichier abîmé ou format inconnu
  }
  if (decoded == null) return null;
  var source = img.bakeOrientation(decoded);
  if (source.hasAlpha) {
    // Fond blanc sous les zones transparentes (le JPEG n'en a pas).
    final white = img.Image(width: source.width, height: source.height);
    img.fill(white, color: img.ColorRgb8(255, 255, 255));
    source = img.compositeImage(white, source);
  }
  for (final (maxSide, quality) in const [(1800, 82), (1600, 75), (1400, 68), (1200, 62), (1000, 55), (800, 50)]) {
    final longest = source.width > source.height ? source.width : source.height;
    final resized = longest <= maxSide
        ? source
        : source.width >= source.height
        ? img.copyResize(source, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(source, height: maxSide, interpolation: img.Interpolation.average);
    final encoded = base64Encode(img.encodeJpg(resized, quality: quality));
    if (encoded.length <= schemaImageMaxBase64) return SchemaImage(encoded, resized.width, resized.height);
  }
  return null;
}
