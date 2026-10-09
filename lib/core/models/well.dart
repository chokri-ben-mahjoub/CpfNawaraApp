class Well {
  final String id;
  final String code;
  final String name;
  final bool active;

  /// Groupe / zone d'appartenance (ex: "Zone Nord"), libre et configurable.
  /// Vide = puits non classé (affiché dans un groupe "Sans groupe").
  final String group;

  const Well({
    required this.id,
    required this.code,
    required this.name,
    required this.active,
    this.group = '',
  });
}
