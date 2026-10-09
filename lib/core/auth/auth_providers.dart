import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_strings.dart';
import '../models/user_role.dart';

const _onboardingDoneKey = 'onboarding_done';
const _profileIdKey = 'profile_id';
const _profileNameKey = 'profile_name';
const _profilePhoneKey = 'profile_phone';
const _profileServiceKey = 'profile_service';

/// Écran d'accueil (carrousel de présentation) déjà vu par l'utilisateur.
class OnboardingController extends StateNotifier<bool> {
  OnboardingController() : super(false);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_onboardingDoneKey) ?? false;
  }

  Future<void> complete() async {
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingDoneKey, true);
  }
}

final onboardingDoneProvider =
    StateNotifierProvider<OnboardingController, bool>((ref) => OnboardingController());

/// Profil de l'utilisateur de cet appareil. Mode 100% local pour l'instant
/// (pas de backend configuré) : un seul profil par appareil, créé une fois
/// via l'écran de configuration, puis protégé par le code à 4 chiffres /
/// l'empreinte (voir `app_lock.dart`).
class AppProfile {
  final String id;
  final String fullName;
  final String phone;
  final String serviceKey;
  final UserRole role;

  const AppProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.serviceKey,
    required this.role,
  });
}

class ProfileController extends StateNotifier<AppProfile?> {
  ProfileController() : super(null) {
    _load();
  }

  static const _uuid = Uuid();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_profileIdKey);
    if (id == null) return;
    state = AppProfile(
      id: id,
      fullName: prefs.getString(_profileNameKey) ?? '',
      phone: prefs.getString(_profilePhoneKey) ?? '',
      serviceKey: prefs.getString(_profileServiceKey) ?? '',
      // Appareil local mono-utilisateur : accès complet (pas de notion de
      // rôle distribué tant qu'il n'y a pas de backend partagé).
      role: UserRole.admin,
    );
  }

  /// Crée le profil local (nom, service, téléphone) — une seule fois par
  /// appareil, juste après l'onboarding.
  Future<void> createProfile({
    required String fullName,
    required String phone,
    required String serviceKey,
  }) async {
    final id = _uuid.v4();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileIdKey, id);
    await prefs.setString(_profileNameKey, fullName);
    await prefs.setString(_profilePhoneKey, phone);
    await prefs.setString(_profileServiceKey, serviceKey);
    state = AppProfile(id: id, fullName: fullName, phone: phone, serviceKey: serviceKey, role: UserRole.admin);
  }

  /// Modifie le profil existant en gardant son identifiant (le code à 4
  /// chiffres, rattaché à cet identifiant, reste valable).
  Future<void> updateProfile({
    required String fullName,
    required String phone,
    required String serviceKey,
  }) async {
    final current = state;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileNameKey, fullName);
    await prefs.setString(_profilePhoneKey, phone);
    await prefs.setString(_profileServiceKey, serviceKey);
    state = AppProfile(id: current.id, fullName: fullName, phone: phone, serviceKey: serviceKey, role: current.role);
  }

  /// Efface le profil local (ne touche pas aux données des puits) : utile
  /// pour reconfigurer l'appareil pour un autre opérateur.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileIdKey);
    await prefs.remove(_profileNameKey);
    await prefs.remove(_profilePhoneKey);
    await prefs.remove(_profileServiceKey);
    state = null;
  }
}

final profileProvider = StateNotifierProvider<ProfileController, AppProfile?>((ref) => ProfileController());

/// True dès qu'un profil local a été configuré sur cet appareil.
final sessionAuthenticatedProvider = Provider<bool>((ref) => ref.watch(profileProvider) != null);

/// Rôle de l'utilisateur courant (toujours Admin tant que l'app fonctionne en
/// local mono-appareil ; redeviendra piloté par le backend si un back-end
/// partagé est rebranché un jour, voir README).
final currentRoleProvider = Provider<UserRole>((ref) => ref.watch(profileProvider)?.role ?? UserRole.reader);

/// Point d'entrée unique pour créer/effacer le profil local de cet appareil.
class AuthService {
  AuthService(this._ref);
  final Ref _ref;

  Future<void> createProfile({required String fullName, required String phone, required String serviceKey}) {
    return _ref.read(profileProvider.notifier).createProfile(fullName: fullName, phone: phone, serviceKey: serviceKey);
  }

  Future<void> signOut() => _ref.read(profileProvider.notifier).reset();
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref));

/// Garantit que l'état local (onboarding, langue) est chargé avant de router.
final authReadyProvider = FutureProvider<void>((ref) async {
  await ref.read(onboardingDoneProvider.notifier).load();
  await ref.read(localeProvider.notifier).load();
});
