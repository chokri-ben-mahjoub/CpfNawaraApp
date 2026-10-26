import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../branding/app_logo.dart';
import '../l10n/app_strings.dart';
import 'export_table.dart';
import 'pdf_chart.dart';
import 'pdf_export_settings.dart';
import 'pdf_style.dart';

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

  static Future<Uint8List> encode(
    List<ExportTable> tables, {
    required String title,
    String operatorName = '',
    List<PdfReportChart> charts = const [],
  }) async {
    final cfg = await PdfExportSettings.load();
    final look = PdfLook(cfg);
    final k = cfg.textScale;
    final safeTitle = _safe(title);
    final doc = pw.Document(title: safeTitle, author: currentAppName);
    final logo = currentAppLogo;
    final logoImage = logo == null || !cfg.showLogo ? null : pw.MemoryImage(logo);
    final generated = cfg.stamp();

    // Beaucoup de colonnes (analyses usine...) : texte plus petit et marge
    // réduite, sinon les en-têtes se retrouvent coupés lettre par lettre.
    final maxColumns = tables.isEmpty ? 0 : tables.map((t) => t.headers.length).reduce((a, b) => a > b ? a : b);
    final fontSize = maxColumns > 12
        ? 6.5 * k
        : maxColumns > 8
            ? 7.5 * k
            : 8.5 * k;
    final cellPadding = maxColumns > 8
        ? const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4)
        : const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5);

    final sections = <pw.Widget>[];
    final chartWidgets = <pw.Widget>[
      if (cfg.charts != PdfChartsPosition.hidden)
        for (final chart in charts) ...[pw.SizedBox(height: 16), buildPdfChartSection(chart)],
    ];
    if (cfg.charts == PdfChartsPosition.before) sections.addAll(chartWidgets);
    for (final table in tables) {
      sections.add(pw.SizedBox(height: 16));
      sections.add(
        pw.Text(_safe(table.name), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: _navy)),
      );
      sections.add(pw.SizedBox(height: 6));
      sections.add(
        look.table(
          headers: table.headers.map(_safe).toList(),
          data: [for (final row in table.rows) row.map(_cell).toList()],
          fontSize: fontSize,
          cellPadding: cellPadding,
        ),
      );
    }

    if (cfg.charts == PdfChartsPosition.after) sections.addAll(chartWidgets);

    // Paysage dès qu'un tableau a plus de 6 colonnes : largement plus de
    // place que le portrait pour que chaque en-tête tienne sur sa ligne.
    final pageFormat = switch (cfg.orientation) {
      PdfOrientation.portrait => PdfPageFormat.a4,
      PdfOrientation.landscape => PdfPageFormat.a4.landscape,
      PdfOrientation.auto => maxColumns > 6 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    };
    final dateText = '${(dataLanguage == 'en' ? 'Generated on' : 'Genere le')} $generated';
    final footerParts = [
      if (cfg.datePlacement == PdfDatePlacement.footer) dateText,
      if (cfg.showOperator && operatorName.isNotEmpty) _safe(operatorName),
      if (cfg.footerText.trim().isNotEmpty) _safe(cfg.footerText.trim()),
    ];

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: pageFormat,
          margin: look.margin(20, 24),
          buildBackground: look.background,
        ),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                if (logoImage != null) ...[pw.Image(logoImage, height: 20), pw.SizedBox(width: 8)],
                if (cfg.showAppName)
                  pw.Text(
                    currentAppName,
                    style: pw.TextStyle(color: look.accent, fontWeight: pw.FontWeight.bold, fontSize: 12 * k),
                  ),
                pw.Spacer(),
                if (cfg.showTitle) pw.Text(safeTitle, style: pw.TextStyle(color: _grey, fontSize: 9 * k)),
                if (cfg.datePlacement == PdfDatePlacement.header) ...[
                  if (cfg.showTitle) pw.SizedBox(width: 10),
                  pw.Text(generated, style: pw.TextStyle(color: _navy, fontSize: 9 * k, fontWeight: pw.FontWeight.bold)),
                ],
              ],
            ),
            if (cfg.headerText.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(_safe(cfg.headerText.trim()), style: pw.TextStyle(color: _grey, fontSize: 8.5 * k)),
              ),
            pw.Divider(color: look.accent, thickness: 1.5),
          ],
        ),
        footer: (context) => pw.Row(
          children: [
            pw.Text(footerParts.join(' - '), style: pw.TextStyle(color: _grey, fontSize: 8 * k)),
            pw.Spacer(),
            if (cfg.showPageNumbers)
              pw.Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: pw.TextStyle(color: _grey, fontSize: 8 * k),
              ),
          ],
        ),
        build: (context) => [
          if (cfg.showTitle)
            pw.Text(safeTitle, style: pw.TextStyle(fontSize: 16 * k, fontWeight: pw.FontWeight.bold, color: _navy)),
          if (cfg.datePlacement == PdfDatePlacement.top)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(dateText, style: pw.TextStyle(fontSize: 10 * k, color: _grey)),
            ),
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
