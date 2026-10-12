import 'dart:convert';

/// Accès à un projet Firebase par ses API REST (comptes + Firestore) : le
/// même code Dart fonctionne sur Android, Windows et web, sans SDK natif.
///
/// La configuration se colle depuis l'app (JSON de la console Firebase,
/// `google-services.json` ou QR code d'un autre appareil) : voir
/// [FirebaseRestConfig.parse].
///
/// La clé d'API Firebase n'est pas un secret (elle est présente dans toute
/// app cliente) : l'accès aux données est protégé par les règles Firestore
/// (`firestore.rules`, basées sur le rôle de chaque compte).
class FirebaseRestConfig {
  final String apiKey;
  final String projectId;

  /// Informations facultatives (affichées, transmises par QR code).
  final String appId;
  final String authDomain;
  final String storageBucket;
  final String messagingSenderId;

  /// Ex: https://identitytoolkit.googleapis.com/v1
  final String authBaseUrl;

  /// Ex: https://securetoken.googleapis.com/v1
  final String tokenBaseUrl;

  /// Ex: https://firestore.googleapis.com/v1
  final String firestoreBaseUrl;

  /// Cloud Functions (opérations d'administration), ex:
  /// `https://europe-west1-PROJET.cloudfunctions.net` ; `null` : région
  /// [functionsRegion] du projet.
  final String? functionsBaseUrl;

  /// Région des Cloud Functions de PuitsTrack (voir functions/index.js).
  static const functionsRegion = 'europe-west1';

  const FirebaseRestConfig({
    required this.apiKey,
    required this.projectId,
    this.appId = '',
    this.authDomain = '',
    this.storageBucket = '',
    this.messagingSenderId = '',
    this.authBaseUrl = 'https://identitytoolkit.googleapis.com/v1',
    this.tokenBaseUrl = 'https://securetoken.googleapis.com/v1',
    this.firestoreBaseUrl = 'https://firestore.googleapis.com/v1',
    this.functionsBaseUrl,
  });

  /// Projet PuitsTrack intégré à l'app (proposé en un clic à l'installation).
  static const builtIn = FirebaseRestConfig(
    apiKey: 'AIzaSyDPZfqckq75ugdlyyMnuZhpI8SX5uM35GE',
    projectId: 'puitstrack',
    authDomain: 'puitstrack.firebaseapp.com',
    storageBucket: 'puitstrack.firebasestorage.app',
  );

  /// Ancien nom de [builtIn].
  static const production = builtIn;

  /// Vrai si l'app est compilée pour les émulateurs locaux
  /// (`--dart-define=SYNC_EMULATOR=true`, tests).
  static const useEmulator = bool.fromEnvironment('SYNC_EMULATOR');

  /// Émulateurs Firebase locaux (`firebase emulators:start`), pour les tests.
  factory FirebaseRestConfig.emulator({
    String host = '127.0.0.1',
    int authPort = 9099,
    int firestorePort = 8080,
    int functionsPort = 5001,
    String projectId = 'puitstrack',
  }) => FirebaseRestConfig(
    apiKey: 'emulator-key',
    projectId: projectId,
    authBaseUrl: 'http://$host:$authPort/identitytoolkit.googleapis.com/v1',
    tokenBaseUrl: 'http://$host:$authPort/securetoken.googleapis.com/v1',
    firestoreBaseUrl: 'http://$host:$firestorePort/v1',
    functionsBaseUrl: 'http://$host:$functionsPort/$projectId/$functionsRegion',
  );

  /// URL d'une Cloud Function « callable ».
  String functionUrl(String name) =>
      '${functionsBaseUrl ?? 'https://$functionsRegion-$projectId.cloudfunctions.net'}/$name';

  bool get isEmulator => apiKey == 'emulator-key';

  String get _databasePath => 'projects/$projectId/databases/(default)/documents';

