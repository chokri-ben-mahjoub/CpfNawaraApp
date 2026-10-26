import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/l10n/app_strings.dart';
import 'package:puitstrack/core/models/well_round.dart';
import 'package:puitstrack/core/plant/plant_catalog.dart';

void main() {
  const fr = Locale('fr');
  const en = Locale('en');

  /// `tr` renvoie la clé elle-même quand elle manque : on vérifie qu'elle est
  /// traduite dans les deux langues, et qu'aucune traduction n'est vide.
  void expectTranslated(Iterable<String> keys) {
    for (final key in keys) {
      for (final locale in [fr, en]) {
        final text = tr(locale, key);
        expect(text, isNot(key), reason: 'clé manquante (${locale.languageCode}) : $key');
        expect(text.trim(), isNotEmpty, reason: 'traduction vide (${locale.languageCode}) : $key');
      }
    }
  }

  test('tournées : champs, sections et choix traduits en français et en anglais', () {
    final all = [...wellRoundFields, ...siteRoundFields];
    expectTranslated([
      for (final f in all) f.labelKey,
      for (final f in all) 'rs_${f.section}',
      for (final f in all) ...f.choices,
      'navRounds',
      'roundsTitle',
      'roundsToday',
      'roundsPrevDay',
      'roundsNextDay',
      'roundsWellsDone',
      'roundsViewCards',
      'roundsViewTable',
      'roundsEnter',
      'roundsAddAnother',
      'roundsSite',
      'roundsNothing',
      'roundsColWell',
      'roundsColTime',
      'roundsColOperator',
      'roundsPrevious',
      'roundsSaved',
      'roundsDeleteTitle',
      'roundNotDone',
    ]);
  });

  test('catalogue de l\'usine : libellés et choix de tous les paramètres intégrés', () {
    expectTranslated([
      for (final p in builtInParamCatalog) p.labelKey,
      for (final p in builtInParamCatalog) ...p.choices,
    ]);
  });

  test('calcul des hydrocarbures, réglages PDF, export multi-analyses', () {
    expectTranslated([
      'plantCalcTitle', 'plantCalcHint', 'plantCalcInputs', 'plantCalcResults', 'plantCalcTphUsed',
      'plantCalcNeedMore', 'plantCalcStepMass', 'plantCalcStepVolume', 'plantCalcPrefilled',
      'plantSelectMode', 'plantSelectDone', 'plantSelectAll', 'plantSelectNone', 'plantExportSelected',
      'plantParamsTitle', 'plantParamsHint', 'plantNoValuesForParams', 'plantSamplingTime',
      'plantReportDateLabel', 'plantReportTitle', 'plantSampleReportTitle', 'plantReportRole', 'reportOptTitle',
      'reportOpt_curves', 'reportOpt_photo', 'reportOpt_limitColumn', 'reportOpt_statusColumn',
      'reportOpt_details', 'reportOpt_samplingTime', 'reportOpt_allAnalyses', 'reportOpt_headerDateTime',
      'reportOpt_signatureBottom', 'reportOpt_logo',
      'pdfSetTitle', 'pdfSetIntro', 'pdfSetCharts', 'pdfSetChartsPos', 'pdfSetChartsAfter', 'pdfSetChartsBefore',
      'pdfSetHidden', 'pdfSetDate', 'pdfSetDatePlacement', 'pdfSetPlaceHeader', 'pdfSetPlaceFooter',
      'pdfSetPlaceTop', 'pdfSetDateFormat', 'pdfSetShowTime', 'pdfSetPreview', 'pdfSetHeaderFooter',
      'pdfSetLogo', 'pdfSetAppName', 'pdfSetTitleShow', 'pdfSetOperator', 'pdfSetPages', 'pdfSetHeaderText',
      'pdfSetFooterText', 'pdfSetPage', 'pdfSetOrientation', 'pdfSetAuto', 'pdfSetPortrait', 'pdfSetLandscape',
      'pdfKindAll', 'pdfKindSamples', 'pdfKindTables', 'pdfKindAllHint', 'pdfKindSamplesHint', 'pdfKindTablesHint',
      'pdfLivePreview', 'pdfPreviewHide', 'pdfPreviewShow', 'pdfSecTexts', 'pdfSecContent', 'pdfSetReportNumber',
      'pdfPresets', 'pdfPreset_classic', 'pdfPreset_minimal', 'pdfPreset_compact', 'pdfPreset_detailed', 'pdfPresetHint_classic', 'pdfPresetHint_minimal', 'pdfPresetHint_compact', 'pdfPresetHint_detailed', 'pdfSecLook', 'pdfSetColors', 'pdfPalOrange', 'pdfPalBlue', 'pdfPalGreen', 'pdfPalPurple', 'pdfPalRed', 'pdfPalTeal', 'pdfSetTableStyle', 'pdfTableFilled', 'pdfTableLines', 'pdfTableZebra', 'pdfSetMargins', 'pdfMarginTight', 'pdfMarginWide', 'pdfSetWatermark', 'pdfSetWatermarkHint', 'pdfSetEmptyNone',
      'pdfSetPlantReport', 'pdfSetReportTitle', 'pdfSetSignatureRole', 'pdfSetEmptyDefault',
      'pdfSetTextSize', 'pdfSetSmall', 'pdfSetNormal', 'pdfSetLarge', 'pdfSetReset', 'pdfSetOpenHint',
      'stockTableFormula',
    ]);
  });

  test('libellés prédéfinis des types d\'analyse : traduits en anglais, libres inchangés', () {
    dataLanguage = 'en';
    expect(trData('Tête de puits'), 'Wellhead');
    expect(trData('Injection chimique'), 'Chemical injection');
    expect(trData('Pression annulaire'), 'Annulus pressure');
    expect(trData('Mon type perso'), 'Mon type perso');
    dataLanguage = 'fr';
    expect(trData('Tête de puits'), 'Tête de puits');
  });
}
