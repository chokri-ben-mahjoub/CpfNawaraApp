import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'saved_download.dart';

/// Navigateur : déclenche un téléchargement classique (dossier
/// Téléchargements du navigateur). [subFolder] et [overwrite] n'ont pas de
/// sens ici.
Future<SavedDownload> saveLocally({
  required String fileName,
  required String mimeType,
  required List<int> bytes,
  String? subFolder,
  bool overwrite = false,
}) async {
  final blob = web.Blob([Uint8List.fromList(bytes).toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Laisse le temps au navigateur de lire le fichier avant de libérer l'URL.
  Future<void>.delayed(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  return SavedDownload(fileName: fileName, uri: url, folder: '', mimeType: mimeType);
}

/// Le navigateur gère lui-même l'ouverture (barre de téléchargements).
Future<bool> openLocally(SavedDownload file) async => false;
