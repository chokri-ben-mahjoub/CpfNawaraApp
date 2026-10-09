import 'package:flutter/material.dart';

import '../units/unit_system.dart';

/// Module "Usine CPF" : points de prélèvement de l'usine de traitement de
/// gaz et analyses de laboratoire, organisés par circuit.

enum PlantCircuit { condensate, water, gas, amine }

extension PlantCircuitX on PlantCircuit {
  String get storageKey => name;

  String get labelKey => switch (this) {
    PlantCircuit.condensate => 'plantCircuitCondensate',
    PlantCircuit.water => 'plantCircuitWater',
    PlantCircuit.gas => 'plantCircuitGas',
    PlantCircuit.amine => 'plantCircuitAmine',
  };

  /// Couleur des lignes du schéma (même code que le PFD de l'usine).
  Color get color => switch (this) {
    PlantCircuit.condensate => const Color(0xFF9C5B2E),
    PlantCircuit.water => const Color(0xFF1E88E5),
    PlantCircuit.gas => const Color(0xFFE8A400),
    PlantCircuit.amine => const Color(0xFF2E9E5B),
  };

  IconData get icon => switch (this) {
    PlantCircuit.condensate => Icons.opacity,
    PlantCircuit.water => Icons.water_drop_outlined,
    PlantCircuit.gas => Icons.local_fire_department_outlined,
    PlantCircuit.amine => Icons.science_outlined,
  };

  static PlantCircuit fromKey(String key) =>
      PlantCircuit.values.firstWhere((c) => c.name == key, orElse: () => PlantCircuit.condensate);
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

  const PlantParam(
    this.key,
    this.labelKey,
    this.unit, {
    this.kind = ParamKind.number,
    this.choices = const [],
    this.okChoices = const [],
    this.storedUnit,
    this.fixedUnit = false,
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

/// Profil d'un point = liste de ses paramètres (colonne `profile` en base).
const plantProfiles = <String, List<PlantParam>>{
  'condensate': _condensateParams,
  'water': _waterParams,
  'gas': _gasParams,
  'gas_export': _exportGasParams,
  'amine': _amineParams,
};

List<PlantParam> paramsForProfile(String profile) => plantProfiles[profile] ?? const [];

/// Profils proposés à la création d'un point (libellé = clé de traduction).
const plantProfileLabelKeys = {
  'condensate': 'plantProfileCondensate',
  'water': 'plantProfileWater',
  'gas': 'plantProfileGas',
  'gas_export': 'plantProfileGasExport',
  'amine': 'plantProfileAmine',
};

/// Profil proposé par défaut pour un circuit.
String defaultProfileFor(PlantCircuit circuit) => switch (circuit) {
  PlantCircuit.condensate => 'condensate',
  PlantCircuit.water => 'water',
  PlantCircuit.gas => 'gas',
  PlantCircuit.amine => 'amine',
};

/// Tous les paramètres connus (un par clé), pour choisir librement ceux
/// analysés sur un point.
final List<PlantParam> plantParamCatalog = () {
  final seen = <String>{};
  return [
    for (final list in plantProfiles.values)
      for (final p in list)
        if (seen.add(p.key)) p,
  ];
}();

/// Définition d'un paramètre : celle du profil du point en priorité (unités
/// propres au circuit), sinon celle du catalogue.
PlantParam? plantParamByKey(String key, {String? profile}) {
  for (final p in paramsForProfile(profile ?? '')) {
    if (p.key == key) return p;
  }
  for (final p in plantParamCatalog) {
    if (p.key == key) return p;
  }
  return null;
}

/// Paramètres "composition" du gaz, regroupés à l'écran.
const gasCompositionKeys = {'ch4', 'c2h6', 'c3h8', 'c4plus', 'co2', 'n2'};

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
];

/// Origine d'une analyse.
const plantSources = ['plantSourceLab', 'plantSourceField', 'plantSourceImport'];
