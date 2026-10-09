import '../analysis/production_metrics.dart';
import '../data/wells_repository.dart';
import '../models/analysis_record.dart';
import '../models/intervention.dart';
import '../models/production_types.dart';
import '../models/well.dart';
import 'export_table.dart';

/// Tableaux d'export réutilisés par plusieurs écrans (fiche puits, zone,
/// tableau de bord, journal des interventions...).

/// Analyses brutes : une ligne par saisie. [includeWell] ajoute la colonne
/// "Puits" (exports multi-puits).
ExportTable analysesTable(
  WellsState data,
  List<AnalysisRecord> records,
  String Function(String) s, {
  bool includeWell = false,
}) {
  final wellsById = {for (final w in data.wells) w.id: w};
  final typesById = {for (final t in data.analysisTypes) t.id: t};
  final sorted = [...records]..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  return ExportTable(
    name: s('exportSheetAnalyses'),
    headers: [
      s('colDate'),
      if (includeWell) s('colWell'),
      s('colType'),
      s('colValue'),
      s('colUnit'),
      s('colMin'),
      s('colMax'),
      s('colOutOfRange'),
      s('colService'),
      s('colOperator'),
      s('colComment'),
    ],
    rows: [
      for (final r in sorted)
        if (typesById[r.typeId] != null)
          [
            r.dateTime,
            if (includeWell) _wellLabel(wellsById[r.wellId]),
            typesById[r.typeId]!.label,
            r.value,
            typesById[r.typeId]!.unit,
            typesById[r.typeId]!.min,
            typesById[r.typeId]!.max,
            typesById[r.typeId]!.isOutOfRange(r.value) ? s('yes') : s('no'),
            s(r.serviceKey),
            r.operatorName,
            r.comment ?? '',
          ],
    ],
  );
}

/// Production journalière + ratios calculés (GOR, WOR, GLR, PI) de chaque
/// puits de [wells], éventuellement limitée à [from]..[to].
ExportTable productionTable(
  WellsState data,
  List<Well> wells,
  String Function(String) s, {
  DateTime? from,
  DateTime? to,
}) {
  String unitOf(String typeId, String fallback) {
    for (final t in data.analysisTypes) {
      if (t.id == typeId) return t.unit;
    }
    return fallback;
  }

  final rows = <List<Object?>>[];
  for (final well in wells) {
    final metrics = ProductionMetrics.fromRecords(
      data.records.where((r) => r.wellId == well.id).toList(),
      reservoirPressure: well.reservoirPressure,
    );
    final piByDay = {for (final p in metrics.series(DerivedRatio.pi)) p.t: p.v};
    for (final d in metrics.days.reversed) {
      if (from != null && d.day.isBefore(DateTime(from.year, from.month, from.day))) continue;
      if (to != null && d.day.isAfter(to)) continue;
      final gor = ProductionMetrics.gor(d);
      final wor = ProductionMetrics.wor(d);
      final glr = ProductionMetrics.glr(d);
      final pi = piByDay[d.day];
      rows.add([
        DateOnly(d.day),
        if (wells.length > 1) _wellLabel(well),
        d.oil,
        d.gas,
        d.water,
        gor == null ? null : roundTo(gor, 3),
        wor == null ? null : roundTo(wor, 4),
        glr == null ? null : roundTo(glr, 3),
        d.pwf,
        well.reservoirPressure,
        pi == null ? null : roundTo(pi, 4),
      ]);
    }
  }

  final oilUnit = unitOf(oilFlowTypeId, 'm³/j');
  final gasUnit = unitOf(gasFlowTypeId, 'Sm³/j');
  final waterUnit = unitOf(waterFlowTypeId, 'm³/j');
  final pressureUnit = unitOf(bottomHolePressureTypeId, 'bar');
  return ExportTable(
    name: s('exportSheetProduction'),
    headers: [
      s('colDate'),
      if (wells.length > 1) s('colWell'),
      '${s('productionOil')} ($oilUnit)',
      '${s('productionGas')} ($gasUnit)',
      '${s('productionWater')} ($waterUnit)',
      s('ratioGor'),
      s('ratioWor'),
      s('ratioGlr'),
      'Pwf ($pressureUnit)',
      'Pr ($pressureUnit)',
      s('ratioPi'),
    ],
    rows: rows,
  );
}

/// Journal des interventions (tous les puits fournis).
ExportTable interventionsTable(WellsState data, List<Intervention> interventions, String Function(String) s) {
  final wellsById = {for (final w in data.wells) w.id: w};
  final sorted = [...interventions]..sort((a, b) => b.date.compareTo(a.date));
  return ExportTable(
    name: s('exportSheetInterventions'),
    headers: [
      s('colDate'),
      s('colWell'),
      s('interventionTypeLabel'),
      s('interventionResultLabel'),
      s('interventionCostLabel'),
      s('interventionCurrencyLabel'),
      s('interventionDescriptionLabel'),
      s('colOperator'),
    ],
    rows: [
      for (final i in sorted)
        [
          DateOnly(i.date),
          _wellLabel(wellsById[i.wellId]),
          s(i.typeKey),
          s(i.resultKey),
          i.cost,
          i.cost == null ? null : i.currency,
          i.description ?? '',
          i.operatorName,
        ],
    ],
  );
}

String _wellLabel(Well? well) => well == null ? '' : '${well.name} (${well.code})';
