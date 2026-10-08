import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_providers.dart';

String _pinKey(String userId) => 'app_lock_pin_$userId';

String _hashPin(String userId, String pin) => sha256.convert(utf8.encode('$userId:$pin')).toString();

/// Identifiant du profil local courant (voir `auth_providers.dart`) : c'est
/// à cet identifiant qu'est rattaché le code à 4 chiffres.
final currentUserIdProvider = Provider<String?>((ref) => ref.watch(profileProvider)?.id);

class AppLockState {
  /// `null` tant qu'on n'a pas encore vérifié si un code existe pour cet
  /// utilisateur (lecture locale, quasi instantanée).
  final bool? hasPin;
  final bool unlocked;

  const AppLockState({required this.hasPin, required this.unlocked});

  AppLockState copyWith({bool? hasPin, bool? unlocked}) =>
      AppLockState(hasPin: hasPin ?? this.hasPin, unlocked: unlocked ?? this.unlocked);

  static const loading = AppLockState(hasPin: null, unlocked: false);
}

/// Déverrouillage rapide de l'app (code à 4 chiffres + empreinte) : une fois
/// le profil local configuré, l'app se reverrouille à chaque réouverture et
/// se déverrouille avec ce code (ou l'empreinte) plutôt qu'en redemandant la
/// configuration complète.
class AppLockController extends StateNotifier<AppLockState> {
  AppLockController(this._ref) : super(AppLockState.loading) {
    _sub = _ref.listen<String?>(currentUserIdProvider, (previous, next) {
      if (previous != next) unawaited(_reload(next));
    }, fireImmediately: true);
  }

  final Ref _ref;
  late final ProviderSubscription<String?> _sub;
  String? _userId;
  String? _storedHash;

  Future<void> _reload(String? userId) async {
    _userId = userId;
    if (userId == null) {
      _storedHash = null;
      state = AppLockState.loading;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _storedHash = prefs.getString(_pinKey(userId));
    state = AppLockState(hasPin: _storedHash != null, unlocked: false);
  }

  Future<void> setPin(String pin) async {
    final userId = _userId;
    if (userId == null) return;
    final hash = _hashPin(userId, pin);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey(userId), hash);
    _storedHash = hash;
    state = state.copyWith(hasPin: true, unlocked: true);
  }

  bool verifyPin(String pin) {
    final userId = _userId;
    if (userId == null || _storedHash == null) return false;
    return _hashPin(userId, pin) == _storedHash;
  }

  void unlock() => state = state.copyWith(unlocked: true);

  /// Reverrouille l'app (ex: au retour en premier plan) sans toucher au code
  /// enregistré.
  void lock() {
    if (state.hasPin == true) state = state.copyWith(unlocked: false);
  }

  /// Oublie le code enregistré (ex: "code oublié ?") : l'app redemande d'en
  /// créer un nouveau avant de continuer.
  Future<void> clearPin() async {
    final userId = _userId;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey(userId));
    _storedHash = null;
    state = state.copyWith(hasPin: false, unlocked: false);
  }

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final appLockProvider = StateNotifierProvider<AppLockController, AppLockState>((ref) => AppLockController(ref));

/// Authentification biométrique (empreinte / visage), best-effort : toute
/// erreur (capteur absent, non configuré, annulé...) est traitée comme un
/// simple échec, l'utilisateur retombe sur le code à 4 chiffres.
class BiometricAuth {
  static final _auth = LocalAuthentication();

  static Future<bool> get isAvailable async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
