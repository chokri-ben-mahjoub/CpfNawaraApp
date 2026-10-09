/// Système d'unités affiché : SI (bar, °C, m³/j, kg/m³), tel qu'enregistré
/// en base, ou unités pétrolières API (psi, °F, bbl/j, °API).
///
/// La base locale et Firestore restent toujours en SI : la conversion se
/// fait à la lecture (contrôleurs) et à l'écriture (saisie, seuils), si bien
/// que tous les écrans, courbes et exports suivent le réglage sans calcul
/// supplémentaire.
enum UnitSystem { si, api }

extension UnitSystemX on UnitSystem {
  String get labelKey => switch (this) {
    UnitSystem.si => 'unitsSi',
    UnitSystem.api => 'unitsApi',
  };

  static UnitSystem fromKey(String? key) => key == 'api' ? UnitSystem.api : UnitSystem.si;
}

class _Rule {
  final String unit;
  final double Function(double) toDisplay;
  final double Function(double) toSi;

  /// Conversion décroissante (ex: masse volumique → °API) : un minimum
  /// devient un maximum.
  final bool inverts;

  const _Rule(this.unit, this.toDisplay, this.toSi, {this.inverts = false});
}

double _api(double kgm3) => kgm3 <= 0 ? 0 : 141.5 / (kgm3 / 999.016) - 131.5;
double _kgm3(double api) => 141.5 / (api + 131.5) * 999.016;

/// Unités SI converties en API (les autres — %, ppm, mg/L, mol %... — ne
/// changent pas).
final _rules = <String, _Rule>{
  'bar': _Rule('psi', (v) => v * 14.5037738, (v) => v / 14.5037738),
  '°C': _Rule('°F', (v) => v * 9 / 5 + 32, (v) => (v - 32) * 5 / 9),
  'm³/j': _Rule('bbl/j', (v) => v * 6.28981077, (v) => v / 6.28981077),
  'Sm³/j': _Rule('scf/j', (v) => v * 35.3146667, (v) => v / 35.3146667),
  'kg/m³': _Rule('°API', _api, _kgm3, inverts: true),
};

/// Conversion globale, réglée au démarrage d'après les Réglages (comme le
/// format CSV) et lue par les contrôleurs de données.
class Units {
  Units._();

  static UnitSystem system = UnitSystem.si;

  static _Rule? _rule(String siUnit) => system == UnitSystem.api ? _rules[siUnit.trim()] : null;

  /// Unité affichée pour une unité enregistrée en SI.
  static String unit(String siUnit) => _rule(siUnit)?.unit ?? siUnit;

  /// Unité SI correspondant à une unité saisie à l'écran (ex: "psi" en mode
  /// API → "bar") ; inchangée sinon.
  static String siUnitFor(String displayUnit) {
    if (system == UnitSystem.api) {
      for (final entry in _rules.entries) {
        if (entry.value.unit == displayUnit.trim()) return entry.key;
      }
    }
    return displayUnit;
  }

  /// Valeur affichée pour une valeur enregistrée en SI.
  static double display(double value, String siUnit) => _rule(siUnit)?.toDisplay(value) ?? value;

  static double? displayOrNull(double? value, String siUnit) => value == null ? null : display(value, siUnit);

  /// Valeur saisie (unité affichée) ramenée en SI pour l'enregistrement —
  /// arrondie à 9 chiffres significatifs pour qu'un aller-retour ne
  /// transforme pas 20 en 19,999999998.
  static double toSi(double value, String siUnit) {
    final rule = _rule(siUnit);
    if (rule == null) return value;
    return _round(rule.toSi(value));
  }

  static double? toSiOrNull(double? value, String siUnit) => value == null ? null : toSi(value, siUnit);

  /// Bornes [min, max] converties, remises dans l'ordre si la conversion est
  /// décroissante.
  static (double, double) range(double min, double max, String siUnit) {
    final rule = _rule(siUnit);
    if (rule == null) return (min, max);
    final a = rule.toDisplay(min);
    final b = rule.toDisplay(max);
    return rule.inverts ? (b, a) : (a, b);
  }

  /// Bornes saisies (unité affichée) ramenées en SI, dans l'ordre.
  static (double?, double?) rangeToSi(double? min, double? max, String siUnit) {
    final rule = _rule(siUnit);
    if (rule == null) return (min, max);
    final a = min == null ? null : _round(rule.toSi(min));
    final b = max == null ? null : _round(rule.toSi(max));
    return rule.inverts ? (b, a) : (a, b);
  }

  /// Bornes facultatives converties (seuils d'un point de l'usine).
  static (double?, double?) rangeOrNull(double? min, double? max, String siUnit) {
    final rule = _rule(siUnit);
    if (rule == null) return (min, max);
    final a = min == null ? null : rule.toDisplay(min);
    final b = max == null ? null : rule.toDisplay(max);
    return rule.inverts ? (b, a) : (a, b);
  }

  static double _round(double v) {
    if (v == 0 || v.isNaN || v.isInfinite) return v;
    return double.parse(v.toStringAsPrecision(9));
  }
}
