import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_export_settings.dart';

const _grey = PdfColor.fromInt(0xFF757575);
const _lineGrey = PdfColor.fromInt(0xFFBDBDBD);

/// Apparence commune des PDF d'après les réglages : couleurs de la palette,
/// style des tableaux (en-tête plein, filets, lignes alternées), marges et
/// filigrane. Utilisée par le rapport usine et par les exports de tableaux.
class PdfLook {
  final PdfExportSettings cfg;
  PdfLook(this.cfg);

  PdfColor get accent => PdfColor.fromInt(cfg.accentArgb);
  PdfColor get header => PdfColor.fromInt(cfg.headerArgb);

  /// Marges de la page, mises à l'échelle des réglages.
  pw.EdgeInsets margin(double left, double top) =>
      pw.EdgeInsets.symmetric(horizontal: left * cfg.marginScale, vertical: top * cfg.marginScale);

  /// Tableau de texte au style choisi.
  pw.Widget table({
    required List<String> headers,
    required List<List<Object>> data,
    required double fontSize,
    pw.EdgeInsets cellPadding = const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    pw.Alignment cellAlignment = pw.Alignment.centerLeft,
    Map<int, pw.Alignment>? cellAlignments,
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) {
    final filled = cfg.tableStyle != 1;
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: fontSize,
        color: filled ? PdfColors.white : header,
      ),
      headerDecoration: filled
          ? pw.BoxDecoration(color: header)
          : pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: accent, width: 1.4))),
      headerPadding: cellPadding,
      cellStyle: pw.TextStyle(fontSize: fontSize),
      cellPadding: cellPadding,
      cellAlignment: cellAlignment,
      cellAlignments: cellAlignments,
      columnWidths: columnWidths,
      border: cfg.tableStyle == 1
          ? const pw.TableBorder(horizontalInside: pw.BorderSide(color: _lineGrey, width: 0.5))
          : pw.TableBorder.all(color: _lineGrey, width: 0.5),
      oddRowDecoration: cfg.tableStyle == 2
          ? pw.BoxDecoration(color: PdfColor.fromInt((cfg.accentArgb & 0x00FFFFFF) | 0x14000000))
          : null,
    );
  }

  /// Fond de page : filigrane en diagonale, ou rien.
  pw.Widget Function(pw.Context)? get background {
    final text = cfg.watermark.trim();
    if (text.isEmpty) return null;
    return (context) => pw.FullPage(
      ignoreMargins: true,
      child: pw.Center(
        child: pw.Transform.rotate(
          angle: -0.62,
          child: pw.Opacity(
            opacity: 0.12,
            child: pw.Text(
              text.toUpperCase(),
              style: pw.TextStyle(fontSize: 64, fontWeight: pw.FontWeight.bold, color: _grey),
            ),
          ),
        ),
      ),
    );
  }
}
