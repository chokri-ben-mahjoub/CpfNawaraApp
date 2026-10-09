import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Génère un fichier CSV (séparateur `;`, compatible Excel FR) à partir
/// d'en-têtes + lignes de texte, puis ouvre le volet de partage natif.
class CsvExporter {
  static Future<void> exportAndShare({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
    String? shareSubject,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_escape).join(';'));
    for (final row in rows) {
      buffer.writeln(row.map(_escape).join(';'));
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    // BOM UTF-8 : évite les caractères accentués mal affichés à l'ouverture
    // dans Excel.
    final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(buffer.toString())];
    await File(path).writeAsBytes(bytes, flush: true);

    await Share.shareXFiles([XFile(path)], subject: shareSubject ?? fileName);
  }

  static String _escape(String value) {
    if (value.contains(';') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
