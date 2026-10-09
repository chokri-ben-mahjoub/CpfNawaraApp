import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../platform/app_platform.dart';

/// Fichier généré en mémoire, à partager.
class ShareableFile {
  final String name;
  final String mimeType;
  final List<int> bytes;
  const ShareableFile(this.name, this.mimeType, this.bytes);
}

/// Ouvre le volet de partage natif (WhatsApp, e-mail, Drive...) — sur le web,
/// le partage du navigateur quand il existe.
Future<ShareResult> shareFiles(List<ShareableFile> files, {String? subject}) async {
  final xFiles = <XFile>[];
  if (isWeb) {
    for (final f in files) {
      xFiles.add(XFile.fromData(Uint8List.fromList(f.bytes), name: f.name, mimeType: f.mimeType));
    }
  } else {
    final dir = await getTemporaryDirectory();
    for (final f in files) {
      final path = '${dir.path}/${f.name}';
      await File(path).writeAsBytes(f.bytes, flush: true);
      xFiles.add(XFile(path, mimeType: f.mimeType));
    }
  }
  return Share.shareXFiles(xFiles, subject: subject);
}
