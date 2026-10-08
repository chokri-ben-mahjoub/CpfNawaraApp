/// Configuration Firebase passée au build via `--dart-define`, jamais
/// commitée en clair.
///
/// Lancement :
/// ```
/// flutter run \
///   --dart-define=FIREBASE_API_KEY=... \
///   --dart-define=FIREBASE_APP_ID=... \
///   --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
///   --dart-define=FIREBASE_PROJECT_ID=... \
///   --dart-define=FIREBASE_STORAGE_BUCKET=...
/// ```
///
/// Voir le README pour la procédure complète de création du projet Firebase
/// et l'endroit où trouver ces valeurs (Paramètres du projet → Général →
/// "Vos applications" → config SDK).
class Env {
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseMessagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseStorageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static bool get isConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  static const missingConfigMessage =
      'Configuration Firebase manquante. Lancez l\'app avec '
      '--dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... '
      '--dart-define=FIREBASE_MESSAGING_SENDER_ID=... '
      '--dart-define=FIREBASE_PROJECT_ID=... '
      '--dart-define=FIREBASE_STORAGE_BUCKET=... '
      '(voir le README, section "Configurer Firebase").';
}
