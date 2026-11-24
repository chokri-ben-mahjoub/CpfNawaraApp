import 'plant_catalog.dart';

/// Méthode d'analyse (ASTM ou équivalente) associée à un paramètre du
/// catalogue usine (`plant_catalog.dart`), pour la colonne « Méthode » du
/// rapport PDF modèle OMV. Table statique (non éditable) : ne couvre que
/// les paramètres intégrés dont la méthode normalisée est connue — un
/// paramètre personnalisé ou non listé ici n'affiche simplement rien.
const _astmMethodByParamKey = {
  'density': 'ASTM D 1298',
  'cond_density': 'ASTM D 1298',
  'water_cut': 'ASTM D 6304',
  'bsw': 'ASTM D 4007',
  'chlorides': 'ASTM D 512',
  'tss': 'ASTM D 5907',
  'ph': 'ASTM D 1293',
  'salinity': 'ASTM D 1125',
  'tds': 'ASTM D 1125',
  'conductivity': 'ASTM D 1125',
  'concentration': 'Automatic titration',
  'foam': 'ASTM D 1881',
  'appr_free_condensate': 'Settling',
  'appr_emulsion': 'Settling',
  'appr_sand': 'Settling',
};

String? astmMethodFor(String paramKey) => _astmMethodByParamKey[paramKey];

/// Méthode affichée dans le rapport : celle saisie pour le paramètre
/// (Administration › Paramètres) en priorité, sinon celle d'usine.
String? plantMethodFor(PlantParam param) {
  final own = param.method.trim();
  if (own.isNotEmpty) return own;
  final custom = PlantCustomCatalog.params[param.key]?.method.trim() ?? '';
  return custom.isNotEmpty ? custom : astmMethodFor(param.key);
}

final _methodInLabel = RegExp(r'\(\s*(ASTM\s*D\s*\d+)\s*\)', caseSensitive: false);

/// Méthode écrite dans le nom d'un test, ex. « Chloride (ASTM D512) » →
/// « ASTM D 512 ».
String? methodFromLabel(String label) {
  final m = _methodInLabel.firstMatch(label);
  if (m == null) return null;
  final digits = RegExp(r'\d+').firstMatch(m.group(1)!)!.group(0)!;
  return 'ASTM D $digits';
}

/// Nom du test sans la méthode entre parenthèses (elle a sa colonne).
String labelWithoutMethod(String label) =>
    label.replaceAll(_methodInLabel, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

/// Méthode à afficher pour un test : saisie > lue dans le nom > d'usine.
String? plantMethodShown(PlantParam param, String label) {
  final own = param.method.trim();
  if (own.isNotEmpty) return own;
  final custom = PlantCustomCatalog.params[param.key]?.method.trim() ?? '';
  if (custom.isNotEmpty) return custom;
  final known = methodFromLabel(label) ?? astmMethodFor(param.key);
  if (known != null) return known;
  // Condensat libre, émulsion, sable (même paramètre personnalisé) : essai
  // de décantation.
  final l = label.toLowerCase();
  if (l.contains('free condensate') || l.contains('emulsion') || l.contains('sand') ||
      param.key.contains('free_condensate') || param.key.contains('emulsion') || param.key.contains('sand')) {
    return 'Settling';
  }
  return null;
}
