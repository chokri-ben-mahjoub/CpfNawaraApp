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
  'ph': 'ASTM D 1293',
  'salinity': 'ASTM D 1125',
  'tds': 'ASTM D 1125',
  'conductivity': 'ASTM D 1125',
  'concentration': 'Automatic titration',
  'foam': 'ASTM D 1881',
};

String? astmMethodFor(String paramKey) => _astmMethodByParamKey[paramKey];
