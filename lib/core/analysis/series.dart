import 'dart:math' as math;

/// Un point d'une série temporelle (mesure brute ou valeur calculée).
class SeriesPoint {
  final DateTime t;
  final double v;
  const SeriesPoint(this.t, this.v);
}

/// Statistiques descriptives d'une série sur une période — base des tableaux
/// de comparaison (deux puits, ou avant/après une intervention).
class SeriesStats {
  final int count;
  final double mean;
  final double min;
  final double max;
  final double first;
  final double last;

  const SeriesStats({
    required this.count,
    required this.mean,
    required this.min,
    required this.max,
    required this.first,
    required this.last,
  });

  /// `null` si la série est vide.
  static SeriesStats? of(List<SeriesPoint> points) {
    if (points.isEmpty) return null;
    final sorted = [...points]..sort((a, b) => a.t.compareTo(b.t));
    var sum = 0.0;
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final p in sorted) {
      sum += p.v;
      lo = math.min(lo, p.v);
      hi = math.max(hi, p.v);
    }
    return SeriesStats(
      count: sorted.length,
      mean: sum / sorted.length,
      min: lo,
      max: hi,
      first: sorted.first.v,
      last: sorted.last.v,
    );
  }
}

/// Variation relative de [from] vers [to], en % (`null` si [from] vaut 0).
double? percentChange(double from, double to) {
  if (from == 0) return null;
  return (to - from) / from.abs() * 100;
}

/// Minuit (heure locale) du jour de [t].
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Points de [points] compris entre [start] et [end] (jours entiers inclus).
List<SeriesPoint> clipToRange(List<SeriesPoint> points, DateTime start, DateTime end) {
  final from = dayOf(start);
  final to = dayOf(end).add(const Duration(days: 1));
  return points.where((p) => !p.t.isBefore(from) && p.t.isBefore(to)).toList();
}

/// Formatage lisible d'une valeur calculée : 3 chiffres significatifs pour
/// les petites valeurs, pas de décimales inutiles pour les grandes.
String formatNumber(double value) {
  if (value.isNaN || value.isInfinite) return '—';
  final abs = value.abs();
  if (abs >= 1000) return value.toStringAsFixed(0);
  if (abs >= 100) return value.toStringAsFixed(1);
  if (abs >= 1) return value.toStringAsFixed(2);
  if (abs == 0) return '0';
  return value.toStringAsFixed(3);
}

/// Variation signée en % (ex: "+12,4 %").
String formatPercent(double value, {int decimals = 1}) {
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(decimals)} %';
}
