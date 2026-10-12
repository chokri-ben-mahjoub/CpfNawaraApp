import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_strings.dart';
import '../models/user_role.dart';
import '../settings/app_settings.dart';
import '../sync/firebase_config_provider.dart';
import '../sync/sync_service.dart';

const _onboardingDoneKey = 'onboarding_done';
const _profileIdKey = 'profile_id';
const _profileNameKey = 'profile_name';
const _profilePhoneKey = 'profile_phone';
const _profileServiceKey = 'profile_service';
const _profilePhotoKey = 'profile_photo';
const _profilePhotoAtKey = 'profile_photo_at';

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

final onboardingDoneProvider = StateNotifierProvider<OnboardingController, bool>((ref) => OnboardingController());

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

  /// Photo de profil (JPEG carré, voir `profile_photo.dart`), propre à cet
  /// appareil.
  final Uint8List? photo;

  /// Date (ms) du dernier changement de photo, retrait compris : sert à
  /// garder la plus récente entre les appareils du compte.
  final int photoAt;

  const AppProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.serviceKey,
    required this.role,
    this.photo,
    this.photoAt = 0,
  });

  AppProfile copyWith({
    String? fullName,
    String? phone,
    String? serviceKey,
    Uint8List? photo,
    bool clearPhoto = false,
    int? photoAt,
  }) => AppProfile(
    id: id,
    fullName: fullName ?? this.fullName,
    phone: phone ?? this.phone,
    serviceKey: serviceKey ?? this.serviceKey,
    role: role,
    photo: clearPhoto ? null : (photo ?? this.photo),
    photoAt: photoAt ?? this.photoAt,
  );
}

Uint8List? _decodePhoto(String? data) {
  if (data == null || data.isEmpty) return null;
  try {
    return base64Decode(data);
  } catch (_) {
    return null;
  }
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
      // Rôle du profil local (mode personnel) ; avec un compte d'équipe,
      // c'est celui de la fiche d'équipe qui compte (currentRoleProvider).
      role: UserRole.admin,
      photo: _decodePhoto(prefs.getString(_profilePhotoKey)),
      photoAt: prefs.getInt(_profilePhotoAtKey) ?? 0,
    );
  }

  /// Enregistre (ou retire, si [photo] est nul) la photo de profil, datée
  /// [at] (maintenant par défaut ; date du serveur quand elle vient d'un
  /// autre appareil du compte).
  Future<void> setPhoto(Uint8List? photo, {int? at}) async {
    final current = state;
    if (current == null) return;
    final when = at ?? DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    if (photo == null) {
      await prefs.remove(_profilePhotoKey);
    } else {
      await prefs.setString(_profilePhotoKey, base64Encode(photo));
    }
    await prefs.setInt(_profilePhotoAtKey, when);
    state = current.copyWith(photo: photo, clearPhoto: photo == null, photoAt: when);
  }

  /// Crée le profil local (nom, service, téléphone) — une seule fois par
  /// appareil, juste après l'onboarding.
  Future<void> createProfile({required String fullName, required String phone, required String serviceKey}) async {
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
  Future<void> updateProfile({required String fullName, required String phone, required String serviceKey}) async {
    final current = state;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileNameKey, fullName);
    await prefs.setString(_profilePhoneKey, phone);
    await prefs.setString(_profileServiceKey, serviceKey);
    state = current.copyWith(fullName: fullName, phone: phone, serviceKey: serviceKey);
  }

  /// Efface le profil local (ne touche pas aux données des puits) : utile
  /// pour reconfigurer l'appareil pour un autre opérateur.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileIdKey);
    await prefs.remove(_profileNameKey);
    await prefs.remove(_profilePhoneKey);
    await prefs.remove(_profileServiceKey);
    await prefs.remove(_profilePhotoKey);
    await prefs.remove(_profilePhotoAtKey);
    state = null;
  }
}

final profileProvider = StateNotifierProvider<ProfileController, AppProfile?>((ref) => ProfileController());

/// True dès qu'un profil local a été configuré sur cet appareil.
final sessionAuthenticatedProvider = Provider<bool>((ref) => ref.watch(profileProvider) != null);

/// Rôle de l'utilisateur de l'appareil : celui de sa fiche d'équipe quand un
/// compte est connecté (lecteur si le compte est inactif ou en attente) ;
/// administrateur en mode personnel. Tant que la fiche n'a jamais pu être
/// lue, l'appareil garde l'accès complet à ses données locales — rien n'est
/// envoyé à l'équipe sans rôle connu, et les règles Firestore protègent le
/// serveur.
final currentRoleProvider = Provider<UserRole>((ref) {
  final sync = ref.watch(syncControllerProvider);
  if (!sync.isSignedIn) return UserRole.admin;
  // Pas encore d'entreprise (ou adhésion jamais lue) : données de
  // l'appareil seulement, rien n'est envoyé — accès complet en local.
  if (sync.memberStatus == MemberStatus.unknown || sync.memberStatus == MemberStatus.noCompany) return UserRole.admin;
  final member = sync.member;
  if (member == null) return UserRole.reader;
  return member.active ? member.role : UserRole.reader;
});

/// Point d'entrée unique pour créer/effacer le profil local de cet appareil.
class AuthService {
  AuthService(this._ref);
  final Ref _ref;

  Future<void> createProfile({required String fullName, required String phone, required String serviceKey}) {
    return _ref.read(profileProvider.notifier).createProfile(fullName: fullName, phone: phone, serviceKey: serviceKey);
  }

  /// Efface le profil local et déconnecte le compte d'équipe de cet
  /// appareil (les données locales restent).
  Future<void> signOut() async {
    await _ref.read(syncControllerProvider.notifier).signOut();
    await _ref.read(profileProvider.notifier).reset();
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref));

/// Garantit que l'état local (onboarding, langue) est chargé avant de router.
final authReadyProvider = FutureProvider<void>((ref) async {
  await ref.read(onboardingDoneProvider.notifier).load();
  await ref.read(localeProvider.notifier).load();
  // Projet Firebase configuré, et système d'unités (lu par les contrôleurs
  // de données dès leur premier chargement).
  await ref.read(firebaseConfigProvider.notifier).ready;
  await ref.read(appSettingsProvider.notifier).ready;
});
