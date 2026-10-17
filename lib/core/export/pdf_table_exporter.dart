import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'export_table.dart';

const _accent = PdfColor.fromInt(0xFFFF7A33);
const _navy = PdfColor.fromInt(0xFF0B1E2D);
const _grey = PdfColor.fromInt(0xFF757575);

/// Document PDF générique (une section tableau par [ExportTable]) : le
/// troisième format proposé par `chooseExport`, à côté d'Excel et CSV, pour
/// les exports déjà en place dans l'app (alertes, historique, stock...) —
/// voir `export_service.dart`.
///
/// Polices standard du PDF (Helvetica) : les caractères accentués français
/// sont pris en charge, pas les tirets longs ni ≤ / ≥ (remplacés).
class PdfTableExporter {
  static final _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  static Future<Uint8List> encode(List<ExportTable> tables, {required String title, String operatorName = ''}) async {
    final safeTitle = _safe(title);
    final doc = pw.Document(title: safeTitle, author: 'PuitsTrack');
    final generated = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Beaucoup de colonnes (analyses usine...) : texte plus petit et marge
    // réduite, sinon les en-têtes se retrouvent coupés lettre par lettre.
    final maxColumns = tables.isEmpty ? 0 : tables.map((t) => t.headers.length).reduce((a, b) => a > b ? a : b);
    final fontSize = maxColumns > 12
        ? 6.5
        : maxColumns > 8
            ? 7.5
            : 8.5;
    final cellPadding = maxColumns > 8
        ? const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4)
        : const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5);

    final sections = <pw.Widget>[];
    for (final table in tables) {
      sections.add(pw.SizedBox(height: 16));
      sections.add(
        pw.Text(_safe(table.name), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: _navy)),
      );
      sections.add(pw.SizedBox(height: 6));
      sections.add(
        pw.TableHelper.fromTextArray(
          headers: table.headers.map(_safe).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSize, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _navy),
          headerPadding: cellPadding,
          cellStyle: pw.TextStyle(fontSize: fontSize),
          cellPadding: cellPadding,
          cellAlignment: pw.Alignment.centerLeft,
          data: [for (final row in table.rows) row.map(_cell).toList()],
        ),
      );
    }

    // Paysage dès qu'un tableau a plus de 6 colonnes : largement plus de
    // place que le portrait pour que chaque en-tête tienne sur sa ligne.
    final pageFormat = maxColumns > 6 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(20, 24, 20, 24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                pw.Text('PuitsTrack', style: pw.TextStyle(color: _accent, fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Spacer(),
                pw.Text(safeTitle, style: const pw.TextStyle(color: _grey, fontSize: 9)),
              ],
            ),
            pw.Divider(color: _accent, thickness: 1.5),
          ],
        ),
        footer: (context) => pw.Row(
          children: [
            pw.Text(
              'Genere le $generated${operatorName.isEmpty ? '' : ' - ${_safe(operatorName)}'}',
              style: const pw.TextStyle(color: _grey, fontSize: 8),
            ),
            pw.Spacer(),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(color: _grey, fontSize: 8),
            ),
          ],
        ),
        build: (context) => [
          pw.Text(safeTitle, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _navy)),
          ...sections,
        ],
      ),
    );
    return doc.save();
  }

  static String _cell(Object? value) {
    if (value == null) return '';
    if (value is DateOnly) return _dateFormat.format(value.date);
    if (value is DateTime) return _dateTimeFormat.format(value);
    if (value is int) return value.toString();
    if (value is double) {
      if (value.isNaN || value.isInfinite) return '';
      return value == value.roundToDouble() && value.abs() < 1e15 ? value.toInt().toString() : value.toString();
    }
    return _safe(value.toString());
  }

  static String _safe(String text) => text
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('≤', '<=')
      .replaceAll('≥', '>=')
      .replaceAll('’', "'")
      .replaceAll('…', '...');
}
