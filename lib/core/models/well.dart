class Well {
  final String id;
  final String code;
  final String name;
  final bool active;

  /// Groupe / zone d'appartenance (ex: "Zone Nord"), libre et configurable.
  /// Vide = puits non classé (affiché dans un groupe "Sans groupe").
  final String group;

  /// Pression de gisement (Pr, en bar), issue du dernier test de remontée de
  /// pression — sert au calcul de l'indice de productivité (PI). `null` tant
  /// qu'elle n'a pas été renseignée.
  final double? reservoirPressure;

  const Well({
    required this.id,
    required this.code,
    required this.name,
    required this.active,
    this.group = '',
    this.reservoirPressure,
  });
}
