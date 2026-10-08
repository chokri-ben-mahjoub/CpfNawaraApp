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

  /// Valeur stockée dans `profiles.role` (Firestore) et en cache local.
  String get storageKey {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.user:
        return 'user';
      case UserRole.reader:
        return 'reader';
    }
  }

  static UserRole fromStorageKey(String key) {
    switch (key) {
      case 'admin':
        return UserRole.admin;
      case 'reader':
        return UserRole.reader;
      case 'user':
      default:
        return UserRole.user;
    }
  }
}
