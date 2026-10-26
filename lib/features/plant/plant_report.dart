import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/analysis/series.dart';
import '../../core/branding/app_logo.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/export/pdf_chart.dart';
import '../../core/plant/plant_catalog.dart';
import '../../core/plant/plant_point_charts.dart';
import '../../core/plant/plant_repository.dart';
import '../../core/export/pdf_export_settings.dart';
import 'report_options.dart';

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
  required String reportNumber,
  bool includeMissing = false,
  bool allCircuits = false,
  String? onlyPointId,
  Set<String>? analysisIds,
  Set<String>? paramKeys,
  ReportOptions options = const ReportOptions(),
}) async {
  // Polices standard du PDF : pas de tiret long ni de ≤ / ≥.
  String t(String key) => _safe(s(key));
  final pdfCfg = await PdfExportSettings.load(allCircuits ? PdfReportKind.allCircuits : PdfReportKind.samples);
  final k = pdfCfg.textScale;
  final reportTitle = pdfCfg.reportTitle.trim().isEmpty ? t(allCircuits ? 'plantReportTitle' : 'plantSampleReportTitle') : _safe(pdfCfg.reportTitle.trim());
  final roleText = pdfCfg.signatureRole.trim().isEmpty ? t('plantReportRole') : _safe(pdfCfg.signatureRole.trim());
  final doc = pw.Document(title: reportTitle, author: currentAppName);
  final logo = currentAppLogo;
  final logoImage = logo == null || !options.logo ? null : pw.MemoryImage(logo);
  final headerStamp = pdfCfg.stamp();
  final reportDay = DateFormat('dd-MM-yyyy').format(day);

  // Bloc « Date : … / Nom : fonction », en gras comme sur le modèle.
  pw.Widget signatureBlock() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        '${t('plantReportDateLabel')}: $reportDay',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      if (operatorName.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Text(
          '${_safe(operatorName)}: $roleText',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ],
  );

  // Analyses choisies (une, plusieurs ou toutes) d'un point, de la plus
  // ancienne à la plus récente.
  List<PlantAnalysis> selectedFor(SamplePoint p) =>
      [
        for (final id in analysisIds ?? <String>{}) ?controller.byId(id),
      ].where((a) => a.pointId == p.id).toList()..sort((x, y) {
        final byDate = x.date.compareTo(y.date);
        return byDate != 0 ? byDate : x.samplingTime.compareTo(y.samplingTime);
      });

  final sections = <pw.Widget>[];

  for (final circuit in circuits) {
    final points = [
      for (final p in controller.pointsOf(circuit))
        if (onlyPointId == null || p.id == onlyPointId) p,
    ];
    // Circuit sans rien à montrer (tous ses points non analysés, exclus du
    // rapport) : pas d'en-tête orphelin.
    final hasVisiblePoint =
        includeMissing ||
        points.any(
          (p) => analysisIds != null
              ? selectedFor(p).isNotEmpty
              : controller.analysisOn(p.id, day) != null,
        );
    if (hasVisiblePoint) {
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
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      );
    }
    for (final point in points) {
      final selected = analysisIds == null ? null : selectedFor(point);
      final analysis = selected != null
          ? (selected.isEmpty ? null : selected.last)
          : controller.analysisOn(point.id, day);
      final status = selected != null
          ? (selected.isEmpty
                ? PlantStatus.missing
                : (selected.any(
                        (x) => controller.outOfRange(point, x).isNotEmpty,
                      )
                      ? PlantStatus.outOfRange
                      : PlantStatus.ok))
          : controller.status(point, day);
      if (analysis == null && !includeMissing) continue;
      sections.add(pw.SizedBox(height: 8));
      sections.add(
        pw.Row(
          children: [
            pw.Text(
              _safe('${point.code} - ${point.name}'),
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10.5,
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Text(
              _safe('(${point.equipment})'),
              style: const pw.TextStyle(color: _grey, fontSize: 9),
            ),
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
            child: pw.Text(
              t('plantNoAnalysisThatDay'),
              style: const pw.TextStyle(color: _grey, fontSize: 9),
            ),
          ),
        );
        continue;
      }
      // Toutes les analyses du jour (ex: 8 h et 17 h), par heure de prélèvement.
      var daily =
          selected ??
          (controller.analysesOnDay(point.id, day).toList()
            ..sort((x, y) => x.samplingTime.compareTo(y.samplingTime)));
      if (paramKeys != null) {
        daily = daily
            .where(
              (x) => point.params.any(
                (p) => paramKeys.contains(p.key) && x.values[p.key] != null,
              ),
            )
            .toList();
      }
      if (daily.isEmpty) {
        sections.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text(
              t('plantNoValuesForParams'),
              style: const pw.TextStyle(color: _grey, fontSize: 9),
            ),
          ),
        );
        continue;
      }
      if (!options.allAnalyses && analysisIds == null) daily = [daily.last];
      void addCharts() {
        for (final chart in plantPointCharts(controller, point, s, keys: paramKeys)) {
          sections.add(pw.SizedBox(height: 8));
          sections.add(buildPdfChartSection(chart, height: 130));
        }
      }

      if (options.curves && pdfCfg.charts == PdfChartsPosition.before) addCharts();
      for (final a in daily) {
        sections.add(pw.SizedBox(height: 4));
        if (options.samplingTime || analysisIds != null) {
          sections.add(
            pw.Text(
              '${t('plantSamplingTime')}: ${analysisIds != null ? '${DateFormat('dd-MM-yyyy').format(a.date)} ' : ''}${a.samplingTime}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _navy,
              ),
            ),
          );
        }
        sections.add(pw.SizedBox(height: 3));
        sections.add(
          pw.TableHelper.fromTextArray(
            headers: [
              t('plantColParam'),
              t('colUnit'),
              t('colValue'),
              if (options.limitColumn) t('plantColThreshold'),
              if (options.statusColumn) t('colStatus'),
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 8.5,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: _navy),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignments: {
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
            },
            data: [
              for (final param in point.params)
                if (a.values[param.key] != null &&
                    (paramKeys == null || paramKeys.contains(param.key)))
                  [
                    t(param.labelKey),
                    param.unit,
                    param.isNumeric
                        ? formatNumber((a.values[param.key] as num).toDouble())
                        : t('${a.values[param.key]}'),
                    if (options.limitColumn)
                      _thresholdLabel(
                        controller.threshold(point.id, param.key),
                      ),
                    if (options.statusColumn)
                      switch (controller.isOut(
                        point.id,
                        param,
                        a.values[param.key],
                      )) {
                        true => t('plantStatusOut'),
                        false => t('plantStatusOk'),
                        null => '-',
                      },
                  ],
            ],
          ),
        );
        final meta = [
          t(a.source),
          if (a.operatorName.isNotEmpty) a.operatorName,
          if (a.comment != null && a.comment!.isNotEmpty) a.comment!,
        ].map(_safe).join(' - ');
        if (options.details)
          sections.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(
                meta,
                style: const pw.TextStyle(color: _grey, fontSize: 8.5),
              ),
            ),
          );
        // Photo jointe : toujours sous le tableau.
        final photo = _decodePhoto(a.photo);
        if (options.photo && photo != null) {
          sections.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Center(
                child: pw.Image(photo, height: 150, fit: pw.BoxFit.contain),
              ),
            ),
          );
        }
      }
      if (options.curves && pdfCfg.charts != PdfChartsPosition.before) addCharts();
    }
  }

  final pageFormat = switch (pdfCfg.orientation) {
    PdfOrientation.landscape => PdfPageFormat.a4.landscape,
    _ => PdfPageFormat.a4,
  };
  final footerParts = [
    if (pdfCfg.datePlacement == PdfDatePlacement.footer) '${t('plantReportGenerated')} $headerStamp',
    if (pdfCfg.showOperator && operatorName.isNotEmpty) _safe(operatorName),
    if (pdfCfg.footerText.trim().isNotEmpty) _safe(pdfCfg.footerText.trim()),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              if (logoImage != null) ...[
                pw.Image(logoImage, height: 30),
                pw.SizedBox(width: 8),
              ],
              if (pdfCfg.showAppName)
                pw.Text(
                  currentAppName,
                  style: pw.TextStyle(color: _accent, fontWeight: pw.FontWeight.bold, fontSize: 12 * k),
                ),
              pw.Spacer(),
              if (pdfCfg.datePlacement == PdfDatePlacement.header)
                pw.Text(headerStamp, style: pw.TextStyle(color: _grey, fontSize: 9 * k)),
            ],
          ),
          if (pdfCfg.headerText.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(_safe(pdfCfg.headerText.trim()), style: pw.TextStyle(color: _grey, fontSize: 8.5 * k)),
            ),
          pw.Divider(color: _accent, thickness: 1.5),
        ],
      ),
      footer: (context) => pw.Row(
        children: [
          pw.Text(footerParts.join(' - '), style: pw.TextStyle(color: _grey, fontSize: 8 * k)),
          pw.Spacer(),
          if (pdfCfg.showPageNumbers)
            pw.Text('${context.pageNumber} / ${context.pagesCount}', style: pw.TextStyle(color: _grey, fontSize: 8 * k)),
        ],
      ),
      build: (context) => [
        if (pdfCfg.showTitle)
          pw.Text(reportTitle, style: pw.TextStyle(fontSize: 18 * k, fontWeight: pw.FontWeight.bold, color: _navy)),
        if (pdfCfg.showReportNumber) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            '${t('plantReportNumberLabel')} $reportNumber',
            style: pw.TextStyle(fontSize: 12 * k, fontWeight: pw.FontWeight.bold, color: _accent),
          ),
        ],
        if (pdfCfg.datePlacement == PdfDatePlacement.top) ...[
          pw.SizedBox(height: 4),
          pw.Text('${t('plantReportGenerated')} $headerStamp', style: pw.TextStyle(fontSize: 10 * k, color: _grey)),
        ],
        pw.SizedBox(height: 16),
        ...sections,
        if (options.signatureBottom) ...[
          pw.SizedBox(height: 24),
          signatureBlock(),
        ],
        if (sections.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 24),
            child: pw.Text(t('plantReportNothing'), style: const pw.TextStyle(color: _grey, fontSize: 11)),
          ),
      ],
    ),
  );
  return doc.save();
}

