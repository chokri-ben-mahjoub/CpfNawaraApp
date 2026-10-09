import 'saved_download.dart';

Future<SavedDownload> saveLocally({
  required String fileName,
  required String mimeType,
  required List<int> bytes,
  String? subFolder,
  bool overwrite = false,
}) =>
    throw UnsupportedError('saveLocally');

Future<bool> openLocally(SavedDownload file) async => false;
