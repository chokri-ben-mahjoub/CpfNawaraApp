import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/app_strings.dart' show currentAppName;
import 'qr_links.dart';

/// Une étiquette à coller sur le terrain.
class QrLabel {
  final QrKind kind;
  final String id;
  final String title;
  final String subtitle;
  const QrLabel({required this.kind, required this.id, required this.title, this.subtitle = ''});
}

/// Planche d'étiquettes QR (A4, 3 colonnes) : on scanne l'étiquette sur place
/// et l'app ouvre directement le puits, le point ou l'article.
Future<Uint8List> buildQrLabelsPdf({
  required List<QrLabel> labels,
  required String title,
  required String Function(QrKind) kindLabel,
}) async {
  final doc = pw.Document(title: title, author: currentAppName);
  const navy = PdfColor.fromInt(0xFF0B1E2D);
  const grey = PdfColor.fromInt(0xFF757575);

  pw.Widget cell(QrLabel l) => pw.Container(
    width: 165,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(kindLabel(l.kind).toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: grey)),
        pw.SizedBox(height: 4),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
          data: qrPayload(l.kind, l.id),
          width: 96,
          height: 96,
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          l.title,
          textAlign: pw.TextAlign.center,
          maxLines: 2,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: navy),
        ),
        if (l.subtitle.isNotEmpty)
          pw.Text(
            l.subtitle,
            textAlign: pw.TextAlign.center,
            maxLines: 1,
            style: const pw.TextStyle(fontSize: 8, color: grey),
          ),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Text(
          '$currentAppName - $title',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: navy),
        ),
      ),
      build: (context) => [
        pw.Wrap(spacing: 10, runSpacing: 10, children: [for (final l in labels) cell(l)]),
      ],
    ),
  );
  return doc.save();
}
