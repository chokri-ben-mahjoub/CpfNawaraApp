import 'package:flutter/material.dart';

import '../units/unit_system.dart';

/// Module "Usine CPF" : points de prélèvement de l'usine de traitement de
/// gaz et analyses de laboratoire, organisés par circuit.

/// Couleurs des circuits intégrés, aussi utilisées pour les tuyaux du schéma
/// PFD (fixes : le dessin ne suit pas le paramétrage des circuits).
const condensatePipeColor = Color(0xFF9C5B2E);
const waterPipeColor = Color(0xFF1E88E5);
const gasPipeColor = Color(0xFFE8A400);

/// Icônes proposées pour un circuit (Administration > Circuits).
const circuitIconOptions = <String, IconData>{
  'opacity': Icons.opacity,
  'water_drop': Icons.water_drop_outlined,
  'fire': Icons.local_fire_department_outlined,
  'science': Icons.science_outlined,
  'bolt': Icons.bolt,
  'thermostat': Icons.thermostat_outlined,
  'filter': Icons.filter_alt_outlined,
  'air': Icons.air,
  'compress': Icons.compress,
  'factory': Icons.factory_outlined,
  'tank': Icons.propane_tank_outlined,
  'settings': Icons.settings_outlined,
};

IconData circuitIcon(String key) => circuitIconOptions[key] ?? Icons.science_outlined;

/// Couleurs proposées pour un circuit (Administration > Circuits).
const circuitColorOptions = <Color>[
  condensatePipeColor,
  waterPipeColor,
  gasPipeColor,
  Color(0xFF2E9E5B), // vert (amine)
  Color(0xFF8E24AA), // violet
  Color(0xFFD81B60), // rose
  Color(0xFF00897B), // sarcelle
  Color(0xFF5E35B1), // indigo
  Color(0xFF6D4C41), // marron
  Color(0xFF546E7A), // ardoise
];

/// Un circuit de l'usine (table `plant_circuits`) : regroupe des points de
/// prélèvement avec une couleur et une icône pour les écrans liste / alertes
/// / rapports (le schéma PFD, lui, est un dessin fixe indépendant). Les 4
/// circuits intégrés (condensat, eau, gaz, amine) ont un [labelKey] traduit
/// (clé de `app_strings.dart`) ; un circuit ajouté par un administrateur
/// stocke directement son nom dans [labelKey] (texte libre, non traduit,
/// comme le nom d'un point de prélèvement).
class PlantCircuit {
  final String id;
  final String labelKey;
  final int colorValue;
  final String iconKey;
  final String defaultProfile;
  final int sortOrder;

  const PlantCircuit({
    required this.id,
    required this.labelKey,
    required this.colorValue,
    required this.iconKey,
    required this.defaultProfile,
    this.sortOrder = 0,
  });

  Color get color => Color(colorValue);
  IconData get icon => circuitIcon(iconKey);
  String get storageKey => id;

  @override
  bool operator ==(Object other) => other is PlantCircuit && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum ParamKind { number, choice }

/// Un paramètre analysé (une valeur par analyse).
class PlantParam {
  final String key;

  /// Clé de traduction du libellé.
  final String labelKey;
  final String unit;
  final ParamKind kind;

  /// Valeurs possibles (clés de traduction) pour un paramètre à choix
  /// (ex: aspect de l'eau), et celles considérées conformes.
  final List<String> choices;
  final List<String> okChoices;

  /// Unité enregistrée en base, quand [unit] est l'unité convertie pour
  /// l'affichage (voir [displayed]).
  final String? storedUnit;

  /// Unité jamais convertie (ex: masse volumique de l'eau, toujours en
  /// kg/m³ même en unités API).
  final bool fixedUnit;

  /// Paramètre intégré retiré du catalogue par un administrateur (voir
  /// [PlantCustomCatalog]) : n'apparaît plus dans les listes de choix, mais
  /// reste affiché correctement partout où il est déjà utilisé.
  final bool hidden;

