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
import '../../core/plant/plant_methods.dart';
import '../../core/plant/plant_point_charts.dart';
import '../../core/plant/plant_repository.dart';
import '../../core/export/pdf_export_settings.dart';
import '../../core/export/export_table.dart';
import '../../core/export/pdf_style.dart';
import '../../core/lab/gas_bottle_repository.dart';
import '../../core/lab/sample_manifest_repository.dart';
import 'report_options.dart';

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
  // Circuit précis (style propre à ce circuit, s'il a été personnalisé) :
  // seulement quand le rapport ne porte que sur un seul circuit.
  final onlyCircuitId = !allCircuits && circuits.length == 1 ? circuits.first.id : null;
  final pdfCfg = await PdfExportSettings.load(
    allCircuits ? PdfReportKind.allCircuits : PdfReportKind.samples,
    onlyCircuitId,
  );
  final k = pdfCfg.textScale;
  final look = PdfLook(pdfCfg);
  final accentC = look.accent;
  final gasBottles = pdfCfg.showGasBottles ? await loadGasBottles() : const <GasBottle>[];
  final sampleManifest = pdfCfg.showScopeOfWork ? await loadSampleManifest(day) : const <SampleManifestEntry>[];
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
      if (pdfCfg.showCircuitBadge) {
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
          look.table(
            headers: [
              t('plantColTest'),
              if (pdfCfg.showMethods) t('plantColMethod'),
              t('colUnit'),
              t('plantColResults'),
              if (options.limitColumn) t('plantColSpec'),
              if (options.statusColumn) t('colStatus'),
            ],
            fontSize: 8.5 * k,
            cellAlignments: () {
              var i = 1;
              final m = <int, pw.Alignment>{};
              if (pdfCfg.showMethods) m[i++] = pw.Alignment.center;
              m[i++] = pw.Alignment.center; // unité
              m[i++] = pw.Alignment.centerRight; // valeur
              m[i++] = pw.Alignment.center; // seuil
              m[i] = pw.Alignment.center; // statut
              return m;
            }(),
            data: [
              for (final param in point.params)
                if (a.values[param.key] != null &&
                    (paramKeys == null || paramKeys.contains(param.key)))
                  [
                    t(param.labelKey),
                    if (pdfCfg.showMethods) (astmMethodFor(param.key) ?? '-'),
                    param.unit,
                    () {
                      final valueText = param.isNumeric
                          ? formatNumber((a.values[param.key] as num).toDouble())
                          : t('${a.values[param.key]}');
                      final out = controller.isOut(point.id, param, a.values[param.key]);
                      if (out == null || !pdfCfg.highlightOutOfRange) return valueText;
                      return pw.Text(
                        valueText,
                        style: pw.TextStyle(fontSize: 8.5 * k, fontWeight: pw.FontWeight.bold, color: out ? _out : _ok),
                      );
                    }(),
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
        if (pdfCfg.showOutOfRangeComments) {
          final notes = [
            for (final param in point.params)
              if (a.values[param.key] != null &&
                  (paramKeys == null || paramKeys.contains(param.key)) &&
                  controller.isOut(point.id, param, a.values[param.key]) == true &&
                  (a.paramComments[param.key] ?? '').isNotEmpty)
                (t(param.labelKey), a.paramComments[param.key]!),
          ];
          if (notes.isNotEmpty) {
            sections.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (final (label, comment) in notes)
                      pw.RichText(
                        text: pw.TextSpan(
                          style: pw.TextStyle(fontSize: 8.5 * k, color: _out),
                          children: [
                            pw.TextSpan(
                              text: '$label (${t('plantValueOut')}) : ',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                            ),
                            pw.TextSpan(text: _safe(comment)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
        }
        final meta = [t(a.source), if (a.operatorName.isNotEmpty) a.operatorName].map(_safe).join(' - ');
        if (options.details) {
          sections.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(meta, style: const pw.TextStyle(color: _grey, fontSize: 8.5)),
            ),
          );
          if (a.comment != null && a.comment!.isNotEmpty)
            sections.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.RichText(
                  text: pw.TextSpan(
                    style: const pw.TextStyle(fontSize: 8.5, color: _navy),
                    children: [
                      pw.TextSpan(
                        text: '${t('plantCommentPrefix')} : ',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.TextSpan(text: _safe(a.comment!)),
                    ],
                  ),
                ),
              ),
            );
        }
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
      pageTheme: pw.PageTheme(
        pageFormat: pageFormat,
        margin: look.margin(32, 28),
        buildBackground: look.background,
      ),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: pdfCfg.logoRight
                ? [
                    if (pdfCfg.showAppName)
                      pw.Text(
                        currentAppName,
                        style: pw.TextStyle(color: accentC, fontWeight: pw.FontWeight.bold, fontSize: 12 * k),
                      ),
                    pw.Spacer(),
                    if (pdfCfg.datePlacement == PdfDatePlacement.header) ...[
                      pw.Text(headerStamp, style: pw.TextStyle(color: _grey, fontSize: 9 * k)),
                      pw.SizedBox(width: 10),
                    ],
                    if (logoImage != null) pw.Image(logoImage, height: 30),
                  ]
                : [
                    if (logoImage != null) ...[
                      pw.Image(logoImage, height: 30),
                      pw.SizedBox(width: 8),
                    ],
                    if (pdfCfg.showAppName)
                      pw.Text(
                        currentAppName,
                        style: pw.TextStyle(color: accentC, fontWeight: pw.FontWeight.bold, fontSize: 12 * k),
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
          pw.Divider(color: accentC, thickness: 1.5),
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
        if (pdfCfg.coverPage) ...[
          pw.SizedBox(height: 220),
          pw.Center(
            child: pw.Column(
              children: [
                if (pdfCfg.showAppName)
                  pw.Text(
                    currentAppName,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 14 * k, fontWeight: pw.FontWeight.bold, color: accentC),
                  ),
                if (pdfCfg.showTitle) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                    reportTitle,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 22 * k, fontWeight: pw.FontWeight.bold, color: _navy),
                  ),
                ],
                if (pdfCfg.showReportNumber) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                    '${t('plantReportNumberLabel')} $reportNumber',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 14 * k, fontWeight: pw.FontWeight.bold, color: accentC),
                  ),
                ],
              ],
            ),
          ),
          pw.NewPage(),
        ] else ...[
          if (pdfCfg.showTitle)
            pw.Center(
              child: pw.Text(
                reportTitle,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 18 * k, fontWeight: pw.FontWeight.bold, color: _navy),
              ),
            ),
          if (pdfCfg.showReportNumber) ...[
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                '${t('plantReportNumberLabel')} $reportNumber',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 12 * k, fontWeight: pw.FontWeight.bold, color: accentC),
              ),
            ),
          ],
          if (pdfCfg.datePlacement == PdfDatePlacement.top) ...[
            pw.SizedBox(height: 4),
            pw.Text('${t('plantReportGenerated')} $headerStamp', style: pw.TextStyle(fontSize: 10 * k, color: _grey)),
          ],
          pw.SizedBox(height: 16),
        ],
        if (sampleManifest.isNotEmpty) ...[
          pw.Text(
            t('plantScopeOfWorkTitle'),
            style: pw.TextStyle(fontSize: 13 * k, fontWeight: pw.FontWeight.bold, color: _navy),
          ),
          pw.SizedBox(height: 8),
          look.table(
            headers: [
              t('plantScopeColTestItem'),
              t('plantScopeColConditioning'),
              t('plantScopeColQuantity'),
              t('plantScopeColLabel'),
              t('plantScopeColCpfCode'),
            ],
            fontSize: 8.5 * k,
            cellAlignments: {2: pw.Alignment.center},
            data: [
              for (final e in sampleManifest)
                [_safe(e.testItem), _safe(e.conditioning), '${e.quantity}', _safe(e.label), _safe(e.cpfCode)],
            ],
          ),
          pw.NewPage(),
        ],
        ...sections,
        if (gasBottles.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Text(
            t('plantGasBottlesSurveyTitle'),
            style: pw.TextStyle(fontSize: 12 * k, fontWeight: pw.FontWeight.bold, color: _navy),
          ),
          pw.SizedBox(height: 6),
          look.table(
            headers: [t('plantGasBottlesColCylinder'), t('plantGasBottlesColPressure'), t('plantGasBottlesColLocation')],
            fontSize: 8.5 * k,
            cellAlignments: {1: pw.Alignment.center, 2: pw.Alignment.center},
            data: [
              for (final b in gasBottles)
                [_safe(b.label), '${_bottlePressureText(b.pressure)} bars', _safe(b.location)],
            ],
          ),
        ],
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
/// Pression d'une bouteille de gaz : entier si rond, sinon une décimale
/// (contrairement à `formatNumber`, pensé pour des valeurs d'analyse).
String _bottlePressureText(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

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

/// Les mêmes données que le rapport PDF, en tableaux pour Excel / CSV : une
/// feuille par circuit, une ligne par analyse (date, heure de prélèvement,
/// point, valeurs, source, opérateur, commentaire). Mêmes filtres que le
/// PDF : un seul point, des analyses choisies, des paramètres choisis.
List<ExportTable> plantReportTables({
  required PlantController controller,
  required DateTime day,
  required List<PlantCircuit> circuits,
  required String Function(String) s,
  String? onlyPointId,
  Set<String>? analysisIds,
  Set<String>? paramKeys,
}) {
  final tables = <ExportTable>[];
  for (final circuit in circuits) {
    final entries = <(SamplePoint, PlantAnalysis)>[];
    for (final point in controller.pointsOf(circuit)) {
      if (onlyPointId != null && point.id != onlyPointId) continue;
      final analyses = analysisIds != null
          ? [for (final id in analysisIds) ?controller.byId(id)].where((a) => a.pointId == point.id).toList()
          : controller.analysesOnDay(point.id, day).toList();
      for (final a in analyses) {
        entries.add((point, a));
      }
    }
    if (entries.isEmpty) continue;
    entries.sort((x, y) {
      final byDate = x.$2.date.compareTo(y.$2.date);
      if (byDate != 0) return byDate;
      final byTime = x.$2.samplingTime.compareTo(y.$2.samplingTime);
      return byTime != 0 ? byTime : x.$1.code.compareTo(y.$1.code);
    });
    // Colonnes : paramètres des points du circuit réellement renseignés.
    final params = <String, PlantParam>{};
    for (final (point, a) in entries) {
      for (final p in point.params) {
        if (paramKeys != null && !paramKeys.contains(p.key)) continue;
        if (a.values[p.key] != null) params.putIfAbsent(p.key, () => p);
      }
    }
    final cols = params.values.toList();
    final name = s(circuit.labelKey);
    tables.add(
      ExportTable(
        name: name.length > 31 ? name.substring(0, 31) : name,
        headers: [
          s('colDate'),
          s('plantSamplingTime'),
          s('plantColPoint'),
          s('plantColName'),
          for (final p in cols) p.unit.isEmpty ? s(p.labelKey) : '${s(p.labelKey)} (${p.unit})',
          s('plantColSource'),
          s('colOperator'),
          s('colComment'),
          s('plantColOutOfRangeComments'),
        ],
        rows: [
          for (final (point, a) in entries)
            [
              DateOnly(a.date),
              a.samplingTime,
              point.code,
              point.name,
              for (final p in cols)
                p.isNumeric ? a.number(p.key) : (a.values[p.key] == null ? null : s('${a.values[p.key]}')),
              s(a.source),
              a.operatorName,
              a.comment ?? '',
              [
                for (final p in point.params)
                  if (a.values[p.key] != null &&
                      controller.isOut(point.id, p, a.values[p.key]) == true &&
                      (a.paramComments[p.key] ?? '').isNotEmpty)
                    '${s(p.labelKey)}: ${a.paramComments[p.key]}',
              ].join(' ; '),
            ],
        ],
      ),
    );
  }
  return tables;
}
