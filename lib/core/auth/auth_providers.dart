import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../models/user_role.dart';

const _onboardingDoneKey = 'onboarding_done';
const _profileIdKey = 'profile_id';
const _profileNameKey = 'profile_name';
const _profilePhoneKey = 'profile_phone';
const _profileServiceKey = 'profile_service';
const _profileRoleKey = 'profile_role';

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

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

/// Flux des changements d'état d'authentification Firebase (connexion,
/// déconnexion, session restaurée au démarrage).
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// True dès qu'une session Firebase est active.
final sessionAuthenticatedProvider = Provider<bool>((ref) {
  final auth = ref.watch(authStateChangesProvider);
  return auth.maybeWhen(
    data: (user) => user != null,
    orElse: () => ref.read(firebaseAuthProvider).currentUser != null,
  );
});

/// Profil applicatif de l'utilisateur connecté (collection `profiles`), lu en
/// direct depuis Firestore — dont le cache hors-ligne intégré le garde
/// disponible sans réseau après la 1ère connexion. Une copie est aussi tenue
/// dans les préférences locales pour un affichage instantané au démarrage.
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
  ProfileController(this._ref) : super(null) {
    _authSub = _ref.listen<AsyncValue<User?>>(authStateChangesProvider, (previous, next) {
      next.whenData(_onAuthEvent);
    });
    unawaited(_loadCached());
    final current = _ref.read(firebaseAuthProvider).currentUser;
    if (current != null) _listenProfile(current.uid);
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<User?>> _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  Future<void> _loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_profileIdKey);
    if (id == null) return;
    state = AppProfile(
      id: id,
      fullName: prefs.getString(_profileNameKey) ?? '',
      phone: prefs.getString(_profilePhoneKey) ?? '',
      serviceKey: prefs.getString(_profileServiceKey) ?? '',
      role: UserRoleX.fromStorageKey(prefs.getString(_profileRoleKey) ?? 'user'),
    );
  }

  Future<void> _onAuthEvent(User? user) async {
    if (user == null) {
      await _profileSub?.cancel();
      _profileSub = null;
      state = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileIdKey);
      await prefs.remove(_profileNameKey);
      await prefs.remove(_profilePhoneKey);
      await prefs.remove(_profileServiceKey);
      await prefs.remove(_profileRoleKey);
      return;
    }
    _listenProfile(user.uid);
  }

  void _listenProfile(String uid) {
    _profileSub?.cancel();
    _profileSub = _ref
        .read(firestoreProvider)
        .collection('profiles')
        .doc(uid)
        .snapshots()
        .listen(_onProfileSnapshot, onError: (_) {});
  }

  Future<void> _onProfileSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    if (data == null) return;
    final profile = AppProfile(
      id: doc.id,
      fullName: data['fullName'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      serviceKey: data['serviceKey'] as String? ?? '',
      role: UserRoleX.fromStorageKey(data['role'] as String? ?? 'user'),
    );
    state = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileIdKey, profile.id);
    await prefs.setString(_profileNameKey, profile.fullName);
    await prefs.setString(_profilePhoneKey, profile.phone);
    await prefs.setString(_profileServiceKey, profile.serviceKey);
    await prefs.setString(_profileRoleKey, profile.role.storageKey);
  }

  @override
  void dispose() {
    _authSub.close();
    _profileSub?.cancel();
    super.dispose();
  }
}

final profileProvider =
    StateNotifierProvider<ProfileController, AppProfile?>((ref) => ProfileController(ref));

/// Rôle de l'utilisateur courant. En l'absence de profil chargé (ex: tout
/// premier instant après une connexion), on retombe sur le rôle le plus
/// restrictif plutôt que d'accorder des droits par erreur.
final currentRoleProvider = Provider<UserRole>((ref) {
  return ref.watch(profileProvider)?.role ?? UserRole.reader;
});

/// Opérations d'authentification Firebase (email + mot de passe).
class AuthService {
  AuthService(this._auth, this._firestore);
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<void> signIn({required String email, required String password}) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String serviceKey,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final uid = credential.user!.uid;
    await _firestore.collection('profiles').doc(uid).set({
      'fullName': fullName,
      'phone': phone,
      'serviceKey': serviceKey,
      'role': 'user',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Envoie un email avec un lien de réinitialisation géré par la page
  /// hébergée par Firebase (pas de retour dans l'app à gérer nous-mêmes).
  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() => _auth.signOut();
}

final authServiceProvider =
    Provider<AuthService>((ref) => AuthService(ref.watch(firebaseAuthProvider), ref.watch(firestoreProvider)));

/// Garantit que l'état local (onboarding, langue) est chargé avant de router.
final authReadyProvider = FutureProvider<void>((ref) async {
  await ref.read(onboardingDoneProvider.notifier).load();
  await ref.read(localeProvider.notifier).load();
});
