/// Une date sans heure (ex: date d'intervention, ligne de production
/// journalière) : exportée en vraie date Excel au format jour/mois/année,
/// contrairement à un [DateTime] qui garde l'heure.
class DateOnly {
  final DateTime date;
  const DateOnly(this.date);
}

/// Un tableau à exporter : une feuille Excel, ou un fichier CSV.
///
/// Les cellules de [rows] peuvent être des `String`, des nombres (`num`,
/// exportés en vraies valeurs numériques — triables et calculables dans
/// Excel), des `DateTime` (date + heure), des [DateOnly] ou `null` (cellule
/// vide).
class ExportTable {
  /// Nom de la feuille Excel (31 caractères max) ou suffixe du fichier CSV
  /// quand l'export contient plusieurs tableaux.
  final String name;
  final List<String> headers;
  final List<List<Object?>> rows;

  const ExportTable({required this.name, required this.headers, required this.rows});

  bool get isEmpty => rows.isEmpty;
}

/// Arrondit une valeur calculée (ratio, moyenne, taux...) pour l'export,
/// sans ajouter de zéros inutiles.
double roundTo(double value, int decimals) {
  if (value.isNaN || value.isInfinite) return value;
  final factor = _pow10(decimals);
  return (value * factor).roundToDouble() / factor;
}

double _pow10(int n) {
  var result = 1.0;
  for (var i = 0; i < n; i++) {
    result *= 10;
  }
  return result;
}
