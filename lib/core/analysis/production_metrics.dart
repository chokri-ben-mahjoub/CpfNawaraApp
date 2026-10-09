import '../models/analysis_record.dart';
import '../models/analysis_type.dart';
import '../models/production_types.dart';
import 'series.dart';

/// Ratios calculés automatiquement à partir des débits saisis.
enum DerivedRatio { gor, wor, glr, pi }

extension DerivedRatioX on DerivedRatio {
  String get storageKey => name;

  /// Clé de traduction du nom court (GOR, WOR...).
  String get labelKey => 'ratio${name[0].toUpperCase()}${name.substring(1)}';

  /// Clé de traduction de la définition (affichée sous la valeur).
  String get descriptionKey => '${labelKey}Desc';

  static DerivedRatio? fromKey(String key) {
    for (final r in DerivedRatio.values) {
      if (r.name == key) return r;
    }
    return null;
  }
}

/// Production d'un puits pour un jour donné : dernière valeur saisie ce
/// jour-là pour chaque débit, et pression de fond si mesurée.
class DailyProduction {
  final DateTime day;
  final double? oil;
  final double? gas;
  final double? water;
  final double? pwf;

  const DailyProduction({required this.day, this.oil, this.gas, this.water, this.pwf});
}

/// Nombre de jours pendant lesquels un débit reste "valable" pour le calcul
/// du PI quand la pression de fond est mesurée un jour sans saisie de débit
/// (mesures rarement faites exactement le même jour).
const _piRateCarryDays = 3;

/// Calculs de production d'un puits (ratios, séries journalières).
class ProductionMetrics {
  final List<DailyProduction> days;
  final double? reservoirPressure;

  ProductionMetrics._(this.days, this.reservoirPressure);

  /// [records] : toutes les analyses du puits (tous types confondus).
  factory ProductionMetrics.fromRecords(List<AnalysisRecord> records, {double? reservoirPressure}) {
    final relevant = records
        .where((r) =>
            r.typeId == oilFlowTypeId ||
            r.typeId == gasFlowTypeId ||
            r.typeId == waterFlowTypeId ||
            r.typeId == bottomHolePressureTypeId)
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final byDay = <DateTime, Map<String, double>>{};
    for (final r in relevant) {
      // Tri chronologique : la dernière saisie du jour écrase les précédentes.
      (byDay[dayOf(r.dateTime)] ??= {})[r.typeId] = r.value;
    }
    final sortedDays = byDay.keys.toList()..sort();
    final days = [
      for (final day in sortedDays)
        DailyProduction(
          day: day,
          oil: byDay[day]![oilFlowTypeId],
          gas: byDay[day]![gasFlowTypeId],
          water: byDay[day]![waterFlowTypeId],
          pwf: byDay[day]![bottomHolePressureTypeId],
        ),
    ];
    return ProductionMetrics._(days, reservoirPressure);
  }

  static double? gor(DailyProduction d) {
    if (d.oil == null || d.gas == null || d.oil! <= 0) return null;
    return d.gas! / d.oil!;
  }

  static double? wor(DailyProduction d) {
    if (d.oil == null || d.water == null || d.oil! <= 0) return null;
    return d.water! / d.oil!;
  }

  static double? glr(DailyProduction d) {
    if (d.oil == null || d.water == null || d.gas == null) return null;
    final liquid = d.oil! + d.water!;
    if (liquid <= 0) return null;
    return d.gas! / liquid;
  }

  /// Série journalière d'un ratio (jours où il est calculable).
  List<SeriesPoint> series(DerivedRatio ratio) {
    switch (ratio) {
      case DerivedRatio.gor:
        return _simple(gor);
      case DerivedRatio.wor:
        return _simple(wor);
      case DerivedRatio.glr:
        return _simple(glr);
      case DerivedRatio.pi:
        return _piSeries();
    }
  }

  List<SeriesPoint> _simple(double? Function(DailyProduction) f) => [
        for (final d in days)
          if (f(d) != null) SeriesPoint(d.day, f(d)!),
      ];

  /// PI = débit liquide / (Pr − Pwf), calculé les jours où Pwf est mesurée.
  /// Les débits huile/eau utilisés sont ceux du même jour, ou à défaut les
  /// derniers saisis dans les [_piRateCarryDays] jours précédents.
  List<SeriesPoint> _piSeries() {
    final pr = reservoirPressure;
    if (pr == null) return const [];
    final result = <SeriesPoint>[];
    double? lastOil;
    double? lastWater;
    DateTime? lastOilDay;
    DateTime? lastWaterDay;
    for (final d in days) {
      if (d.oil != null) {
        lastOil = d.oil;
        lastOilDay = d.day;
      }
      if (d.water != null) {
        lastWater = d.water;
        lastWaterDay = d.day;
      }
      if (d.pwf == null) continue;
      final drawdown = pr - d.pwf!;
      if (drawdown <= 0) continue;
      final oilOk = lastOilDay != null && d.day.difference(lastOilDay).inDays <= _piRateCarryDays;
      if (!oilOk) continue;
      final waterOk = lastWaterDay != null && d.day.difference(lastWaterDay).inDays <= _piRateCarryDays;
      final liquid = lastOil! + (waterOk ? lastWater! : 0);
      result.add(SeriesPoint(d.day, liquid / drawdown));
    }
    return result;
  }

  /// Série journalière d'un débit (dernière valeur du jour).
  List<SeriesPoint> rateSeries(String typeId) {
    double? pick(DailyProduction d) {
      switch (typeId) {
        case oilFlowTypeId:
          return d.oil;
        case gasFlowTypeId:
          return d.gas;
        case waterFlowTypeId:
          return d.water;
        case bottomHolePressureTypeId:
          return d.pwf;
      }
      return null;
    }

    return [
      for (final d in days)
        if (pick(d) != null) SeriesPoint(d.day, pick(d)!),
    ];
  }

  /// Dernière valeur calculable d'un ratio, et la précédente (pour la
  /// tendance).
  (SeriesPoint? latest, SeriesPoint? previous) latest(DerivedRatio ratio) {
    final s = series(ratio);
    if (s.isEmpty) return (null, null);
    return (s.last, s.length > 1 ? s[s.length - 2] : null);
  }
}

/// Unité d'un ratio, déduite des unités configurées pour les débits (ex:
/// "Sm³/j" ÷ "m³/j" → "Sm³/m³").
String ratioUnit(DerivedRatio ratio, {AnalysisType? oil, AnalysisType? gas, AnalysisType? water, AnalysisType? pwf}) {
  String volume(AnalysisType? t, String fallback) {
    final unit = t?.unit ?? fallback;
    return unit.endsWith('/j') ? unit.substring(0, unit.length - 2) : unit;
  }

  switch (ratio) {
    case DerivedRatio.gor:
      return '${volume(gas, 'Sm³')}/${volume(oil, 'm³')}';
    case DerivedRatio.wor:
      return '${volume(water, 'm³')}/${volume(oil, 'm³')}';
    case DerivedRatio.glr:
      return '${volume(gas, 'Sm³')}/${volume(oil, 'm³')}';
    case DerivedRatio.pi:
      return '${oil?.unit ?? 'm³/j'}/${pwf?.unit ?? 'bar'}';
  }
}
