import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/analysis/series.dart';
import '../../core/branding/app_logo.dart';
import '../../core/config/shared_config.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/export/pdf_chart.dart';
import '../../core/plant/plant_catalog.dart';
import '../../core/plant/plant_methods.dart';
import '../../core/plant/plant_point_charts.dart';
import '../../core/plant/plant_repository.dart';
import '../../core/export/pdf_export_settings.dart';
import '../../core/export/export_table.dart';
import '../../core/export/pdf_style.dart';
import '../../core/export/pdf_style_set.dart';
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

  /// Réglages à utiliser à la place de ceux enregistrés (aperçu en direct).
  PdfExportSettings? settings,

  /// Aperçu des réglages : bouteilles de gaz et Scope of Work d'exemple (rien
  /// n'est lu en base), pour que les deux options se voient à l'écran.
  bool sampleExtras = false,
}) async {
  // Polices standard du PDF : pas de tiret long ni de ≤ / ≥.
  String t(String key) => _safe(s(key));
  // Circuit précis (style propre à ce circuit, s'il a été personnalisé) :
  // seulement quand le rapport ne porte que sur un seul circuit.
  final onlyCircuitId = !allCircuits && circuits.length == 1 ? circuits.first.id : null;
  final pdfCfg = settings ?? await PdfExportSettings.load(
    allCircuits ? PdfReportKind.allCircuits : PdfReportKind.samples,
    onlyCircuitId,
  );
  final k = pdfCfg.textScale;
  final look = PdfLook(pdfCfg);
  final accentC = look.accent;
  final gasBottles = pdfCfg.showGasBottles ? (sampleExtras ? _previewGasBottles : await loadGasBottles()) : const <GasBottle>[];
  var gasBottlesReadingTime = gasBottles.isEmpty ? '' : await loadGasBottlesReadingTime();
  final gasReadingDate = gasBottles.isEmpty ? null : DateTime.tryParse(await loadGasBottlesReadingDate());
  if (gasReadingDate != null) {
    final d = '${gasReadingDate.day.toString().padLeft(2, '0')}/${gasReadingDate.month.toString().padLeft(2, '0')}/${gasReadingDate.year}';
    gasBottlesReadingTime = '$d $gasBottlesReadingTime'.trim();
  }
  final sampleManifest = pdfCfg.showScopeOfWork ? (sampleExtras ? _previewManifest(day) : await loadSampleManifest(day)) : const <SampleManifestEntry>[];
  final reportTitle = pdfCfg.reportTitle.trim().isEmpty ? t(allCircuits ? 'plantReportTitle' : 'plantSampleReportTitle') : _safe(pdfCfg.reportTitle.trim());
  final roleText = pdfCfg.signatureRole.trim().isEmpty ? t('plantReportRole') : _safe(pdfCfg.signatureRole.trim());
  final doc = pw.Document(title: reportTitle, author: currentAppName);
  final logo = currentAppLogo;
  final logoImage = logo == null || !options.logo ? null : pw.MemoryImage(logo);
  final headerStamp = pdfCfg.stamp();
  final reportDay = DateFormat('dd-MM-yyyy').format(day);

  // Titres : sans personnalisation, rendu historique inchangé ; sinon le style
  // choisi (police, taille, couleur, alignement) prend le dessus.
  final rtSpec = pdfCfg.style.reportTitle;
  final rtDefault = rtSpec == PdfStyleSet.defaults.reportTitle;
  final ttSpec = pdfCfg.style.tableTitle;
  final ttDefault = ttSpec == PdfStyleSet.defaults.tableTitle;
  pw.Widget reportTitleW(String text, double base, {required bool centerBox}) {
    if (!rtDefault) {
      final spec = rtSpec.size == null ? rtSpec : rtSpec.copyWith(size: rtSpec.size! * base / 18);
      return look.title(text, spec, size: base, color: _navy, scale: k);
    }
    final txt = pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: base * k, fontWeight: pw.FontWeight.bold, color: _navy),
    );
    return centerBox ? pw.Center(child: txt) : txt;
  }

  pw.Widget tableTitleW(String text, double base) => ttDefault
      ? pw.Text(text, style: pw.TextStyle(fontSize: base * k, fontWeight: pw.FontWeight.bold, color: _navy))
      : look.title(text, ttSpec, size: base, color: _navy, scale: k);

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
      if (analysis == null && !includeMissing) continue;
      sections.add(pw.SizedBox(height: 8));
      sections.add(
        pw.Row(
          children: [
            pw.Container(width: 4, height: 4, decoration: const pw.BoxDecoration(color: PdfColors.black, shape: pw.BoxShape.circle)),
            pw.SizedBox(width: 8),
            pw.Text(
              _safe('${t(circuit.labelKey)}: ${point.name}'),
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10.5,
                decoration: pw.TextDecoration.underline,
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
              style: look.note(pdfCfg.style.secondary, size: 9, color: _grey),
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
              style: look.note(pdfCfg.style.secondary, size: 9, color: _grey),
            ),
          ),
        );
        continue;
      }
      if (!options.allAnalyses && analysisIds == null) daily = [daily.last];
      void addCharts() {
        for (final chart in plantPointCharts(controller, point, s, keys: paramKeys)) {
          sections.add(pw.SizedBox(height: 8));
          sections.add(buildPdfChartSection(chart, height: 130, look: look));
        }
      }

      if (options.curves && pdfCfg.charts == PdfChartsPosition.before) addCharts();
      // Colonne fusionnée, toujours (une ou plusieurs analyses du point ce
      // jour-là) plutôt que la ligne de texte : même présentation pour tous
      // les points du rapport, comme sur le modèle papier.
      final useTimeColumn = options.samplingTime;
      // Lignes de résultats d'une analyse (sans la colonne « heure »).
      List<List<Object>> rowsFor(PlantAnalysis a) {
        const apprKeys = ['appr_free_condensate', 'appr_emulsion', 'appr_sand'];
        bool shown(PlantParam p) => a.values[p.key] != null && (paramKeys == null || paramKeys.contains(p.key));
        final out = <List<Object>>[];
        var apprDone = false;
        for (final param in point.params) {
          if (param.key.startsWith('appr_') && param.key.endsWith('_v')) continue;
          if (apprKeys.contains(param.key)) {
            if (apprDone) continue;
            apprDone = true;
            final subs = [for (final p in point.params) if (apprKeys.contains(p.key) && shown(p)) p];
            for (var n = 0; n < subs.length; n++) {
              final sp = subs[n];
              final choice = '${a.values[sp.key]}';
              final measured = choice == 'plantApprMeasured' ? a.values['${sp.key}_v'] : null;
              final bad = controller.isOut(point.id, sp, choice) == true;
              final color = !pdfCfg.highlightOutOfRange ? PdfColors.black : (bad ? _out : _ok);
              final valueText = measured is num ? '${measured.toDouble().toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')}%V' : t(choice);
              out.add([
                n == 0 ? t('plantParamAppearance') : const PdfCellContinues(),
                if (pdfCfg.showMethods) (n == 0 ? (plantMethodShown(sp, t(sp.labelKey)) ?? '-') : const PdfCellContinues()),
                n == 0 ? '%Vol' : const PdfCellContinues(),
                pw.RichText(
                  text: pw.TextSpan(
                    style: pw.TextStyle(fontSize: 8.5 * k),
                    children: [
                      pw.TextSpan(text: '${t(sp.labelKey)}: '),
                      pw.TextSpan(
                        text: valueText,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: color),
                      ),
                    ],
                  ),
                ),
                if (options.limitColumn) t('plantApprPass'),
                if (options.statusColumn) (bad ? t('plantStatusOut') : t('plantStatusOk')),
              ]);
            }
            continue;
          }
          if (!shown(param)) continue;
          out.add([
                    labelWithoutMethod(t(param.labelKey)),
                    if (pdfCfg.showMethods) (plantMethodShown(param, t(param.labelKey)) ?? '-'),
                    param.unit,
                    () {
                      final valueText = param.isNumeric
                          ? formatNumber((a.values[param.key] as num).toDouble())
                          : t('${a.values[param.key]}');
                      final out = controller.isOut(point.id, param, a.values[param.key]);
                      if (out == null || !pdfCfg.highlightOutOfRange) {
                        return pw.Text(valueText, style: pw.TextStyle(fontSize: 8.5 * k, fontWeight: pw.FontWeight.bold));
                      }
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
                  ]);
        }
        return out;
      }

      // Plusieurs analyses du même point (ex. 7h30 et 17h30) : un seul tableau,
      // la cellule « heure de prélèvement » fusionnée en face des lignes de
      // chaque analyse, comme sur le modèle PDF du laboratoire.
      if (useTimeColumn) {
        final tableFontSize = 8.5 * k;
        sections.add(pw.SizedBox(height: 3));
        sections.addAll(
          look.groupedTable(
            headers: [
              t('plantSamplingTimeColumn'),
              t('plantColTest'),
              if (pdfCfg.showMethods) t('plantColMethod'),
              t('colUnit'),
              t('plantColResults'),
              if (options.limitColumn) t('plantColSpec'),
              if (options.statusColumn) t('colStatus'),
            ],
            fontSize: tableFontSize,
            cellAlignments: () {
              var i = 1;
              final m = <int, pw.Alignment>{};
              m[i++] = pw.Alignment.center; // libellé du test
              if (pdfCfg.showMethods) m[i++] = pw.Alignment.center;
              m[i++] = pw.Alignment.center; // unité
              m[i++] = pw.Alignment.center; // valeur
              m[i++] = pw.Alignment.center; // seuil
              m[i] = pw.Alignment.center; // statut
              return m;
            }(),
            // Toutes les colonnes doivent avoir une largeur explicite : chaque
            // groupe (heure de prélèvement) devient un tableau PDF séparé
            // (pour ne jamais le couper entre deux pages), et une colonne
            // sans largeur fixe se dimensionne sur son propre contenu —
            // les grilles de deux groupes ne s'alignent alors plus entre
            // elles (ex: "674.0" plus large que "0.100").
            columnWidths: {
              0: const pw.FlexColumnWidth(1.6), // heure
              1: const pw.FlexColumnWidth(3), // test
              if (pdfCfg.showMethods) 2: const pw.FlexColumnWidth(2.4), // méthode
              2 + (pdfCfg.showMethods ? 1 : 0): const pw.FlexColumnWidth(1.3), // unité
              3 + (pdfCfg.showMethods ? 1 : 0): const pw.FlexColumnWidth(1.8), // résultat
              if (options.limitColumn) 4 + (pdfCfg.showMethods ? 1 : 0): const pw.FlexColumnWidth(1.6), // seuil
              if (options.statusColumn)
                4 + (pdfCfg.showMethods ? 1 : 0) + (options.limitColumn ? 1 : 0): const pw.FlexColumnWidth(1.6), // statut
            },
            groups: [
              for (final a in daily)
                (
                  analysisIds != null
                      ? '${DateFormat('dd-MM-yyyy').format(a.date)}\n${a.samplingTime}'
                      : a.samplingTime,
                  rowsFor(a),
                ),
            ],
          ),
        );
      }

      for (final a in daily) {
        sections.add(pw.SizedBox(height: 4));
        if (!useTimeColumn && (options.samplingTime || analysisIds != null)) {
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
        final tableFontSize = 8.5 * k;
        var rowIndex = 0;
        if (!useTimeColumn) sections.add(
          look.table(
            headers: [
              if (useTimeColumn) t('plantSamplingTime'),
              t('plantColTest'),
              if (pdfCfg.showMethods) t('plantColMethod'),
              t('colUnit'),
              t('plantColResults'),
              if (options.limitColumn) t('plantColSpec'),
              if (options.statusColumn) t('colStatus'),
            ],
            fontSize: tableFontSize,
            cellAlignments: () {
              var i = useTimeColumn ? 1 : 0;
              final m = <int, pw.Alignment>{};
              if (useTimeColumn) m[0] = pw.Alignment.center;
              i++; // libellé du test
              if (pdfCfg.showMethods) m[i++] = pw.Alignment.center;
              m[i++] = pw.Alignment.center; // unité
              m[i++] = pw.Alignment.centerRight; // valeur
              m[i++] = pw.Alignment.center; // seuil
              m[i] = pw.Alignment.center; // statut
              return m;
            }(),
            data: [
              for (final r in rowsFor(a)) [if (useTimeColumn) (rowIndex++ == 0 ? a.samplingTime : ''), for (final c in r) c is PdfCellContinues ? '' : c],
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
        final meta = [if (a.operatorName.isNotEmpty) a.operatorName].map(_safe).join(' - ');
        if (options.details && meta.isNotEmpty) {
          sections.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(meta, style: look.note(pdfCfg.style.secondary, size: 8.5, color: _grey)),
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
              child: pw.Column(
                children: [
                  pw.Center(child: pw.Image(photo, height: 150, fit: pw.BoxFit.contain)),
                  if ((a.photoTitle ?? '').trim().isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(
                      _safe(a.photoTitle!.trim()),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _navy),
                    ),
                  ],
                ],
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
  final pageMargin = look.margin(32, 28);

  // Page de garde : rendu historique (logo absent, titre centré à 220 pt du
  // haut) tant que rien n'a été déplacé à la souris (Réglages › Exports PDF
  // › Mise en page libre) ; dès qu'un élément a une position choisie, toute
  // la page de garde passe en positionnement libre (pw.Stack).
  pw.Widget coverPage() {
    final logoLayout = pdfCfg.style.logoLayout;
    final titleLayout = pdfCfg.style.titleLayout;
    final titleScale = titleLayout?.scale ?? 1;
    final titleBlock = pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        if (pdfCfg.showAppName)
          pw.Text(
            currentAppName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 14 * k * titleScale, fontWeight: pw.FontWeight.bold, color: accentC),
          ),
        if (pdfCfg.showTitle) ...[
          pw.SizedBox(height: 8),
          reportTitleW(reportTitle, 22 * titleScale, centerBox: false),
        ],
        if (pdfCfg.showReportNumber) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            '${t('plantReportNumberLabel')} $reportNumber',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 14 * k * titleScale, fontWeight: pw.FontWeight.bold, color: accentC),
          ),
        ],
      ],
    );

    if (logoLayout == null && titleLayout == null) {
      return pw.Column(children: [pw.SizedBox(height: 220), pw.Center(child: titleBlock)]);
    }
    // Un élément a été déplacé : la page de garde n'a plus d'en-tête/pied de
    // page (voir plus bas) et occupe toute la zone utile.
    return pw.SizedBox(
      width: pageFormat.width - pageMargin.horizontal,
      height: pageFormat.height - pageMargin.vertical,
      child: pw.Stack(
        children: [
          if (logoLayout != null && logoImage != null)
            pw.Align(
              alignment: pw.Alignment(logoLayout.dx * 2 - 1, 1 - logoLayout.dy * 2),
              child: pw.Image(logoImage, height: 30 * logoLayout.scale),
            ),
          pw.Align(
            alignment: titleLayout == null ? pw.Alignment.center : pw.Alignment(titleLayout.dx * 2 - 1, 1 - titleLayout.dy * 2),
            child: titleBlock,
          ),
        ],
      ),
    );
  }

  /// Vrai si la page de garde est en positionnement libre (un élément a été
  /// déplacé à la souris) : elle occupe alors toute la zone utile, donc sans
  /// en-tête/pied de page superposés dessus.
  bool coverPageIsFreeLayout(pw.Context context) =>
      pdfCfg.coverPage && context.pageNumber == 1 && (pdfCfg.style.logoLayout != null || pdfCfg.style.titleLayout != null);

  final footerParts = [
    if (pdfCfg.datePlacement == PdfDatePlacement.footer) '${t('plantReportGenerated')} $headerStamp',
    if (pdfCfg.showOperator && operatorName.isNotEmpty) _safe(operatorName),
    if (pdfCfg.footerText.trim().isNotEmpty) _safe(pdfCfg.footerText.trim()),
  ];

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: pageFormat,
        margin: pageMargin,
        buildBackground: look.background,
      ),
      header: (context) => coverPageIsFreeLayout(context) ? pw.SizedBox() : pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: pdfCfg.logoRight
                ? [
                    if (pdfCfg.showAppName)
                      pw.Text(
                        currentAppName,
                        style: look.note(pdfCfg.style.pageHeader, size: 12 * k, color: accentC, bold: true),
                      ),
                    pw.Spacer(),
                    if (pdfCfg.datePlacement == PdfDatePlacement.header) ...[
                      pw.Text(headerStamp, style: look.note(pdfCfg.style.pageHeader, size: 9 * k, color: _grey)),
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
                        style: look.note(pdfCfg.style.pageHeader, size: 12 * k, color: accentC, bold: true),
                      ),
                    pw.Spacer(),
                    if (pdfCfg.datePlacement == PdfDatePlacement.header)
                      pw.Text(headerStamp, style: look.note(pdfCfg.style.pageHeader, size: 9 * k, color: _grey)),
                  ],
          ),
          if (pdfCfg.headerText.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(_safe(pdfCfg.headerText.trim()), style: look.note(pdfCfg.style.pageHeader, size: 8.5 * k, color: _grey)),
            ),
          pw.Divider(color: accentC, thickness: 1.5),
        ],
      ),
      footer: (context) => coverPageIsFreeLayout(context) ? pw.SizedBox() : pw.Row(
        children: [
          pw.Text(footerParts.join(' - '), style: look.note(pdfCfg.style.pageFooter, size: 8 * k, color: _grey)),
          pw.Spacer(),
          if (pdfCfg.showPageNumbers)
            pw.Text('${context.pageNumber} / ${context.pagesCount}', style: look.note(pdfCfg.style.pageFooter, size: 8 * k, color: _grey)),
        ],
      ),
      build: (context) => [
        if (pdfCfg.coverPage) ...[
          coverPage(),
          pw.NewPage(),
        ] else ...[
          if (pdfCfg.showTitle)
            reportTitleW(reportTitle, 18, centerBox: true),
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
            pw.Text('${t('plantReportGenerated')} $headerStamp', style: look.note(pdfCfg.style.secondary, size: 10 * k, color: _grey)),
          ],
          pw.SizedBox(height: 16),
        ],
        if (sampleManifest.isNotEmpty) ...[
          tableTitleW(t('plantScopeOfWorkTitle'), 13),
          pw.SizedBox(height: 8),
          look.table(
            headers: [
              t('plantScopeColTestItem'),
              t('plantScopeColConditioning'),
              t('plantScopeColQuantity'),
              t('plantScopeColLabel'),
              t('plantScopeColCpfCode'),
              t('plantScopeColSamplingTime'),
            ],
            fontSize: 8.5 * k,
            cellAlignments: {2: pw.Alignment.center},
            data: [
              for (final e in sampleManifest)
                [_safe(e.testItem), _safe(e.conditioning), '${e.quantity}', _safe(e.label), _safe(e.cpfCode), _safe(e.samplingTime)],
            ],
          ),
          pw.NewPage(),
        ],
        ...sections,
        if (gasBottles.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          tableTitleW(t('plantGasBottlesSurveyTitle'), 12),
          if (gasBottlesReadingTime.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              '${t('plantGasBottlesReadingTime')}: $gasBottlesReadingTime',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _navy),
            ),
          ],
          pw.SizedBox(height: pdfCfg.style.table.spaceAfterTitle),
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
            child: pw.Text(t('plantReportNothing'), style: look.note(pdfCfg.style.secondary, size: 11, color: _grey)),
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
const _previewGasBottles = [
  GasBottle(id: 'p1', name: 'Bouteille 1', pressure: 120, location: 'Zone A'),
  GasBottle(id: 'p2', name: 'Bouteille 2', pressure: 95.5, location: 'Zone B'),
];

List<SampleManifestEntry> _previewManifest(DateTime day) => [
  SampleManifestEntry(id: 'p1', date: '', testItem: 'Condensate', conditioning: 'Bottle 1 L', quantity: 2, label: 'COND-01', cpfCode: 'CPF-001', samplingTime: '06:30'),
  SampleManifestEntry(id: 'p2', date: '', testItem: 'Produced water', conditioning: 'Bottle 500 mL', quantity: 1, label: 'PW-01', cpfCode: 'CPF-002', samplingTime: '07:00'),
];

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
