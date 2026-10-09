import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';

const _configKey = 'firebase_config';

/// Ancienne session de synchronisation (avant la configuration depuis
/// l'app) : ces installations utilisaient le projet intégré.
const _legacySessionKey = 'sync_session';

/// Projet Firebase utilisé par cet appareil, configuré depuis l'app (écran
/// d'installation ou Administration › Projet Firebase) et enregistré
/// localement. `null` : pas encore configuré (mode personnel, local).
class FirebaseConfigController extends StateNotifier<FirebaseRestConfig?> {
  FirebaseConfigController() : super(null) {
    _ready = _load();
  }

  late final Future<void> _ready;

  /// Terminé une fois la configuration relue.
  Future<void> get ready => _ready;

  Future<void> _load() async {
    if (FirebaseRestConfig.useEmulator) {
      state = FirebaseRestConfig.emulator();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw != null) {
      try {
        state = FirebaseRestConfig.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
        return;
      } catch (_) {
        // Configuration illisible : traitée comme absente.
      }
    }
    if (prefs.getString(_legacySessionKey) != null) state = FirebaseRestConfig.builtIn;
  }

  /// Enregistre le projet à utiliser. Changer de projet déconnecte le compte
  /// d'équipe de cet appareil (les données locales sont conservées).
  Future<void> set(FirebaseRestConfig config) async {
    await _ready;
    final prefs = await SharedPreferences.getInstance();
    if (state != null && state != config) await _clearSession(prefs);
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
    state = config;
  }

  /// Oublie le projet (retour au mode personnel).
  Future<void> clear() async {
    await _ready;
    final prefs = await SharedPreferences.getInstance();
    await _clearSession(prefs);
    await prefs.remove(_configKey);
    state = null;
  }

  static Future<void> _clearSession(SharedPreferences prefs) async {
    await prefs.remove(_legacySessionKey);
    await prefs.remove('sync_member');
    await prefs.remove('sync_last_success');
  }
}

final firebaseConfigProvider = StateNotifierProvider<FirebaseConfigController, FirebaseRestConfig?>(
  (ref) => FirebaseConfigController(),
);
