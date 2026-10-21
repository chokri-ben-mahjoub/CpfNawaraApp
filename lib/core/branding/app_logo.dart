import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

/// Côté maximal du logo enregistré (pixels) : largement suffisant pour un
/// en-tête de PDF ou un bandeau d'écran, tout en restant léger à stocker.
const logoMaxSide = 480;

/// Logo prêt à enregistrer (PNG, transparence conservée — contrairement aux
/// photos de profil ou de schéma, un logo a souvent un fond transparent).
class LogoImage {
  final Uint8List bytes;
  final int width;
  final int height;
  const LogoImage(this.bytes, this.width, this.height);
}

/// Redresse, réduit et ré-encode en PNG un logo importé (JPEG, PNG ou ICO).
/// `null` si le fichier n'est pas une image lisible. Fonction de premier
/// niveau : appelable avec `compute` (hors du fil de l'interface).
LogoImage? compressLogo(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null; // fichier abîmé ou format inconnu
  }
  if (decoded == null) return null;
  final source = img.bakeOrientation(decoded);
  final longest = source.width > source.height ? source.width : source.height;
  final resized = longest <= logoMaxSide
      ? source
      : source.width >= source.height
      ? img.copyResize(source, width: logoMaxSide, interpolation: img.Interpolation.average)
      : img.copyResize(source, height: logoMaxSide, interpolation: img.Interpolation.average);
  return LogoImage(Uint8List.fromList(img.encodePng(resized)), resized.width, resized.height);
}

const _logoKey = 'custom_app_logo_png_b64';

/// Logo personnalisé actuellement configuré (PNG), ou `null` si aucun.
/// Variable globale simple (même principe que `currentAppName` dans
/// `app_strings.dart`) : utilisée par les exports PDF, du code non-widget
/// qui n'a pas de `ref` sous la main.
Uint8List? currentAppLogo;

/// Clé du logo partagé dans la configuration d'équipe (`app_config`,
/// synchronisée) : tous les appareils de l'entreprise l'utilisent dans leurs
/// PDF, sans devoir le configurer un par un.
const companyLogoKey = 'company_logo_b64';

Uint8List? _localLogo;
Uint8List? _sharedLogo;

/// Le logo de l'appareil (Réglages) prime sur celui de l'équipe.
void _refreshEffectiveLogo() => currentAppLogo = _localLogo ?? _sharedLogo;

/// PNG décodé d'une valeur `app_config`, ou `null` (absent ou vide).
Uint8List? decodeSharedLogo(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return base64Decode(value);
  } catch (_) {
    return null;
  }
}

/// Appelé quand la configuration d'équipe est (re)lue.
void applySharedLogo(Uint8List? bytes) {
  _sharedLogo = bytes;
  _refreshEffectiveLogo();
}

/// Permet d'ajouter/retirer le logo depuis Réglages › Apparence, affiché
/// dans les rapports PDF générés par l'app (voir `pdf_table_exporter.dart`
/// et `plant_report.dart`) : stocké sur l'appareil, pris en compte
/// immédiatement.
class AppLogoController extends StateNotifier<Uint8List?> {
  AppLogoController() : super(null);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_logoKey);
    final bytes = saved == null || saved.isEmpty ? null : base64Decode(saved);
    state = bytes;
    _localLogo = bytes;
    _refreshEffectiveLogo();
  }

  /// `null` retire le logo (retour au rendu sans logo).
  Future<void> setLogo(Uint8List? pngBytes) async {
    state = pngBytes;
    _localLogo = pngBytes;
    _refreshEffectiveLogo();
    final prefs = await SharedPreferences.getInstance();
    if (pngBytes == null) {
      await prefs.remove(_logoKey);
    } else {
      await prefs.setString(_logoKey, base64Encode(pngBytes));
    }
  }
}

final appLogoProvider = StateNotifierProvider<AppLogoController, Uint8List?>((ref) => AppLogoController());
