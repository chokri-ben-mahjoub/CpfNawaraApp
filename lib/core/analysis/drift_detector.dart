import 'dart:math' as math;

/// Dérive d'une valeur par rapport aux mesures récentes, même si elle reste
/// dans les seuils (ex: salinité qui double d'un jour à l'autre).
class Drift {
  final double value;
  final double mean;

  /// Écart à la moyenne récente en nombre d'écarts-types.
  final double zScore;
  const Drift({required this.value, required this.mean, required this.zScore});

  /// Variation relative à la moyenne récente, en %.
  double? get percent => mean == 0 ? null : (value - mean) / mean.abs() * 100;
  bool get isUp => value > mean;
}

/// Nombre minimal de mesures précédentes pour juger d'une dérive.
const driftMinHistory = 5;

/// Nombre maximal de mesures précédentes prises en compte.
const driftWindow = 10;

/// Écart (en écarts-types) à partir duquel une valeur est jugée anormale.
const driftThreshold = 3.0;

/// Compare la dernière valeur de [series] (ordre chronologique) à la moyenne
/// des [driftWindow] précédentes. `null` si l'historique est trop court ou si
/// la valeur reste dans la variabilité habituelle.
Drift? detectDrift(List<double> series) {
  if (series.length < driftMinHistory + 1) return null;
  final last = series.last;
  final history = series.sublist(math.max(0, series.length - 1 - driftWindow), series.length - 1);
  final mean = history.reduce((a, b) => a + b) / history.length;
  final variance = history.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / history.length;
  var std = math.sqrt(variance);
  // Série quasi constante : un écart-type nul rendrait toute variation
  // "infinie" ; on exige au moins 5 % de la moyenne comme variabilité.
  final floor = mean.abs() * 0.05;
  if (std < floor) std = floor;
  if (std == 0) return null;
  final z = (last - mean) / std;
  if (z.abs() < driftThreshold) return null;
  return Drift(value: last, mean: mean, zScore: z);
}
