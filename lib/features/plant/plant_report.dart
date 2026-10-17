import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/analysis/series.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/plant/plant_catalog.dart';
import '../../core/plant/plant_repository.dart';

const _accent = PdfColor.fromInt(0xFFFF7A33);
const _navy = PdfColor.fromInt(0xFF0B1E2D);
const _ok = PdfColor.fromInt(0xFF2E7D32);
const _out = PdfColor.fromInt(0xFFC62828);
const _grey = PdfColor.fromInt(0xFF757575);

/// Rapport journalier PDF de l'usine pour un ou plusieurs circuits : par
/// point, les valeurs du jour avec unité, seuil et état (conforme / hors
/// seuil), et la liste des points non analysés.
///
/// Polices standard du PDF (Helvetica) : les caractères accentués français
/// sont pris en charge.
Future<Uint8List> buildPlantDailyReport({
  required PlantController controller,
  required DateTime day,
  required List<PlantCircuit> circuits,
  required String Function(String) s,
  required String languageCode,
  required String operatorName,
}) async {
  // Polices standard du PDF : pas de tiret long ni de ≤ / ≥.
  String t(String key) => _safe(s(key));
  final doc = pw.Document(title: t('plantReportTitle'), author: currentAppName);
  final dateLabel = DateFormat('EEEE d MMMM yyyy', languageCode).format(day);
  final generated = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

  final sections = <pw.Widget>[];
  var analysed = 0;
  var outCount = 0;
  var total = 0;

  for (final circuit in circuits) {
    final points = controller.pointsOf(circuit);
    sections.add(pw.SizedBox(height: 14));
    sections.add(
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(circuit.color.toARGB32()),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(
          t(circuit.labelKey).toUpperCase(),
          style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11),
        ),
      ),
    );
    for (final point in points) {
      total++;
      final analysis = controller.analysisOn(point.id, day);
      final status = controller.status(point, day);
      if (analysis != null) analysed++;
      if (status == PlantStatus.outOfRange) outCount++;
      sections.add(pw.SizedBox(height: 8));
      sections.add(
        pw.Row(
          children: [
            pw.Text(
              _safe('${point.code} - ${point.name}'),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5),
            ),
            pw.SizedBox(width: 6),
            pw.Text(_safe('(${point.equipment})'), style: const pw.TextStyle(color: _grey, fontSize: 9)),
            pw.Spacer(),
            pw.Text(
              switch (status) {
                PlantStatus.ok => t('plantStatusOk'),
                PlantStatus.outOfRange => t('plantStatusOut'),
                PlantStatus.missing => t('plantStatusMissing'),
              },
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: switch (status) {
                  PlantStatus.ok => _ok,
                  PlantStatus.outOfRange => _out,
                  PlantStatus.missing => _grey,
                },
              ),
            ),
          ],
        ),
      );
      if (analysis == null) {
        sections.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text(t('plantNoAnalysisThatDay'), style: const pw.TextStyle(color: _grey, fontSize: 9)),
          ),
        );
        continue;
      }
      sections.add(pw.SizedBox(height: 4));
      sections.add(
        pw.TableHelper.fromTextArray(
          headers: [t('plantColParam'), t('colValue'), t('colUnit'), t('plantColThreshold'), t('colStatus')],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _navy),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellAlignments: {1: pw.Alignment.centerRight, 3: pw.Alignment.center, 4: pw.Alignment.center},
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1.4),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(1.8),
            4: const pw.FlexColumnWidth(1.4),
          },
          data: [
            for (final param in point.params)
              if (analysis.values[param.key] != null)
                [
                  t(param.labelKey),
                  param.isNumeric
                      ? formatNumber((analysis.values[param.key] as num).toDouble())
                      : t('${analysis.values[param.key]}'),
                  param.unit,
                  _thresholdLabel(controller.threshold(point.id, param.key)),
                  switch (controller.isOut(point.id, param, analysis.values[param.key])) {
                    true => t('plantStatusOut'),
                    false => t('plantStatusOk'),
                    null => '-',
                  },
                ],
          ],
        ),
      );
      final meta = [
        t(analysis.source),
        if (analysis.operatorName.isNotEmpty) analysis.operatorName,
        if (analysis.comment != null && analysis.comment!.isNotEmpty) analysis.comment!,
      ].map(_safe).join(' - ');
      sections.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text(meta, style: const pw.TextStyle(color: _grey, fontSize: 8.5)),
        ),
      );
    }
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                currentAppName,
                style: pw.TextStyle(color: _accent, fontWeight: pw.FontWeight.bold, fontSize: 12),
              ),
              pw.Spacer(),
              pw.Text(t('plantReportTitle'), style: const pw.TextStyle(color: _grey, fontSize: 9)),
            ],
          ),
          pw.Divider(color: _accent, thickness: 1.5),
        ],
      ),
      footer: (context) => pw.Row(
        children: [
          pw.Text(
            '${t('plantReportGenerated')} $generated${operatorName.isEmpty ? '' : ' - ${_safe(operatorName)}'}',
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
        pw.Text(
          t('plantReportTitle'),
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _navy),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          '${dateLabel[0].toUpperCase()}${dateLabel.substring(1)} - ${circuits.map((c) => t(c.labelKey)).join(', ')}',
          style: const pw.TextStyle(fontSize: 10.5, color: _grey),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            _summary(t('plantSummaryAnalysed'), '$analysed / $total', _navy),
            pw.SizedBox(width: 10),
            _summary(t('plantSummaryOut'), '$outCount', outCount > 0 ? _out : _ok),
            pw.SizedBox(width: 10),
            _summary(t('plantSummaryMissing'), '${total - analysed}', total - analysed > 0 ? _grey : _ok),
          ],
        ),
        ...sections,
      ],
    ),
  );
  return doc.save();
}

String _thresholdLabel(PlantThreshold? t) {
  if (t == null || t.isEmpty) return '-';
  if (t.min != null && t.max != null) return '${formatNumber(t.min!)} - ${formatNumber(t.max!)}';
  // ">=" / "<=" plutôt que ≥ / ≤, absents des polices standard du PDF.
  if (t.min != null) return '>= ${formatNumber(t.min!)}';
  return '<= ${formatNumber(t.max!)}';
}

pw.Widget _summary(String label, String value, PdfColor color) => pw.Expanded(
  child: pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: color, width: 1),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: _grey)),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color),
        ),
      ],
    ),
  ),
);

/// Remplace les caractères absents des polices standard du PDF.
String _safe(String text) => text
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .replaceAll('≤', '<=')
    .replaceAll('≥', '>=')
    .replaceAll('’', "'")
    .replaceAll('…', '...');
