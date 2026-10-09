/// Type de puits (colonne `wells.well_type`) ; vide = non précisé.
const wellTypeKeys = ['oil_producer', 'gas_producer', 'water_injector', 'gas_injector', 'observation'];

String wellTypeLabelKey(String key) => switch (key) {
  'oil_producer' => 'wellTypeOilProducer',
  'gas_producer' => 'wellTypeGasProducer',
  'water_injector' => 'wellTypeWaterInjector',
  'gas_injector' => 'wellTypeGasInjector',
  'observation' => 'wellTypeObservation',
  _ => 'wellTypeNone',
};

/// Statut d'exploitation d'un puits. Les puits en production, en test ou en
/// injection sont "actifs" (attendus dans le suivi quotidien).
enum WellStatus { producing, testing, injecting, shutIn, abandoned }

extension WellStatusX on WellStatus {
  String get storageKey => switch (this) {
    WellStatus.producing => 'producing',
    WellStatus.testing => 'testing',
    WellStatus.injecting => 'injecting',
    WellStatus.shutIn => 'shut_in',
    WellStatus.abandoned => 'abandoned',
  };

  String get labelKey => switch (this) {
    WellStatus.producing => 'wellStatusProducing',
    WellStatus.testing => 'wellStatusTesting',
    WellStatus.injecting => 'wellStatusInjecting',
    WellStatus.shutIn => 'wellStatusShutIn',
    WellStatus.abandoned => 'wellStatusAbandoned',
  };

  bool get isActive => this == WellStatus.producing || this == WellStatus.testing || this == WellStatus.injecting;

  /// Statut enregistré, ou à défaut déduit de l'ancien indicateur
  /// actif/arrêté (puits créés avant la v8).
  static WellStatus fromStorage(String? key, {required bool active}) {
    for (final s in WellStatus.values) {
      if (s.storageKey == key) return s;
    }
    return active ? WellStatus.producing : WellStatus.shutIn;
  }
}

class Well {
  final String id;
  final String code;
  final String name;
  final bool active;

  /// Groupe / champ d'appartenance (ex: "Zone Nord"), libre et configurable.
  /// Vide = puits non classé (affiché dans un groupe "Sans groupe").
  final String group;

  /// Pression de gisement (Pr, en bar), issue du dernier test de remontée de
  /// pression — sert au calcul de l'indice de productivité (PI). `null` tant
  /// qu'elle n'a pas été renseignée.
  final double? reservoirPressure;

  /// Type (voir [wellTypeKeys]), vide si non précisé.
  final String type;
  final WellStatus status;
  final double? latitude;
  final double? longitude;

  const Well({
    required this.id,
    required this.code,
    required this.name,
    required this.active,
    this.group = '',
    this.reservoirPressure,
    this.type = '',
    WellStatus? status,
    this.latitude,
    this.longitude,
  }) : status = status ?? (active ? WellStatus.producing : WellStatus.shutIn);

  bool get hasLocation => latitude != null && longitude != null;
}
