import '../data/wells_repository.dart';
import '../models/analysis_type.dart';
import '../models/production_types.dart';
import 'production_metrics.dart';
import 'series.dart';

/// Paramètre comparable/traçable : soit un type d'analyse saisi (BSW,
/// débit huile...), soit un ratio calculé (GOR, WOR, GLR, PI).
///
/// [key] est stable et utilisable dans une URL : `type:<id>` ou
/// `ratio:<gor|wor|glr|pi>`.
class MetricOption {
  final String key;
  final String label;
  final String unit;
  final DerivedRatio? ratio;
  final String? typeId;

  const MetricOption._({required this.key, required this.label, required this.unit, this.ratio, this.typeId});

  static String typeKey(String typeId) => 'type:$typeId';
  static String ratioKey(DerivedRatio ratio) => 'ratio:${ratio.storageKey}';
}

/// Tous les paramètres disponibles : débits de production en tête, puis
/// ratios calculés, puis les autres analyses par ordre alphabétique.
List<MetricOption> metricOptions(WellsState data, String Function(String) s) {
  AnalysisType? typeOf(String id) {
    for (final t in data.analysisTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  const productionIds = [oilFlowTypeId, gasFlowTypeId, waterFlowTypeId];
  final options = <MetricOption>[
    for (final id in productionIds)
      if (typeOf(id) != null)
        MetricOption._(key: MetricOption.typeKey(id), label: typeOf(id)!.label, unit: typeOf(id)!.unit, typeId: id),
  ];

  final hasRates = typeOf(oilFlowTypeId) != null;
  if (hasRates) {
    for (final ratio in DerivedRatio.values) {
      options.add(MetricOption._(
        key: MetricOption.ratioKey(ratio),
        label: s(ratio.labelKey),
        unit: ratioUnit(
          ratio,
          oil: typeOf(oilFlowTypeId),
          gas: typeOf(gasFlowTypeId),
          water: typeOf(waterFlowTypeId),
          pwf: typeOf(bottomHolePressureTypeId),
        ),
        ratio: ratio,
      ));
    }
  }

  final others = data.analysisTypes.where((t) => !productionIds.contains(t.id)).toList()
    ..sort((a, b) => a.label.compareTo(b.label));
  for (final t in others) {
    options.add(MetricOption._(key: MetricOption.typeKey(t.id), label: t.label, unit: t.unit, typeId: t.id));
  }
  return options;
}

MetricOption? findMetric(List<MetricOption> options, String? key) {
  if (key == null) return null;
  for (final o in options) {
    if (o.key == key) return o;
  }
  return null;
}

/// Série complète (toutes dates) d'un paramètre pour un puits, triée par
/// date. Pour un type d'analyse : chaque saisie est un point. Pour un ratio :
/// un point par jour où il est calculable.
List<SeriesPoint> metricSeries(WellsState data, String wellId, MetricOption metric) {
  final wellRecords = data.records.where((r) => r.wellId == wellId).toList();
  if (metric.ratio != null) {
    double? pr;
    for (final w in data.wells) {
      if (w.id == wellId) pr = w.reservoirPressure;
    }
    return ProductionMetrics.fromRecords(wellRecords, reservoirPressure: pr).series(metric.ratio!);
  }
  final points = [
    for (final r in wellRecords)
      if (r.typeId == metric.typeId) SeriesPoint(r.dateTime, r.value),
  ]..sort((a, b) => a.t.compareTo(b.t));
  return points;
}
