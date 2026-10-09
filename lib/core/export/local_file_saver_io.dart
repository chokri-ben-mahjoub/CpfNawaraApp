import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'saved_download.dart';

/// PC : enregistre dans Téléchargements\PuitsTrack[\sous-dossier].
Future<SavedDownload> saveLocally({
  required String fileName,
  required String mimeType,
  required List<int> bytes,
  String? subFolder,
  bool overwrite = false,
}) async {
  final downloads = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final folder = Directory(p.joinAll([downloads.path, 'PuitsTrack', ?subFolder]));
  await folder.create(recursive: true);
  var file = File(p.join(folder.path, fileName));
  if (!overwrite) {
    // Comme un navigateur : "nom (1).xlsx" plutôt qu'écraser un fichier.
    final base = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    for (var i = 1; await file.exists(); i++) {
      file = File(p.join(folder.path, '$base ($i)$ext'));
    }
  }
  await file.writeAsBytes(bytes, flush: true);
  return SavedDownload(fileName: p.basename(file.path), uri: file.path, folder: folder.path, mimeType: mimeType);
}

/// Ouvre le fichier avec l'application associée (Excel, LibreOffice...).
Future<bool> openLocally(SavedDownload file) async {
  if (Platform.isWindows) {
    // explorer.exe renvoie 1 même en cas de succès : seul l'échec de
    // lancement (exception) compte.
    await Process.run('explorer.exe', [file.uri]);
    return true;
  }
  final result = await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [file.uri]);
  return result.exitCode == 0;
}
