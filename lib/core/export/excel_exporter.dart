import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Génère un classeur Excel (.xlsx) à partir d'en-têtes + lignes de texte,
/// puis ouvre le volet de partage natif (enregistrer, envoyer par mail...).
///
/// Le fichier est écrit dans le dossier temporaire de l'app : il n'a pas
/// vocation à être relu par l'app elle-même, seulement partagé une fois créé.
class ExcelExporter {
  static Future<void> exportAndShare({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
    String? shareSubject,
  }) async {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet()!;
    final sheet = excel[sheetName];

    sheet.appendRow(headers.map<CellValue?>((h) => TextCellValue(h)).toList());
    for (final row in rows) {
      sheet.appendRow(row.map<CellValue?>((v) => TextCellValue(v)).toList());
    }

    final bytes = excel.encode();
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    await File(path).writeAsBytes(bytes, flush: true);

    await Share.shareXFiles([XFile(path)], subject: shareSubject ?? fileName);
  }
}
