import 'dart:math' as math;

/// Statistiques d'une carte de contrôle (écarts autour de 0).
class ControlStats {
  final double mean, sd;
  const ControlStats(this.mean, this.sd);
  double get ucl2 => mean + 2 * sd;
  double get lcl2 => mean - 2 * sd;
  double get ucl3 => mean + 3 * sd;
  double get lcl3 => mean - 3 * sd;
}

ControlStats? controlStats(List<double> v) {
  if (v.length < 2) return null;
  final mean = v.reduce((a, b) => a + b) / v.length;
  final sd = math.sqrt(v.fold<double>(0, (a, e) => a + (e - mean) * (e - mean)) / (v.length - 1));
  return ControlStats(mean, sd);
}

/// Règles de détection de dérive (type Western Electric) sur les écarts à la
/// référence, appliquées dès 8 mesures. Retourne les anomalies trouvées :
///  - 7 mesures consécutives du même côté de la référence, avec un biais
///    moyen d'au moins 30 % de la tolérance → biais systématique ;
///  - 6 mesures consécutives croissantes ou décroissantes → tendance ;
///  - 1 mesure au-delà de 3σ de toutes les autres → valeur aberrante.
List<String> controlViolations(List<double> errors, double tolerance) {
  final out = <String>[];
  final n = errors.length;
  if (n < 8) return out;

  var run = 1;
  var bestRun = 1;
  for (var i = 1; i < n; i++) {
    final same = errors[i] != 0 && errors[i - 1] != 0 && (errors[i] > 0) == (errors[i - 1] > 0);
    run = same ? run + 1 : 1;
    if (run > bestRun) bestRun = run;
  }
  final meanAbs = errors.map((e) => e.abs()).reduce((a, b) => a + b) / n;
  if (bestRun >= 7 && meanAbs >= tolerance * 0.3) out.add('biais systématique ($bestRun mesures du même côté)');

  var up = 1, down = 1, trend = 1;
  for (var i = 1; i < n; i++) {
    up = errors[i] > errors[i - 1] ? up + 1 : 1;
    down = errors[i] < errors[i - 1] ? down + 1 : 1;
    trend = math.max(trend, math.max(up, down));
  }
  if (trend >= 6) out.add('tendance ($trend mesures consécutives dans le même sens)');

  for (var i = 0; i < n; i++) {
    final others = [...errors]..removeAt(i);
    final st = controlStats(others);
    if (st != null && st.sd > 1e-12 && (errors[i] - st.mean).abs() > 3 * st.sd) {
      out.add('valeur aberrante (mesure n° ${i + 1})');
      break;
    }
  }
  return out;
}