  /// Valeur calculée automatiquement (jamais saisie) à partir d'autres
  /// paramètres du même point — voir [plantComputedValues].
  final bool computed;

  const PlantParam(
    this.key,
    this.labelKey,
    this.unit, {
    this.kind = ParamKind.number,
    this.choices = const [],
    this.okChoices = const [],
    this.storedUnit,
    this.fixedUnit = false,
    this.hidden = false,
    this.computed = false,
  });

  bool get isNumeric => kind == ParamKind.number;

  /// Unité enregistrée en base (SI).
  String get siUnit => storedUnit ?? unit;

  /// Unité vraiment convertie à l'affichage (vide si fixe).
  String get _convertible => fixedUnit ? '' : siUnit;

  /// Le même paramètre, avec l'unité du système choisi dans les Réglages.
  PlantParam displayed() {
    if (storedUnit != null || fixedUnit) return this;
    final shown = Units.unit(unit);
    if (shown == unit) return this;
    return PlantParam(key, labelKey, shown, kind: kind, choices: choices, okChoices: okChoices, storedUnit: unit);
  }

  /// Valeur enregistrée (SI) → valeur affichée.
  double toDisplay(double v) => Units.display(v, _convertible);

  /// Valeur saisie → valeur enregistrée (SI).
  double toSi(double v) => Units.toSi(v, _convertible);

  (double?, double?) rangeToDisplay(double? min, double? max) => Units.rangeOrNull(min, max, _convertible);

