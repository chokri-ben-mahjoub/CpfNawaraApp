import 'dart:math' as math;

import 'series.dart';

const _daysPerMonth = 30.4375;
const _daysPerYear = 365.25;
const _msPerDay = 86400000.0;

/// Ajustement d'un déclin exponentiel (Arps, b = 0) : q(t) = qi · e^(−D·t),
/// par régression linéaire de ln(q) sur le temps (en jours).
///
/// D > 0 : la production décline ; D < 0 : elle augmente (ex: juste après
/// une stimulation réussie).
class DeclineFit {
  /// Origine des temps de l'ajustement (premier point utilisé).
  final DateTime t0;

  /// Débit ajusté à [t0].
  final double qi;

  /// Taux de déclin nominal, par jour.
  final double dailyRate;

  /// Coefficient de détermination de la régression (sur ln q), entre 0 et 1.
  final double r2;
  final int pointCount;
  final DateTime start;
  final DateTime end;

  const DeclineFit({
    required this.t0,
    required this.qi,
    required this.dailyRate,
    required this.r2,
    required this.pointCount,
    required this.start,
    required this.end,
  });

  double _days(DateTime t) => t.difference(t0).inMilliseconds / _msPerDay;

  /// Débit prévu par le modèle à la date [t].
  double rateAt(DateTime t) => qi * math.exp(-dailyRate * _days(t));

  bool get isDeclining => dailyRate > 0;

  /// Déclin nominal en % par mois / par an (D × durée).
  double get nominalMonthlyPct => dailyRate * _daysPerMonth * 100;
  double get nominalAnnualPct => dailyRate * _daysPerYear * 100;

  /// Déclin effectif en % : baisse réelle du débit sur un mois / un an
  /// (1 − e^(−D·durée)) — la valeur la plus parlante pour l'exploitation.
  double get effectiveMonthlyPct => (1 - math.exp(-dailyRate * _daysPerMonth)) * 100;
  double get effectiveAnnualPct => (1 - math.exp(-dailyRate * _daysPerYear)) * 100;

  /// Volume cumulé prévu entre [from] et [to] (intégrale de q(t), débit
  /// exprimé par jour → volume).
  double cumulativeBetween(DateTime from, DateTime to) {
    final a = _days(from);
    final b = _days(to);
    if (dailyRate.abs() < 1e-12) return qi * (b - a);
    return qi / dailyRate * (math.exp(-dailyRate * a) - math.exp(-dailyRate * b));
  }

  /// Nombre de jours (depuis [from]) avant d'atteindre le débit [limit] ;
  /// `null` si jamais atteint (pas de déclin) ou déjà dépassé.
  double? daysUntilRate(double limit, DateTime from) {
    if (!isDeclining || limit <= 0) return null;
    final current = rateAt(from);
    if (current <= limit) return null;
    return math.log(current / limit) / dailyRate;
  }
}

/// Ajuste un déclin exponentiel sur [points] (débits > 0 uniquement).
/// Retourne `null` s'il n'y a pas assez de données exploitables : au moins 3
/// points positifs répartis sur au moins 2 jours différents.
DeclineFit? fitExponentialDecline(List<SeriesPoint> points) {
  final usable = points.where((p) => p.v > 0).toList()..sort((a, b) => a.t.compareTo(b.t));
  if (usable.length < 3) return null;
  final t0 = usable.first.t;
  final xs = [for (final p in usable) p.t.difference(t0).inMilliseconds / _msPerDay];
  final ys = [for (final p in usable) math.log(p.v)];
  if (xs.last - xs.first < 1) return null;

  final n = usable.length;
  final meanX = xs.reduce((a, b) => a + b) / n;
  final meanY = ys.reduce((a, b) => a + b) / n;
  var sxx = 0.0;
  var sxy = 0.0;
  var syy = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - meanX;
    final dy = ys[i] - meanY;
    sxx += dx * dx;
    sxy += dx * dy;
    syy += dy * dy;
  }
  if (sxx == 0) return null;
  final slope = sxy / sxx;
  final intercept = meanY - slope * meanX;
  // Toutes les valeurs identiques : ajustement parfait d'un débit constant.
  final r2 = syy == 0 ? 1.0 : (sxy * sxy) / (sxx * syy);

  return DeclineFit(
    t0: t0,
    qi: math.exp(intercept),
    dailyRate: -slope,
    r2: r2,
    pointCount: n,
    start: usable.first.t,
    end: usable.last.t,
  );
}

/// Fenêtre de données utilisée pour l'ajustement du déclin.
enum DeclineWindow { auto, days90, days180, days365, all }

extension DeclineWindowX on DeclineWindow {
  String get labelKey {
    switch (this) {
      case DeclineWindow.auto:
        return 'declineWindowAuto';
      case DeclineWindow.days90:
        return 'period90';
      case DeclineWindow.days180:
        return 'period180';
      case DeclineWindow.days365:
        return 'period365';
      case DeclineWindow.all:
        return 'periodAll';
    }
  }
}

class DeclineResult {
  final DeclineFit? fit;

  /// Points retenus pour l'ajustement.
  final List<SeriesPoint> used;

  /// Tout l'historique du débit (pour le contexte sur le graphique).
  final List<SeriesPoint> all;

  /// Vrai si la fenêtre "auto" a démarré après la dernière intervention.
  final bool sinceIntervention;

  const DeclineResult({required this.fit, required this.used, required this.all, required this.sinceIntervention});
}

/// Choisit les points selon [window] puis ajuste le déclin.
///
/// En mode `auto`, l'ajustement démarre le lendemain de la dernière
/// intervention (une stimulation ou un workover "remet à zéro" le déclin)
/// s'il reste au moins 3 mesures depuis ; sinon tout l'historique est utilisé.
DeclineResult analyzeDecline(
  List<SeriesPoint> rates, {
  required DeclineWindow window,
  DateTime? lastInterventionDate,
  DateTime? now,
}) {
  final today = dayOf(now ?? DateTime.now());
  final sorted = [...rates]..sort((a, b) => a.t.compareTo(b.t));
  var sinceIntervention = false;
  List<SeriesPoint> used;
  switch (window) {
    case DeclineWindow.auto:
      used = sorted;
      if (lastInterventionDate != null) {
        final after = sorted.where((p) => p.t.isAfter(dayOf(lastInterventionDate).add(const Duration(hours: 23)))).toList();
        if (after.where((p) => p.v > 0).length >= 3) {
          used = after;
          sinceIntervention = true;
        }
      }
    case DeclineWindow.days90:
      used = sorted.where((p) => !p.t.isBefore(today.subtract(const Duration(days: 89)))).toList();
    case DeclineWindow.days180:
      used = sorted.where((p) => !p.t.isBefore(today.subtract(const Duration(days: 179)))).toList();
    case DeclineWindow.days365:
      used = sorted.where((p) => !p.t.isBefore(today.subtract(const Duration(days: 364)))).toList();
    case DeclineWindow.all:
      used = sorted;
  }
  return DeclineResult(
    fit: fitExponentialDecline(used),
    used: used,
    all: sorted,
    sinceIntervention: sinceIntervention,
  );
}
