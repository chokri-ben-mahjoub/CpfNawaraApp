import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../models/user_role.dart';

const _onboardingDoneKey = 'onboarding_done';
const _demoCode = '1234';

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

/// Numéro de téléphone saisi lors de l'étape de connexion ou d'inscription,
/// en attente de vérification par code. `null` tant que rien n'a été soumis.
final pendingPhoneProvider = StateProvider<String?>((ref) => null);

/// Nom complet saisi lors de l'inscription, affiché après connexion.
final pendingNameProvider = StateProvider<String?>((ref) => null);

/// Service (Laboratoire, Production, Exploitation, Réservoir, HSE...)
/// sélectionné lors de l'inscription.
final pendingServiceProvider = StateProvider<String?>((ref) => null);

/// Session ouverte après vérification du code. Repasse à false à chaque
/// redémarrage de l'app ou déconnexion manuelle.
final sessionAuthenticatedProvider = StateProvider<bool>((ref) => false);

/// Rôle de l'utilisateur courant. Pas encore relié à un vrai backend : un
/// sélecteur de démonstration permet de le changer depuis l'écran Compte
/// pour visualiser les trois niveaux d'accès prévus au cahier des charges.
final currentRoleProvider = StateProvider<UserRole>((ref) => UserRole.user);

/// Vérifie le code de connexion saisi (démo locale : "1234").
/// À remplacer par l'appel API d'envoi/validation d'OTP SMS.
bool verifyLoginCode(String code) => code == _demoCode;

/// Garantit que l'état local (onboarding) est chargé avant de router.
final authReadyProvider = FutureProvider<void>((ref) async {
  await ref.read(onboardingDoneProvider.notifier).load();
  await ref.read(localeProvider.notifier).load();
});