  (double?, double?) rangeToSi(double? min, double? max) => Units.rangeToSi(min, max, _convertible);
}

// --- Paramètres par type de point ----------------------------------------

const _condensateParams = [
  PlantParam('density', 'plantParamDensity', 'kg/m³'),
  PlantParam('bsw', 'plantParamBsw', '% vol'),
  PlantParam('water_cut', 'plantParamWaterCut', '%'),
  PlantParam('salinity', 'plantParamSalinity', 'mg/L NaCl'),
  PlantParam('chlorides', 'plantParamChlorides', 'mg/L'),
];

const _waterParams = [
  PlantParam('ph', 'plantParamPh', ''),
  PlantParam('density', 'plantParamDensity', 'kg/m³', fixedUnit: true),
  PlantParam('salinity', 'plantParamSalinity', 'g/L NaCl'),
  PlantParam('tds', 'plantParamTds', 'mg/L'),
  PlantParam('tss', 'plantParamTss', 'mg/L'),
  PlantParam(
    'appearance',
    'plantParamAppearance',
    '',
    kind: ParamKind.choice,
    choices: ['plantAppearanceClear', 'plantAppearanceSlightlyTurbid', 'plantAppearanceTurbid', 'plantAppearanceOily'],
    okChoices: ['plantAppearanceClear', 'plantAppearanceSlightlyTurbid'],
  ),
  PlantParam('iron', 'plantParamIron', 'mg/L'),
  PlantParam('tph', 'plantParamTph', 'mg/L'),
  // Perte d'hydrocarbures dans l'eau produite : débit, TPH et densité du
  // condensat saisis, le reste est calculé (voir [plantComputedValues]).
  PlantParam('water_flow', 'plantParamWaterFlow', 'm³/d', fixedUnit: true),
  PlantParam('cond_density', 'plantParamCondDensity', 'kg/m³', fixedUnit: true),
  PlantParam('hc_mass', 'plantParamHcMass', 'kg/d', fixedUnit: true, computed: true),
  PlantParam('hc_mass_t', 'plantParamHcMassT', 't/d', fixedUnit: true, computed: true),
  PlantParam('hc_volume', 'plantParamHcVolume', 'L/d', fixedUnit: true, computed: true),
];

/// Traitement de l'eau de puits (chloration, osmose inverse) : chlore libre
/// résiduel en plus des paramètres d'eau usuels.
const _waterTreatmentParams = [
  PlantParam('free_chlorine', 'plantParamFreeChlorine', 'mg/L'),
  PlantParam('ph', 'plantParamPh', ''),
  PlantParam('salinity', 'plantParamSalinity', 'g/L NaCl'),
  PlantParam('tds', 'plantParamTds', 'mg/L'),
  PlantParam('tss', 'plantParamTss', 'mg/L'),
  PlantParam(
    'appearance',
    'plantParamAppearance',
    '',
    kind: ParamKind.choice,
    choices: ['plantAppearanceClear', 'plantAppearanceSlightlyTurbid', 'plantAppearanceTurbid', 'plantAppearanceOily'],
    okChoices: ['plantAppearanceClear', 'plantAppearanceSlightlyTurbid'],
  ),
];

/// Composition du gaz (chromatographie), en % molaire, + H2S.
const _gasParams = [
  PlantParam('ch4', 'plantParamCh4', 'mol %'),
  PlantParam('c2h6', 'plantParamC2h6', 'mol %'),
  PlantParam('c3h8', 'plantParamC3h8', 'mol %'),
  PlantParam('c4plus', 'plantParamC4plus', 'mol %'),
  PlantParam('co2', 'plantParamCo2', 'mol %'),
  PlantParam('n2', 'plantParamN2', 'mol %'),
  PlantParam('h2s', 'plantParamH2s', 'ppm'),
];

const _exportGasParams = [
  ..._gasParams,
  PlantParam('hc_dew_point', 'plantParamHcDewPoint', '°C'),
  PlantParam('water_dew_point', 'plantParamWaterDewPoint', '°C'),
];

const _amineParams = [
  PlantParam('concentration', 'plantParamConcentration', '% pds'),
  PlantParam('foam', 'plantParamFoam', 'mL'),
  PlantParam('ph', 'plantParamPh', ''),
  PlantParam('pz', 'plantParamPz', '% pds'),
  PlantParam('conductivity', 'plantParamConductivity', 'mS/cm'),
  PlantParam('salinity', 'plantParamSalinity', 'mg/L'),
  PlantParam('co2_loading', 'plantParamCo2Loading', 'mol/mol'),
  PlantParam('tds', 'plantParamTds', 'mg/L'),
  PlantParam('tss', 'plantParamTss', 'mg/L'),
];

/// Modèles intégrés : profil d'un point = liste de ses paramètres (colonne
/// `profile` en base). Un administrateur peut les modifier (table
/// `plant_profiles`, voir [PlantCustomCatalog]).
const builtInPlantProfiles = <String, List<PlantParam>>{
  'condensate': _condensateParams,
  'water': _waterParams,
  'gas': _gasParams,
  'gas_export': _exportGasParams,
  'amine': _amineParams,
  'water_treatment': _waterTreatmentParams,
};

/// Modèle de paramètres défini par l'administrateur (table
/// `plant_profiles`) : nouveau modèle, ou modèle intégré modifié (même id).
class PlantProfileDef {
  final String id;

  /// Nom libre, ou clé de traduction (modèle intégré non renommé).
  final String label;
  final List<String> paramKeys;
  final int sortOrder;

  const PlantProfileDef({required this.id, required this.label, required this.paramKeys, this.sortOrder = 0});

