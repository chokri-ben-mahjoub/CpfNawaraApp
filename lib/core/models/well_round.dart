/// Tournée de l'opérateur de puits (« well operator audit ») : relevé de
/// chaque puits (têtes de puits, annulaires, choke, injection, N2, niveaux,
/// état ouvert/fermé) et des installations du site, comme sur la feuille
/// papier de la tournée — voir `RoundsController`.
enum RoundFieldKind { number, choice }

class RoundField {
  final String key;
  final RoundFieldKind kind;
  final String unit;

  /// Section d'affichage (clé de traduction `rs_<section>`).
  final String section;

  /// Valeurs possibles (clés de traduction) pour un champ à choix.
  final List<String> choices;

  const RoundField(this.key, this.section, {this.unit = '', this.kind = RoundFieldKind.number, this.choices = const []});

  /// Clé de traduction du libellé.
  String get labelKey => 'rf_$key';
  bool get isNumber => kind == RoundFieldKind.number;
}

const roundWellStatusChoices = ['roundOpen', 'roundClosed'];

/// Relevé de chaque puits.
const wellRoundFields = [
  RoundField('whp_gauge', 'wellhead', unit: 'bar'),
  RoundField('whp_transmitter', 'wellhead', unit: 'bar'),
  RoundField('csg_a', 'annulus', unit: 'bar'),
  RoundField('csg_b', 'annulus', unit: 'bar'),
  RoundField('csg_c', 'annulus', unit: 'bar'),
  RoundField('scssv', 'wellhead', unit: 'bar'),
  RoundField('flowline_pressure', 'flow', unit: 'bar'),
  RoundField('temp_us_choke', 'flow', unit: '°C'),
  RoundField('temp_ds_choke', 'flow', unit: '°C'),
  RoundField('choke_opening', 'flow', unit: '%'),
  RoundField('methanol_mov', 'chemical', unit: '%'),
  RoundField('whcp_n2_bottle', 'whcp', unit: 'bar'),
  RoundField('whcp_n2_pressure', 'whcp', unit: 'bar'),
  RoundField('sdv_n2_pressure', 'whcp', unit: 'bar'),
  RoundField('hydraulic_oil_level', 'levels', unit: '%'),
  RoundField('corrosion_inhibitor_level', 'chemical', unit: '%'),
  RoundField('dh_corrosion_inhibitor', 'chemical', unit: 'L/d'),
  RoundField('sand_filter_dp', 'levels', unit: 'bar'),
  RoundField('drain_pit_level', 'levels', unit: '%'),
  RoundField('well_status', 'status', kind: RoundFieldKind.choice, choices: roundWellStatusChoices),
];

/// Relevé des installations du site (une seule fiche par tournée).
const siteRoundFields = [
  RoundField('water_well_flow', 'site', unit: 'm³'),
  RoundField('lvs_trapsa_n2', 'site', unit: 'bar'),
  RoundField('nac_sewage_status', 'site', kind: RoundFieldKind.choice, choices: ['roundOk', 'roundNotOk']),
  RoundField('nac_edg_diesel', 'site', unit: '%'),
  RoundField('nac_fresh_water_tank', 'site', unit: 'm³'),
  RoundField('camp_ro_status', 'site', kind: RoundFieldKind.choice, choices: ['roundRunning', 'roundStopped']),
  RoundField('camp_sewage_status', 'site', kind: RoundFieldKind.choice, choices: ['roundOk', 'roundNotOk']),
];

/// Identifiant « puits » des relevés du site.
const siteRoundId = '';

class WellRound {
  final String id;

  /// Puits concerné, ou [siteRoundId] pour la fiche du site.
  final String wellId;

  /// Jour de la tournée (minuit, heure locale) et heure "HH:mm".
  final DateTime day;
  final String time;

  /// Valeurs relevées : nombre ou clé de choix.
  final Map<String, Object?> values;
  final String operatorName;
  final String? comment;
  final DateTime recordedAt;

  /// Photo jointe (JPEG en base64), facultative.
  final String? photo;

  const WellRound({
    required this.id,
    required this.wellId,
    required this.day,
    required this.time,
    required this.values,
    required this.operatorName,
    this.comment,
    required this.recordedAt,
    this.photo,
  });

  bool get isSite => wellId == siteRoundId;

  double? number(String key) => (values[key] as num?)?.toDouble();
  String? choice(String key) => values[key] is String ? values[key] as String : null;
}
