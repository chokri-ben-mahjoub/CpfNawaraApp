/// Rôles de l'équipe (champ `role` des documents `users/{uid}`) :
///
/// - **admin** : tout, y compris l'Administration (utilisateurs, puits,
///   points, seuils, import, projet Firebase, journal d'audit) ;
/// - **ingénieur** : saisie des analyses et des interventions ;
/// - **opérateur** : saisie des analyses ;
/// - **lecteur** : consultation uniquement.
///
/// Sans compte d'équipe (mode personnel, données locales), l'utilisateur
/// de l'appareil est administrateur.
enum UserRole { admin, engineer, operator, reader }

extension UserRoleX on UserRole {
  /// Clé de traduction associée (voir `app_strings.dart`).
  String get labelKey => switch (this) {
    UserRole.admin => 'roleAdmin',
    UserRole.engineer => 'roleEngineer',
    UserRole.operator => 'roleOperator',
    UserRole.reader => 'roleReader',
  };

  String get descriptionKey => switch (this) {
    UserRole.admin => 'roleAdminHint',
    UserRole.engineer => 'roleEngineerHint',
    UserRole.operator => 'roleOperatorHint',
    UserRole.reader => 'roleReaderHint',
  };

  /// Saisie et correction des analyses (puits et usine).
  bool get canEnterData => this != UserRole.reader;

  /// Journal des interventions (coûts, résultats).
  bool get canManageInterventions => this == UserRole.admin || this == UserRole.engineer;

  /// Administration : puits, points, types d'analyse, seuils, utilisateurs.
  bool get canConfigure => this == UserRole.admin;

  /// Tables que ce rôle peut modifier (voir `firestore.rules`).
  Set<String> get writableTables => switch (this) {
    UserRole.admin => const {
      'wells',
      'analysis_types',
      'analysis_records',
      'interventions',
      'sample_points',
      'plant_analyses',
      'plant_thresholds',
      'app_config',
      'plant_circuits',
      'plant_schemas',
      'plant_params',
      'plant_profiles',
    },
    UserRole.engineer => const {'analysis_records', 'interventions', 'plant_analyses'},
    UserRole.operator => const {'analysis_records', 'plant_analyses'},
    UserRole.reader => const <String>{},
  };

  /// Valeur stockée dans Firestore (`users/{uid}.role`).
  String get storageKey => switch (this) {
    UserRole.admin => 'admin',
    UserRole.engineer => 'ingenieur',
    UserRole.operator => 'operateur',
    UserRole.reader => 'lecteur',
  };

  static UserRole fromStorageKey(String? key) => switch (key) {
    'admin' => UserRole.admin,
    'ingenieur' || 'engineer' => UserRole.engineer,
    'operateur' || 'operator' || 'user' => UserRole.operator,
    _ => UserRole.reader,
  };
}
