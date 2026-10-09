import 'package:flutter/services.dart';

import '../platform/app_platform.dart';
import 'local_file_saver.dart';
import 'saved_download.dart';

export 'saved_download.dart';

/// Enregistre un fichier directement sur l'appareil, sans passer par le
/// volet de partage :
/// - Android : Téléchargements/PuitsTrack via le canal "puitstrack/downloads"
///   (`android/.../MainActivity.kt`, MediaStore) ;
/// - PC : dossier Téléchargements\PuitsTrack de l'utilisateur ;
/// - web : téléchargement classique du navigateur.
/// Sur iOS, l'appelant retombe sur le volet de partage ("Enregistrer dans
/// Fichiers").
class DownloadSaver {
  static const _channel = MethodChannel('puitstrack/downloads');

  static bool get isSupported => debugForceSupported ?? (isAndroid || isDesktop || isWeb);

  /// Permet aux tests de rendu d'afficher le bouton "Télécharger" quelle que
  /// soit la plateforme de test.
  static bool? debugForceSupported;

  /// Sauvegarde automatique silencieuse possible (pas dans un navigateur, où
  /// chaque fichier déclencherait un téléchargement à l'ouverture de l'app).
  static bool get supportsAutoBackup => debugForceSupported ?? (isAndroid || isDesktop);

  /// Écran protégé (FLAG_SECURE) : Android uniquement.
  static bool get supportsSecureScreen => debugForceSupported ?? isAndroid;

  /// Le fichier enregistré peut être ouvert depuis l'app (bouton "Ouvrir") ;
  /// sur le web, le navigateur s'en charge lui-même.
  static bool get canOpen => isAndroid || isDesktop;

  /// [subFolder] : sous-dossier de Téléchargements/PuitsTrack (ex:
  /// "Sauvegardes"). [overwrite] remplace un fichier du même nom déjà créé
  /// par l'app. [requestPermission] = false : n'affiche jamais de demande
  /// d'autorisation (Android 9 et moins), l'appel échoue à la place.
  static Future<SavedDownload> save({
    required String fileName,
    required String mimeType,
    required List<int> bytes,
    String? subFolder,
    bool overwrite = false,
    bool requestPermission = true,
  }) async {
    if (!isAndroid) {
      return saveLocally(
        fileName: fileName,
        mimeType: mimeType,
        bytes: bytes,
        subFolder: subFolder,
        overwrite: overwrite,
      );
    }
    final result = await _channel.invokeMapMethod<String, dynamic>('saveToDownloads', {
      'name': fileName,
      'mime': mimeType,
      'bytes': Uint8List.fromList(bytes),
      'subFolder': subFolder,
      'overwrite': overwrite,
      'requestPermission': requestPermission,
    });
    return SavedDownload(
      fileName: fileName,
      uri: result!['uri'] as String,
      folder: result['folder'] as String? ?? 'Download',
      mimeType: mimeType,
    );
  }

  /// Ouvre le fichier avec l'application adaptée (Excel, Sheets, WPS...).
  /// Retourne `false` si aucune application installée ne sait l'ouvrir.
  static Future<bool> open(SavedDownload file) async {
    if (!isAndroid) return openLocally(file);
    final opened = await _channel.invokeMethod<bool>('openFile', {'uri': file.uri, 'mime': file.mimeType});
    return opened ?? false;
  }

  /// Active/désactive l'écran protégé (pas de capture d'écran, contenu masqué
  /// dans les applications récentes). Sans effet hors Android.
  static Future<void> setSecureScreen(bool secure) async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('setSecure', {'secure': secure});
    } on PlatformException {
      // Best-effort : un échec ne doit pas bloquer l'app.
    }
  }
}
