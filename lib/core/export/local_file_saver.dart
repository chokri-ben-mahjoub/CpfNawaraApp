// Enregistrement "local" d'un fichier : dossier Téléchargements sur PC,
// téléchargement par le navigateur sur le web.
export 'local_file_saver_stub.dart'
    if (dart.library.io) 'local_file_saver_io.dart'
    if (dart.library.js_interop) 'local_file_saver_web.dart';