String _thresholdLabel(PlantThreshold? t) {
  if (t == null || t.isEmpty) return '-';
  if (t.min != null && t.max != null)
    return '${formatNumber(t.min!)} - ${formatNumber(t.max!)}';
  // ">=" / "<=" plutôt que ≥ / ≤, absents des polices standard du PDF.
  if (t.min != null) return '>= ${formatNumber(t.min!)}';
  return '<= ${formatNumber(t.max!)}';
}

/// Remplace les caractères absents des polices standard du PDF.
String _safe(String text) => text
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .replaceAll('≤', '<=')
    .replaceAll('≥', '>=')
    .replaceAll('’', "'")
    .replaceAll('…', '...');

pw.MemoryImage? _decodePhoto(String? base64Photo) {
  if (base64Photo == null || base64Photo.isEmpty) return null;
  try {
    return pw.MemoryImage(base64Decode(base64Photo));
  } catch (_) {
    return null;
  }
}

/// Titre du rapport usine : celui choisi dans Réglages › Exports PDF, sinon
/// le titre par défaut (aussi utilisé pour l'objet des e-mails).
Future<String> plantReportTitleOf(String Function(String) s, {bool allCircuits = false}) async {
  final c = await PdfExportSettings.load();
  final custom = c.reportTitle.trim();
  return custom.isEmpty ? s(allCircuits ? 'plantReportTitle' : 'plantSampleReportTitle') : custom;
}
