/// Fichier enregistré sur l'appareil (Téléchargements), ou téléchargé par le
/// navigateur.
class SavedDownload {
  final String fileName;

  /// URI Android (content://), chemin du fichier sur PC, URL blob sur le web.
  final String uri;

  /// Dossier affiché à l'utilisateur.
  final String folder;
  final String mimeType;

  const SavedDownload({required this.fileName, required this.uri, required this.folder, required this.mimeType});
}
