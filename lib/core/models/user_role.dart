enum UserRole { admin, user, reader }

extension UserRoleX on UserRole {
  /// Clé de traduction associée (voir `app_strings.dart`).
  String get labelKey {
    switch (this) {
      case UserRole.admin:
        return 'roleAdmin';
      case UserRole.user:
        return 'roleUser';
      case UserRole.reader:
        return 'roleReader';
    }
  }

  /// Lecteur : consultation uniquement, pas de saisie ni de configuration.
  bool get canEnterData => this != UserRole.reader;

  /// Seul l'Admin configure les puits/types d'analyses/seuils.
  bool get canConfigure => this == UserRole.admin;
}
