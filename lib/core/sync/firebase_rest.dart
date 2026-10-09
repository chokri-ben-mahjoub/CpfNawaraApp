import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'firebase_config.dart';

/// Session d'un compte connecté (Firebase Authentication).
class AuthSession {
  final String uid;
  final String email;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  const AuthSession({
    required this.uid,
    required this.email,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// À renouveler 5 minutes avant expiration (jeton valable 1 h).
  bool get needsRefresh => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  Map<String, Object?> toJson() => {
    'uid': uid,
    'email': email,
    'idToken': idToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
  };

  static AuthSession? fromJson(Map<String, Object?> json) {
    try {
      return AuthSession(
        uid: json['uid'] as String,
        email: json['email'] as String,
        idToken: json['idToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Erreur de compte (identifiants, mot de passe trop faible...). [code] est
/// le code Firebase (ex: `EMAIL_EXISTS`, `INVALID_LOGIN_CREDENTIALS`).
class SyncAuthException implements Exception {
  final String code;
  const SyncAuthException(this.code);

  @override
  String toString() => 'SyncAuthException($code)';
}

/// Pas de réseau, serveur injoignable ou délai dépassé.
class SyncNetworkException implements Exception {
  final Object? cause;
  const SyncNetworkException([this.cause]);

  @override
  String toString() => 'SyncNetworkException($cause)';
}

/// Refus de Firestore (règles de sécurité pas encore publiées, jeton
/// invalide...).
class SyncServerException implements Exception {
  final int statusCode;
  final String status;
  final String message;
  const SyncServerException(this.statusCode, this.status, [this.message = '']);

  /// Règles de sécurité qui refusent l'accès (pas encore publiées, rôle
  /// insuffisant, compte désactivé...).
  bool get isPermissionDenied => statusCode == 403;

  /// Base Firestore pas encore créée dans la console.
  bool get isDatabaseMissing => statusCode == 404 && message.contains('does not exist for project');

  @override
  String toString() => 'SyncServerException($statusCode $status $message)';
}

const _timeout = Duration(seconds: 25);

Future<http.Response> _send(Future<http.Response> request) async {
  try {
    return await request.timeout(_timeout);
  } on TimeoutException catch (e) {
    throw SyncNetworkException(e);
  } on http.ClientException catch (e) {
    throw SyncNetworkException(e);
  } catch (e) {
    // SocketException (mobile/PC) ou erreur réseau du navigateur.
    if (e is SyncAuthException || e is SyncServerException) rethrow;
    throw SyncNetworkException(e);
  }
}

/// Comptes e-mail + mot de passe (API REST Identity Toolkit).
class FirebaseAuthRest {
  final FirebaseRestConfig config;
  final http.Client client;

  FirebaseAuthRest(this.config, {http.Client? client}) : client = client ?? http.Client();

  Future<AuthSession> signUp(String email, String password) => _passwordCall('accounts:signUp', email, password);

  Future<AuthSession> signIn(String email, String password) =>
      _passwordCall('accounts:signInWithPassword', email, password);

  Future<AuthSession> _passwordCall(String method, String email, String password) async {
    final body = await _post('${config.authBaseUrl}/$method?key=${config.apiKey}', {
      'email': email,
      'password': password,
      'returnSecureToken': true,
    });
    return AuthSession(
      uid: body['localId'] as String,
      email: body['email'] as String? ?? email,
      idToken: body['idToken'] as String,
      refreshToken: body['refreshToken'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: int.parse('${body['expiresIn'] ?? 3600}'))),
    );
  }

  /// Nouveau jeton d'accès à partir du jeton de rafraîchissement.
  Future<AuthSession> refresh(AuthSession session) async {
    final response = await _send(
      client.post(
        Uri.parse('${config.tokenBaseUrl}/token?key=${config.apiKey}'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'grant_type': 'refresh_token', 'refresh_token': session.refreshToken},
      ),
    );
    final body = _decode(response);
    return AuthSession(
      uid: body['user_id'] as String? ?? session.uid,
      email: session.email,
      idToken: body['id_token'] as String,
      refreshToken: body['refresh_token'] as String? ?? session.refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: int.parse('${body['expires_in'] ?? 3600}'))),
    );
  }

  /// E-mail de réinitialisation du mot de passe.
  Future<void> sendPasswordReset(String email) async {
    await _post('${config.authBaseUrl}/accounts:sendOobCode?key=${config.apiKey}', {
      'requestType': 'PASSWORD_RESET',
      'email': email,
    });
  }

  Future<Map<String, Object?>> _post(String url, Map<String, Object?> payload) async {
    final response = await _send(
      client.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload)),
    );
    return _decode(response);
  }

  Map<String, Object?> _decode(http.Response response) {
    final body = response.body.isEmpty ? <String, Object?>{} : jsonDecode(response.body) as Map<String, Object?>;
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    final error = body['error'];
    final message = error is Map ? '${error['message'] ?? ''}' : '$error';
    // Ex: "WEAK_PASSWORD : Password should be at least 6 characters".
    throw SyncAuthException(
      message.split(RegExp(r'[ :]')).first.trim().isEmpty ? 'UNKNOWN' : message.split(RegExp(r'[ :]')).first.trim(),
    );
  }
}

/// Firestore (API REST v1) : écritures groupées et requêtes.
class FirestoreRest {
  final FirebaseRestConfig config;
  final http.Client client;

  FirestoreRest(this.config, {http.Client? client}) : client = client ?? http.Client();

  /// Applique [writes] (format REST `Write`) de façon atomique.
  Future<void> commit(String idToken, List<Map<String, Object?>> writes) async {
    if (writes.isEmpty) return;
    await _post(idToken, '${config.documentsUrl('')}:commit', {'writes': writes});
  }

  /// Lit un document (ex: `users/<uid>`) ; `null` s'il n'existe pas.
  Future<Map<String, Object?>?> getDocument(String idToken, String path) async {
    final response = await _send(
      client.get(Uri.parse(config.documentsUrl(path)), headers: {'Authorization': 'Bearer $idToken'}),
    );
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return Map<String, Object?>.from(body as Map);
    final error = body is Map ? body['error'] : null;
    final message = error is Map ? '${error['message'] ?? ''}' : '';
    if (response.statusCode == 404 && !message.contains('does not exist for project')) return null;
    throw SyncServerException(response.statusCode, error is Map ? '${error['status'] ?? ''}' : '', message);
  }

  /// Exécute [structuredQuery] sous le document parent [parentPath]
  /// (vide = racine de la base) et renvoie les documents trouvés.
  Future<List<Map<String, Object?>>> runQuery(
    String idToken,
    String parentPath,
    Map<String, Object?> structuredQuery,
  ) async {
    final result = await _post(idToken, '${config.documentsUrl(parentPath)}:runQuery', {
      'structuredQuery': structuredQuery,
    });
    return [
      for (final item in result as List)
        if ((item as Map)['document'] != null) Map<String, Object?>.from(item['document'] as Map),
    ];
  }

  Future<Object?> _post(String idToken, String url, Map<String, Object?> payload) async {
    final response = await _send(
      client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
        body: jsonEncode(payload),
      ),
    );
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    final error = body is Map
        ? body['error']
        : body is List && body.isNotEmpty
        ? (body.first as Map)['error']
        : null;
    throw SyncServerException(
      response.statusCode,
      error is Map ? '${error['status'] ?? ''}' : '',
      error is Map ? '${error['message'] ?? ''}' : '',
    );
  }
}