  bool get builtIn => builtInPlantProfiles.containsKey(id);
}

/// Paramètres personnalisés et modèles modifiés, chargés depuis la base par
/// `PlantController` : consultés par [paramsForProfile], [plantParamByKey],
/// [plantParamCatalog] et [plantProfileLabelKeys].
class PlantCustomCatalog {
  static Map<String, PlantParam> params = const {};
  static Map<String, PlantProfileDef> profiles = const {};
}

/// Paramètres d'un modèle : liste modifiée par l'administrateur, sinon
/// intégrée — dans les deux cas, chaque paramètre passe par [_paramIn] pour
/// tenir compte d'une éventuelle surcharge (renommage, nouvelle unité...).
List<PlantParam> paramsForProfile(String profile) {
  final custom = PlantCustomCatalog.profiles[profile];
  final builtIn = builtInPlantProfiles[profile];
  final keys = custom?.paramKeys ?? [for (final p in builtIn ?? const <PlantParam>[]) p.key];
  return [for (final key in keys) ?_paramIn(key, builtIn)];
}

/// Modèles intégrés d'origine (libellé = clé de traduction).
const builtInProfileLabelKeys = {
  'condensate': 'plantProfileCondensate',
  'water': 'plantProfileWater',
  'gas': 'plantProfileGas',
  'gas_export': 'plantProfileGasExport',
  'amine': 'plantProfileAmine',
  'water_treatment': 'plantProfileWaterTreatment',
};

/// Modèles proposés (id -> libellé ou clé de traduction) : intégrés, puis
/// ceux ajoutés par l'administrateur.
Map<String, String> get plantProfileLabelKeys {
  final custom = PlantCustomCatalog.profiles;
  final added = custom.values.where((d) => !d.builtIn).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return {
    for (final e in builtInProfileLabelKeys.entries) e.key: custom[e.key]?.label ?? e.value,
    for (final d in added) d.id: d.label,
  };
}

/// Paramètres intégrés (un par clé).
final List<PlantParam> builtInParamCatalog = () {
  final seen = <String>{};
  return [
    for (final list in builtInPlantProfiles.values)
      for (final p in list)
        if (seen.add(p.key)) p,
  ];
}();

/// Tous les paramètres à proposer dans les listes de choix (modèle, point) :
/// intégrés (remplacés par leur surcharge s'il y en a une, retirés s'ils
/// sont masqués) puis personnalisés — jamais de doublon de clé.
List<PlantParam> get plantParamCatalog {
  final overrides = PlantCustomCatalog.params;
  return [
    for (final p in builtInParamCatalog)
      if (overrides[p.key] == null)
        p
      else if (!overrides[p.key]!.hidden)
        overrides[p.key]!,
    for (final p in overrides.values)
      if (!builtInParamCatalog.any((b) => b.key == p.key) && !p.hidden) p,
  ];
}

/// Paramètres intégrés retirés du catalogue (masqués), pour l'écran
/// Administration qui permet de les réafficher.
List<PlantParam> get hiddenBuiltInParams => [
  for (final p in builtInParamCatalog)
    if (PlantCustomCatalog.params[p.key]?.hidden ?? false) p,
];

PlantParam? _paramIn(String key, List<PlantParam>? preferred) {
  final override = PlantCustomCatalog.params[key];
  if (override != null) return override;
  for (final p in preferred ?? const <PlantParam>[]) {
    if (p.key == key) return p;
  }
  for (final p in builtInParamCatalog) {
    if (p.key == key) return p;
  }
  return null;
}

/// Définition d'un paramètre : celle du profil du point en priorité (unités
/// propres au circuit), sinon celle du catalogue.
PlantParam? plantParamByKey(String key, {String? profile}) {
  for (final p in paramsForProfile(profile ?? '')) {
    if (p.key == key) return p;
  }
  return _paramIn(key, builtInPlantProfiles[profile]);
}

/// Paramètre personnalisé (ou surcharge d'un paramètre intégré) : libellé et
/// choix en texte libre, unité jamais convertie.
PlantParam customPlantParam({
  required String key,
  required String label,
  required String unit,
  ParamKind kind = ParamKind.number,
  List<String> choices = const [],
  List<String> okChoices = const [],
  bool hidden = false,
}) => PlantParam(key, label, unit, kind: kind, choices: choices, okChoices: okChoices, fixedUnit: true, hidden: hidden);

bool isCustomPlantParam(String key) => PlantCustomCatalog.params.containsKey(key);

/// Paramètres "composition" du gaz, regroupés à l'écran.
const gasCompositionKeys = {'ch4', 'c2h6', 'c3h8', 'c4plus', 'co2', 'n2'};

/// Circuits de départ (table `plant_circuits`) : ids stables, identiques sur
/// tous les appareils (synchronisation) — les points existants y font déjà
/// référence par ces mêmes ids.
const plantSeedCircuits = [
  {
    'id': 'condensate',
    'label_key': 'plantCircuitCondensate',
    'color': 0xFF9C5B2E,
    'icon': 'opacity',
    'default_profile': 'condensate',
    'sort_order': 1,
  },
  {
    'id': 'water',
    'label_key': 'plantCircuitWater',
    'color': 0xFF1E88E5,
    'icon': 'water_drop',
    'default_profile': 'water',
    'sort_order': 2,
  },
  {
    'id': 'gas',
    'label_key': 'plantCircuitGas',
    'color': 0xFFE8A400,
    'icon': 'fire',
    'default_profile': 'gas',
    'sort_order': 3,
  },
  {
    'id': 'amine',
    'label_key': 'plantCircuitAmine',
    'color': 0xFF2E9E5B,
    'icon': 'science',
    'default_profile': 'amine',
    'sort_order': 4,
  },
  {
    'id': 'water_treatment',
    'label_key': 'plantCircuitWaterTreatment',
    'color': 0xFF00897B,
    'icon': 'filter',
    'default_profile': 'water_treatment',
    'sort_order': 5,
  },
];

/// Points de prélèvement de départ (table `sample_points`) : ids stables,
/// identiques sur tous les appareils (synchronisation).
const plantSeedPoints = [
  {
    'id': 'pp_c1',
    'code': 'C1',
    'circuit': 'condensate',
    'name': 'Inlet Separator',
    'equipment': 'Séparateur d\'entrée',
    'profile': 'condensate',
    'sort_order': 1,
  },
  {
    'id': 'pp_c2',
    'code': 'C2',
    'circuit': 'condensate',
    'name': 'Test Separator',
    'equipment': 'Séparateur de test',
    'profile': 'condensate',
    'sort_order': 2,
  },
  {
    'id': 'pp_c3',
    'code': 'C3',
    'circuit': 'condensate',
    'name': 'Avant Reboiler',
    'equipment': 'Rebouilleur condensat',
    'profile': 'condensate',
    'sort_order': 3,
  },
  {
    'id': 'pp_c4',
    'code': 'C4',
    'circuit': 'condensate',
    'name': 'Storage Tank',
    'equipment': 'Bac de stockage',
    'profile': 'condensate',
    'sort_order': 4,
  },
  {
    'id': 'pp_w1',
    'code': 'W1',
    'circuit': 'water',
    'name': 'Test Separator',
    'equipment': 'Séparateur de test',
    'profile': 'water',
    'sort_order': 5,
  },
  {
    'id': 'pp_w2',
    'code': 'W2',
    'circuit': 'water',
    'name': 'Inlet Separator',
    'equipment': 'Séparateur d\'entrée',
    'profile': 'water',
    'sort_order': 6,
  },
  {
    'id': 'pp_w3',
    'code': 'W3',
    'circuit': 'water',
    'name': 'W/C Separator',
    'equipment': 'Séparateur eau/condensat',
    'profile': 'water',
    'sort_order': 7,
  },
  {
    'id': 'pp_w4',
    'code': 'W4',
    'circuit': 'water',
    'name': 'Inlet Separator Water (vers W/C)',
    'equipment': 'Sortie eau séparateur d\'entrée',
    'profile': 'water',
    'sort_order': 8,
  },
  {
    'id': 'pp_g1',
    'code': 'G1',
    'circuit': 'gas',
    'name': 'Test Separator',
    'equipment': 'Séparateur de test',
    'profile': 'gas',
    'sort_order': 9,
  },
  {
    'id': 'pp_g2',
    'code': 'G2',
    'circuit': 'gas',
    'name': 'Inlet Separator',
    'equipment': 'Séparateur d\'entrée',
    'profile': 'gas',
    'sort_order': 10,
  },
  {
    'id': 'pp_g3',
    'code': 'G3',
    'circuit': 'gas',
    'name': 'Export Gas',
    'equipment': 'Gaz export (après TEG)',
    'profile': 'gas_export',
    'sort_order': 11,
  },
  {
    'id': 'pp_la',
    'code': 'LA',
    'circuit': 'amine',
    'name': 'Lean Amine',
    'equipment': 'Pompe HP',
    'profile': 'amine',
    'sort_order': 12,
  },
  {
    'id': 'pp_ra',
    'code': 'RA',
    'circuit': 'amine',
    'name': 'Rich Amine',
    'equipment': 'Flash Drum',
    'profile': 'amine',
    'sort_order': 13,
  },
  // Traitement de l'eau de puits (chloration, osmose inverse).
  {
    'id': 'pp_wt1',
    'code': 'WT1',
    'circuit': 'water_treatment',
    'name': 'Well Water',
    'equipment': 'Puits (eau brute)',
    'profile': 'water_treatment',
    'sort_order': 14,
  },
  {
    'id': 'pp_wt2',
    'code': 'WT2',
    'circuit': 'water_treatment',
    'name': 'Chlorination Unit',
    'equipment': 'Dosage chlore (NaOCl)',
    'profile': 'water_treatment',
    'sort_order': 15,
  },
  {
    'id': 'pp_wt3',
    'code': 'WT3',
    'circuit': 'water_treatment',
    'name': 'Plant Water',
    'equipment': 'Eau usine (après chloration)',
    'profile': 'water_treatment',
    'sort_order': 16,
  },
  {
    'id': 'pp_wt4',
    'code': 'WT4',
    'circuit': 'water_treatment',
    'name': 'Plant Water Storage Tank',
    'equipment': 'Bac de stockage eau usine (TK/TKB)',
    'profile': 'water_treatment',
    'sort_order': 17,
  },
  {
    'id': 'pp_wt5',
    'code': 'WT5',
    'circuit': 'water_treatment',
    'name': 'RO Unit Outlet',
    'equipment': 'Sortie unité d\'osmose inverse',
    'profile': 'water_treatment',
    'sort_order': 18,
  },
  {
    'id': 'pp_wt6',
    'code': 'WT6',
    'circuit': 'water_treatment',
    'name': 'Fresh Water Storage Tank',
    'equipment': 'Bac de stockage eau douce',
    'profile': 'water_treatment',
    'sort_order': 19,
  },
  {
    'id': 'pp_wt7',
    'code': 'WT7',
    'circuit': 'water_treatment',
    'name': 'Aquifer / Reject Water',
    'equipment': 'Rejet aquifère (concentrat RO)',
    'profile': 'water_treatment',
    'sort_order': 20,
  },
];

/// Origine d'une analyse.
const plantSources = ['plantSourceLab', 'plantSourceField', 'plantSourceImport'];

/// Paramètres calculés à partir des valeurs saisies [v] d'un point (clé ->
/// valeur). Pertes d'hydrocarbures dans l'eau produite :
/// * masse (kg/j) = débit d'eau (m³/j) × TPH (mg/L) / 1000
///   (m³ → 1000 L, mg → kg : 1e-6), soit (débit × TPH) / 1 000 000 en t/j ;
/// * volume (L/j) = masse (kg/j) / densité du condensat (kg/m³) × 1000.
/// Un résultat n'est donné que si toutes les valeurs nécessaires sont
/// présentes (densité > 0 pour le volume).
Map<String, double> plantComputedValues(Map<String, double> v) {
  final flow = v['water_flow'];
  final tph = v['tph'];
  final density = v['cond_density'];
  final out = <String, double>{};
  if (flow == null || tph == null) return out;
  final kg = flow * tph / 1000;
  out['hc_mass'] = kg;
  out['hc_mass_t'] = flow * tph / 1000000;
  if (density != null && density > 0) out['hc_volume'] = kg / density * 1000;
  return out;
}
