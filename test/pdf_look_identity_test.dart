import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:puitstrack/core/qr/qr_labels_pdf.dart';
import 'package:puitstrack/core/qr/qr_links.dart';
import 'package:puitstrack/core/export/export_table.dart';
import 'package:puitstrack/core/export/pdf_export_settings.dart';
import 'package:puitstrack/core/export/pdf_table_exporter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:puitstrack/core/export/pdf_style.dart';
import 'package:puitstrack/core/export/pdf_style_set.dart';

const _headers = ['Point', 'pH', 'Valeur'];
const _data = [
  ['A', '7.1', '12'],
  ['B', '6.9', '15'],
];

/// Tableau tel que construit avant la personnalisation fine (référence).
pw.Widget _legacy(PdfExportSettings cfg, double fontSize) {
  final accent = PdfColor.fromInt(cfg.accentArgb);
  final header = PdfColor.fromInt(cfg.headerArgb);
  final filled = cfg.tableStyle == 0 || cfg.tableStyle == 2;
  const grey = PdfColor.fromInt(0xFFBDBDBD);
  const pad = pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5);
  return pw.TableHelper.fromTextArray(
    headers: _headers,
    data: _data,
    headerStyle: pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: fontSize,
      color: filled ? PdfColors.white : header,
    ),
    headerDecoration: filled
        ? pw.BoxDecoration(color: header)
        : (cfg.tableStyle == 3
              ? null
              : pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: accent, width: 1.4)))),
    headerPadding: pad,
    cellStyle: pw.TextStyle(fontSize: fontSize),
    cellPadding: pad,
    cellAlignment: pw.Alignment.centerLeft,
    border: cfg.tableStyle == 1
        ? const pw.TableBorder(horizontalInside: pw.BorderSide(color: grey, width: 0.5))
        : pw.TableBorder.all(color: grey, width: 0.5),
    oddRowDecoration: cfg.tableStyle == 2
        ? pw.BoxDecoration(color: PdfColor.fromInt((cfg.accentArgb & 0x00FFFFFF) | 0x14000000))
        : null,
  );
}

Future<String> _render(pw.Widget w) async {
  final doc = pw.Document(compress: false);
  doc.addPage(pw.Page(build: (_) => w));
  final raw = latin1.decode(await doc.save());
  // Horodatage et identifiant du document : seuls éléments non déterministes.
  return raw.replaceAll(RegExp(r'/CreationDate\s*\([^)]*\)'), '').replaceAll(RegExp(r'/ID\s*\[[^\]]*\]'), '');
}

void main() {
  for (final style in [0, 1, 2, 3]) {
    test('style de tableau $style : rendu par défaut identique à l\'historique', () async {
      final cfg = PdfExportSettings(tableStyle: style);
      final fresh = PdfLook(cfg).table(headers: _headers, data: _data, fontSize: 8.5);
      expect(await _render(fresh), await _render(_legacy(cfg, 8.5)));
    });
  }

  test('titres : rendu par défaut identique, personnalisé différent', () async {
    final look = PdfLook(PdfExportSettings());
    const navy = PdfColor.fromInt(0xFF0B1E2D);
    final legacy = pw.Text('Rapport', style: pw.TextStyle(fontSize: 16 * 1.15, fontWeight: pw.FontWeight.bold, color: navy));
    final fresh = look.title('Rapport', PdfStyleSet.defaults.reportTitle, size: 16, color: navy, scale: 1.15);
    expect(await _render(fresh), await _render(legacy));
    final custom = look.title(
      'Rapport',
      const PdfTextStyleSpec(size: 20, align: PdfTextAlign.center, family: PdfFontFamily.times),
      size: 16,
      color: navy,
    );
    expect(await _render(custom), isNot(await _render(legacy)));
  });

  test('PdfTableExporter génère un PDF avec style par défaut et personnalisé', () async {
    SharedPreferences.setMockInitialValues({});
    const t = [ExportTable(name: 'Alertes', headers: ['A', 'B'], rows: [['x', 1]])];
    final a = await PdfTableExporter.encode(t, title: 'Test');
    expect(a.length, greaterThan(500));
    await PdfExportSettings().copyWith(
      style: const PdfStyleSet(
        reportTitle: PdfTextStyleSpec(size: 24, bold: true, align: PdfTextAlign.center),
        tableTitle: PdfTextStyleSpec(size: 14, italic: true),
        table: PdfTableStyleSpec(spaceBeforeTable: 30, spaceAfterTitle: 12),
      ),
    ).save();
    final b = await PdfTableExporter.encode(t, title: 'Test');
    expect(b.length, isNot(a.length));
  });

  test('aperçu : les réglages passés (non enregistrés) priment sur les enregistrés', () async {
    SharedPreferences.setMockInitialValues({});
    const t = [ExportTable(name: 'T', headers: ['A'], rows: [['x']])];
    final saved = await PdfTableExporter.encode(t, title: 'P');
    final override = await PdfTableExporter.encode(
      t,
      title: 'P',
      settings: PdfExportSettings().copyWith(
        style: const PdfStyleSet(tableTitle: PdfTextStyleSpec(family: PdfFontFamily.courier, size: 20)),
      ),
    );
    expect(override.length, isNot(saved.length));
    // Rien n'a été enregistré par l'aperçu.
    expect((await PdfExportSettings.load()).style.isDefault, isTrue);
  });

  test('planche QR : titre suit le style personnalisé', () async {
    SharedPreferences.setMockInitialValues({});
    Future<int> size() async => (await buildQrLabelsPdf(
      labels: const [QrLabel(kind: QrKind.well, id: 'w1', title: 'Puits 1')],
      title: 'Etiquettes',
      kindLabel: (k) => k.name,
    )).length;
    final before = await size();
    await PdfExportSettings.applyStyleToAll(
      const PdfStyleSet(reportTitle: PdfTextStyleSpec(family: PdfFontFamily.courier, size: 20, bold: true)),
    );
    expect(await size(), isNot(before));
  });

  test('un style personnalisé change le rendu', () async {
    final base = PdfExportSettings();
    final custom = base.copyWith(
      style: const PdfStyleSet(
        columnHeader: PdfTextStyleSpec(family: PdfFontFamily.courier, bold: true, size: 11),
        table: PdfTableStyleSpec(headerBgArgb: 0xFF112233, borderWidth: 2),
      ),
    );
    final a = await _render(PdfLook(base).table(headers: _headers, data: _data, fontSize: 8.5));
    final b = await _render(PdfLook(custom).table(headers: _headers, data: _data, fontSize: 8.5));
    expect(b, isNot(a));
  });
}