  /// Nom complet d'un document (ex: pour `wells/w1`).
  String documentName(String path) => '$_databasePath/$path';

  /// URL REST d'un chemin de documents.
  String documentsUrl(String path) => '$firestoreBaseUrl/$_databasePath${path.isEmpty ? '' : '/$path'}';

  /// Page de la console Firebase du projet (ex: `authentication/providers`).
  String consoleUrl(String page) => 'https://console.firebase.google.com/project/$projectId/$page';

  /// Clé d'API masquée pour l'affichage (AIza…35GE).
  String get maskedApiKey =>
      apiKey.length <= 10 ? apiKey : '${apiKey.substring(0, 4)}…${apiKey.substring(apiKey.length - 4)}';

  Map<String, Object?> toJson() => {
    'apiKey': apiKey,
    'projectId': projectId,
    if (appId.isNotEmpty) 'appId': appId,
    if (authDomain.isNotEmpty) 'authDomain': authDomain,
    if (storageBucket.isNotEmpty) 'storageBucket': storageBucket,
    if (messagingSenderId.isNotEmpty) 'messagingSenderId': messagingSenderId,
  };

  /// Contenu du QR code affiché par l'administrateur : un autre appareil le
  /// scanne pour se connecter au même projet.
  String get qrPayload => jsonEncode({'app': 'puitstrack', ...toJson()});

  static FirebaseRestConfig? fromJson(Map<String, Object?> json) {
    final apiKey = json['apiKey'];
    final projectId = json['projectId'];
    if (apiKey is! String || projectId is! String || apiKey.isEmpty || projectId.isEmpty) return null;
    return FirebaseRestConfig(
      apiKey: apiKey,
      projectId: projectId,
      appId: '${json['appId'] ?? ''}',
      authDomain: '${json['authDomain'] ?? ''}',
      storageBucket: '${json['storageBucket'] ?? ''}',
      messagingSenderId: '${json['messagingSenderId'] ?? ''}',
    );
  }

  /// Lit une configuration collée telle quelle depuis la console Firebase :
  ///
  /// - objet `firebaseConfig` de l'app web (`const firebaseConfig = {
  ///   apiKey: "...", projectId: "..." }`, clés avec ou sans guillemets) ;
  /// - fichier `google-services.json` (Android) ;
  /// - QR code d'un autre appareil ([qrPayload]).
  ///
  /// Retourne `null` si la clé d'API ou l'identifiant du projet manquent.
  static FirebaseRestConfig? parse(String text) {
    String find(List<String> keys) {
      for (final key in keys) {
        final match = RegExp('["\']?$key["\']?\\s*[:=]\\s*["\']([^"\']+)["\']').firstMatch(text);
        if (match != null) return match.group(1)!.trim();
      }
      return '';
    }

    final apiKey = find(['apiKey', 'current_key']);
    final projectId = find(['projectId', 'project_id']);
    if (!isValidApiKey(apiKey) || !isValidProjectId(projectId)) return null;
    return FirebaseRestConfig(
      apiKey: apiKey,
      projectId: projectId,
      appId: find(['appId', 'mobilesdk_app_id']),
      authDomain: find(['authDomain']),
      storageBucket: find(['storageBucket', 'storage_bucket']),
      messagingSenderId: find(['messagingSenderId', 'project_number']),
    );
  }

  static bool isValidApiKey(String value) => RegExp(r'^[A-Za-z0-9_\-]{20,}$').hasMatch(value);

  static bool isValidProjectId(String value) => RegExp(r'^[a-z0-9][a-z0-9\-]{2,40}$').hasMatch(value);

  @override
  bool operator ==(Object other) =>
      other is FirebaseRestConfig &&
      other.apiKey == apiKey &&
      other.projectId == projectId &&
      other.firestoreBaseUrl == firestoreBaseUrl;

  @override
  int get hashCode => Object.hash(apiKey, projectId, firestoreBaseUrl);
}
