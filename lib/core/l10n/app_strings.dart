import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localeKey = 'app_locale';

/// Langues gérées par l'app. Ajouter une entrée ici + dans [_strings] suffit
/// pour supporter une langue supplémentaire.
const supportedLocales = [Locale('fr'), Locale('en')];

final _strings = <String, Map<String, String>>{
  'appName': {'fr': 'Suivi Puits', 'en': 'Well Tracker'},
  'appTagline': {
    'fr': 'CPF Nawara — suivi quotidien des analyses',
    'en': 'CPF Nawara — daily analysis tracking',
  },
  'onboardingTitle': {
    'fr': 'Bienvenue sur Suivi Puits',
    'en': 'Welcome to Well Tracker',
  },
  'onboardingBody': {
    'fr': 'Suivez les analyses quotidiennes de chaque puits (BSW, salinité, '
        'H2S, pression...), par service, avec alertes de seuil et rappels '
        'automatiques en cas de retard.',
    'en': 'Track daily analyses for every well (BSW, salinity, H2S, '
        'pressure...), by service, with threshold alerts and automatic '
        'reminders when something is overdue.',
  },
  'onboardingCta': {'fr': 'Commencer', 'en': 'Get started'},
  'slide1Title': {'fr': 'Tous vos puits au même endroit', 'en': 'All your wells in one place'},
  'slide1Subtitle': {
    'fr': 'Statut, historique et dernières analyses de chaque puits en un coup d\'œil.',
    'en': 'Status, history and latest analyses for every well at a glance.',
  },
  'slide2Title': {'fr': 'Fait / à faire, par jour', 'en': 'Done / pending, every day'},
  'slide2Subtitle': {
    'fr': 'Tableau de bord quotidien par puits et par analyse, avec le nom de l\'opérateur.',
    'en': 'Daily dashboard per well and per analysis, with the operator\'s name.',
  },
  'slide3Title': {'fr': 'Alertes et tendances', 'en': 'Alerts and trends'},
  'slide3Subtitle': {
    'fr': 'Courbes d\'évolution et alerte visuelle dès qu\'une valeur sort du seuil.',
    'en': 'Trend charts and a visual alert as soon as a value goes out of range.',
  },
  'loginSubtitle': {
    'fr': 'Connexion sécurisée par email',
    'en': 'Secure sign-in with your email',
  },
  'loginEmailLabel': {'fr': 'Email', 'en': 'Email'},
  'loginEmailHint': {'fr': 'nom@entreprise.com', 'en': 'name@company.com'},
  'loginPasswordLabel': {'fr': 'Mot de passe', 'en': 'Password'},
  'loginContinue': {'fr': 'Se connecter', 'en': 'Sign in'},
  'loginInvalidEmail': {
    'fr': 'Veuillez saisir une adresse email valide.',
    'en': 'Please enter a valid email address.',
  },
  'loginInvalidPassword': {
    'fr': 'Veuillez saisir votre mot de passe.',
    'en': 'Please enter your password.',
  },
  'loginError': {
    'fr': 'Email ou mot de passe incorrect.',
    'en': 'Incorrect email or password.',
  },
  'languageLabel': {'fr': 'Langue', 'en': 'Language'},
  'loginNoAccount': {'fr': 'Pas encore de compte ?', 'en': "Don't have an account?"},
  'loginCreateAccount': {'fr': 'Créer un compte', 'en': 'Create account'},
  'signupTitle': {'fr': 'Créer un compte', 'en': 'Create your account'},
  'signupSubtitle': {
    'fr': 'Renseigné par votre administrateur avant validation.',
    'en': 'Reviewed by your administrator before activation.',
  },
  'signupNameLabel': {'fr': 'Nom et prénom', 'en': 'Full name'},
  'signupNameHint': {'fr': 'Ex: Ahmed Ben Salah', 'en': 'e.g. John Smith'},
  'signupInvalidName': {
    'fr': 'Veuillez saisir votre nom complet.',
    'en': 'Please enter your full name.',
  },
  'signupServiceLabel': {'fr': 'Service', 'en': 'Department'},
  'signupServiceHint': {'fr': 'Sélectionner un service', 'en': 'Select a department'},
  'signupInvalidService': {
    'fr': 'Veuillez sélectionner votre service.',
    'en': 'Please select your department.',
  },
  'serviceLaboratoire': {'fr': 'Laboratoire', 'en': 'Laboratory'},
  'serviceProduction': {'fr': 'Production', 'en': 'Production'},
  'serviceExploitation': {'fr': 'Exploitation', 'en': 'Operations'},
  'serviceReservoir': {'fr': 'Réservoir', 'en': 'Reservoir'},
  'serviceHse': {'fr': 'HSE', 'en': 'HSE'},
  'signupPhoneLabel': {'fr': 'Téléphone (optionnel)', 'en': 'Phone (optional)'},
  'signupPasswordLabel': {'fr': 'Mot de passe', 'en': 'Password'},
  'signupInvalidPassword': {
    'fr': '8 caractères minimum.',
    'en': 'At least 8 characters.',
  },
  'signupSubmit': {'fr': 'Créer mon compte', 'en': 'Create my account'},
  'signupError': {
    'fr': 'Impossible de créer le compte. Cet email est peut-être déjà utilisé.',
    'en': 'Could not create the account. This email may already be in use.',
  },
  'signupHaveAccount': {'fr': 'Vous avez déjà un compte ?', 'en': 'Already have an account?'},
  'signupLogin': {'fr': 'Se connecter', 'en': 'Sign in'},
  'forgotPasswordLink': {'fr': 'Mot de passe oublié ?', 'en': 'Forgot password?'},
  'forgotPasswordTitle': {'fr': 'Mot de passe oublié', 'en': 'Forgot password'},
  'forgotPasswordSubtitle': {
    'fr': 'Indiquez votre email, nous vous enverrons un lien pour créer un '
        'nouveau mot de passe.',
    'en': 'Enter your email, we\'ll send you a link to set a new password.',
  },
  'forgotPasswordSubmit': {'fr': 'Envoyer le lien', 'en': 'Send the link'},
  'forgotPasswordSentTitle': {'fr': 'Email envoyé', 'en': 'Email sent'},
  'forgotPasswordSentBody': {
    'fr': 'Si un compte existe avec cet email, un lien de réinitialisation '
        'vient d\'être envoyé.',
    'en': 'If an account exists for this email, a reset link was just sent.',
  },
  'backToLogin': {'fr': 'Retour à la connexion', 'en': 'Back to sign in'},
  'pinSetupTitle': {'fr': 'Créez votre code', 'en': 'Create your code'},
  'pinSetupSubtitle': {
    'fr': 'Ce code à 4 chiffres vous servira à déverrouiller l\'app rapidement, sans ressaisir votre mot de passe.',
    'en': 'This 4-digit code will let you quickly unlock the app without retyping your password.',
  },
  'pinSetupConfirmTitle': {'fr': 'Confirmez votre code', 'en': 'Confirm your code'},
  'pinSetupConfirmSubtitle': {
    'fr': 'Saisissez à nouveau le même code.',
    'en': 'Enter the same code again.',
  },
  'pinMismatch': {
    'fr': 'Les deux codes ne correspondent pas, réessayez.',
    'en': 'The two codes do not match, try again.',
  },
  'unlockTitle': {'fr': 'Bon retour', 'en': 'Welcome back'},
  'unlockSubtitle': {'fr': 'Entrez votre code pour continuer', 'en': 'Enter your code to continue'},
  'unlockBiometricReason': {
    'fr': 'Déverrouillez Suivi Puits',
    'en': 'Unlock Well Tracker',
  },
  'unlockWrongPin': {'fr': 'Code incorrect, réessayez.', 'en': 'Incorrect code, try again.'},
  'unlockForgotPin': {'fr': 'Code oublié ? Se reconnecter', 'en': 'Forgot your code? Sign in again'},
  'accountChangePin': {'fr': 'Modifier mon code', 'en': 'Change my code'},
  'homeWelcome': {'fr': 'Connecté avec succès', 'en': 'Signed in successfully'},
  'homeSubtitle': {
    'fr': 'La partie tableau de bord (puits, analyses, historique) arrive ensuite.',
    'en': 'The dashboard (wells, analyses, history) comes next.',
  },
  'logout': {'fr': 'Se déconnecter', 'en': 'Sign out'},

  // Navigation
  'navToday': {'fr': "Aujourd'hui", 'en': 'Today'},
  'navWells': {'fr': 'Puits', 'en': 'Wells'},

  // Types d'analyses
  'analysisBsw': {'fr': 'BSW', 'en': 'BSW'},
  'analysisSalinity': {'fr': 'Salinité', 'en': 'Salinity'},
  'analysisDensity': {'fr': 'Densité', 'en': 'Density'},
  'analysisH2s': {'fr': 'H2S', 'en': 'H2S'},
  'analysisCo2': {'fr': 'CO2', 'en': 'CO2'},
  'analysisPressure': {'fr': 'Pression', 'en': 'Pressure'},
  'analysisTemperature': {'fr': 'Température', 'en': 'Temperature'},
  'analysisGor': {'fr': 'GOR', 'en': 'GOR'},
  'analysisFlow': {'fr': 'Débit', 'en': 'Flow rate'},
  'frequencyDaily': {'fr': 'Quotidienne', 'en': 'Daily'},
  'frequencyWeekly': {'fr': 'Hebdomadaire', 'en': 'Weekly'},
  'frequencyMonthly': {'fr': 'Mensuelle', 'en': 'Monthly'},

  // Puits
  'wellsTitle': {'fr': 'Puits', 'en': 'Wells'},
  'wellsSearchHint': {'fr': 'Rechercher un puits...', 'en': 'Search a well...'},
  'wellsEmpty': {'fr': 'Aucun puits ne correspond.', 'en': 'No matching well.'},
  'wellStatusActive': {'fr': 'Actif', 'en': 'Active'},
  'wellStatusStopped': {'fr': 'Arrêté', 'en': 'Stopped'},
  'wellsTodaySuffix': {'fr': 'analyses aujourd\'hui', 'en': 'analyses today'},
  'wellDetailLastValues': {'fr': 'Dernières valeurs', 'en': 'Latest values'},
  'wellDetailHistory': {'fr': 'Historique récent', 'en': 'Recent history'},
  'wellDetailNoHistory': {
    'fr': 'Aucune analyse enregistrée pour ce puits.',
    'en': 'No analysis recorded yet for this well.',
  },
  'wellDetailAddAnalysis': {'fr': 'Nouvelle analyse', 'en': 'New analysis'},
  'wellDetailNoValue': {'fr': 'Aucune valeur', 'en': 'No value yet'},
  'outOfRangeBadge': {'fr': 'Hors seuil', 'en': 'Out of range'},

  // Tableau de bord du jour
  'dashboardTitle': {'fr': "Aujourd'hui", 'en': 'Today'},
  'dashboardGreeting': {'fr': 'Bonjour', 'en': 'Hello'},
  'dashboardSummary': {
    'fr': 'Suivi des analyses du jour, par puits.',
    'en': 'Today\'s analysis tracking, by well.',
  },
  'dashboardDone': {'fr': 'Fait', 'en': 'Done'},
  'dashboardPending': {'fr': 'À faire', 'en': 'Pending'},
  'dashboardOverdue': {'fr': 'En retard', 'en': 'Overdue'},
  'dashboardEmpty': {
    'fr': 'Aucune analyse prévue aujourd\'hui.',
    'en': 'No analysis scheduled today.',
  },
  'dashboardDoneBy': {'fr': 'par', 'en': 'by'},
  'dashboardAllDone': {
    'fr': 'Toutes les analyses du jour sont faites 🎉',
    'en': 'All of today\'s analyses are done 🎉',
  },
  'dashboardPeriodDay': {'fr': 'Jour', 'en': 'Day'},
  'dashboardPeriodWeek': {'fr': 'Semaine', 'en': 'Week'},
  'dashboardPeriodMonth': {'fr': 'Mois', 'en': 'Month'},
  'dashboardPeriodDone': {'fr': 'faites', 'en': 'done'},
  'dashboardPeriodAllDone': {
    'fr': 'Tout est à jour sur cette période 🎉',
    'en': 'Everything is up to date for this period 🎉',
  },
  'dashboardMissingTitle': {'fr': 'Analyses manquantes', 'en': 'Missing analyses'},
  'dashboardMissingEmpty': {
    'fr': 'Aucune analyse manquante sur cette période.',
    'en': 'No missing analysis for this period.',
  },
  'dashboardMissingExpectedOn': {'fr': 'attendue le', 'en': 'expected on'},
  'exportTooltip': {'fr': 'Exporter en Excel', 'en': 'Export to Excel'},
  'exportStarted': {'fr': 'Préparation du fichier Excel...', 'en': 'Preparing the Excel file...'},
  'exportEmpty': {
    'fr': 'Rien à exporter pour le moment.',
    'en': 'Nothing to export right now.',
  },
  'exportError': {
    'fr': 'L\'export a échoué. Réessayez.',
    'en': 'Export failed. Please try again.',
  },
  'colDate': {'fr': 'Date', 'en': 'Date'},
  'colWell': {'fr': 'Puits', 'en': 'Well'},
  'colType': {'fr': 'Type d\'analyse', 'en': 'Analysis type'},
  'colValue': {'fr': 'Valeur', 'en': 'Value'},
  'colUnit': {'fr': 'Unité', 'en': 'Unit'},
  'colService': {'fr': 'Service', 'en': 'Department'},
  'colOperator': {'fr': 'Opérateur', 'en': 'Operator'},
  'colComment': {'fr': 'Commentaire', 'en': 'Comment'},
  'colStatus': {'fr': 'Statut', 'en': 'Status'},
  'colExpectedSince': {'fr': 'En retard depuis', 'en': 'Overdue since'},
  'colOutOfRange': {'fr': 'Hors seuil', 'en': 'Out of range'},

  // Saisie rapide
  'entryTitle': {'fr': 'Nouvelle analyse', 'en': 'New analysis'},
  'entryWellLabel': {'fr': 'Puits', 'en': 'Well'},
  'entrySelectWell': {'fr': 'Sélectionner un puits', 'en': 'Select a well'},
  'entryInvalidWell': {'fr': 'Veuillez choisir un puits.', 'en': 'Please choose a well.'},
  'entryTypeLabel': {'fr': "Type d'analyse", 'en': 'Analysis type'},
  'entrySelectType': {'fr': 'Sélectionner un type', 'en': 'Select a type'},
  'entryInvalidType': {'fr': 'Veuillez choisir un type.', 'en': 'Please choose a type.'},
  'entryValueLabel': {'fr': 'Valeur', 'en': 'Value'},
  'entryValueHint': {'fr': 'Ex: 12.5', 'en': 'e.g. 12.5'},
  'entryInvalidValue': {
    'fr': 'Veuillez saisir une valeur numérique.',
    'en': 'Please enter a numeric value.',
  },
  'entryServiceLabel': {'fr': 'Service', 'en': 'Department'},
  'entryInvalidService': {
    'fr': 'Veuillez choisir un service.',
    'en': 'Please choose a department.',
  },
  'entryCommentLabel': {'fr': 'Commentaire (optionnel)', 'en': 'Comment (optional)'},
  'entrySave': {'fr': 'Enregistrer', 'en': 'Save'},
  'entryDuplicateTitle': {'fr': 'Déjà saisi aujourd\'hui', 'en': 'Already recorded today'},
  'entryDuplicateBody': {
    'fr': 'Une valeur a déjà été enregistrée aujourd\'hui pour ce puits et ce paramètre.',
    'en': 'A value has already been recorded today for this well and parameter.',
  },
  'entryDuplicateReplace': {'fr': 'Remplacer la valeur', 'en': 'Replace the value'},
  'entryOutOfRangeTitle': {'fr': 'Valeur hors seuil', 'en': 'Value out of range'},
  'entryOutOfRangeBody': {
    'fr': 'La valeur saisie sort des seuils attendus pour ce paramètre. Confirmez-vous ?',
    'en': 'The entered value is outside the expected range for this parameter. Confirm?',
  },
  'entrySuccessTitle': {'fr': 'Analyse enregistrée', 'en': 'Analysis saved'},
  'entrySuccessBody': {
    'fr': 'La valeur a bien été enregistrée.',
    'en': 'The value has been saved.',
  },
  'close': {'fr': 'Fermer', 'en': 'Close'},
  'cancel': {'fr': 'Annuler', 'en': 'Cancel'},
  'confirm': {'fr': 'Confirmer', 'en': 'Confirm'},

  // Tendances
  'trendTitle': {'fr': 'Tendance', 'en': 'Trend'},
  'trendThreshold': {'fr': 'Seuil attendu', 'en': 'Expected range'},
  'trendNoData': {
    'fr': 'Pas encore assez de valeurs pour une courbe.',
    'en': 'Not enough values yet for a chart.',
  },
  'trendLatest': {'fr': 'Dernière valeur', 'en': 'Latest value'},
  'trendVsPrevious': {'fr': 'vs précédente', 'en': 'vs previous'},
  'trendUp': {'fr': 'en hausse', 'en': 'rising'},
  'trendDown': {'fr': 'en baisse', 'en': 'falling'},
  'trendStable': {'fr': 'stable', 'en': 'stable'},
  'trendRecentValues': {'fr': 'Valeurs récentes', 'en': 'Recent values'},

  // Navigation (suite)
  'navAlerts': {'fr': 'Alertes', 'en': 'Alerts'},
  'navAccount': {'fr': 'Compte', 'en': 'Account'},

  // Rôles
  'roleAdmin': {'fr': 'Administrateur', 'en': 'Administrator'},
  'roleUser': {'fr': 'Utilisateur', 'en': 'User'},
  'roleReader': {'fr': 'Lecteur', 'en': 'Reader'},
  'roleReaderNotice': {
    'fr': 'Mode lecteur : consultation uniquement, saisie désactivée.',
    'en': 'Reader mode: read-only, data entry disabled.',
  },

  // Compte
  'accountTitle': {'fr': 'Compte', 'en': 'Account'},
  'accountRoleLabel': {'fr': 'Rôle', 'en': 'Role'},
  'accountRoleHint': {
    'fr': 'Géré par un administrateur depuis la base de données.',
    'en': 'Managed by an administrator from the database.',
  },
  'accountLanguageLabel': {'fr': 'Langue', 'en': 'Language'},
  'accountAdminSettings': {'fr': 'Paramètres (types & seuils)', 'en': 'Settings (types & thresholds)'},
  'accountNoName': {'fr': 'Utilisateur', 'en': 'User'},

  // Alertes
  'alertsTitle': {'fr': 'Alertes', 'en': 'Alerts'},
  'alertsOverdueSection': {'fr': 'Analyses en retard', 'en': 'Overdue analyses'},
  'alertsOutOfRangeSection': {'fr': 'Dernières valeurs hors seuil', 'en': 'Latest out-of-range values'},
  'alertsEmpty': {
    'fr': 'Aucune alerte pour le moment. Tout est à jour 🎉',
    'en': 'No alerts right now. Everything is up to date 🎉',
  },
  'alertsOverdueSince': {'fr': 'en retard', 'en': 'overdue'},

  // Paramétrage Admin
  'adminTypesTitle': {'fr': "Types d'analyses", 'en': 'Analysis types'},
  'adminAddType': {'fr': 'Ajouter un type', 'en': 'Add a type'},
  'adminEditType': {'fr': "Modifier le type d'analyse", 'en': 'Edit analysis type'},
  'adminNewType': {'fr': "Nouveau type d'analyse", 'en': 'New analysis type'},
  'adminNameLabel': {'fr': 'Nom (ex: Débit)', 'en': 'Name (e.g. Flow rate)'},
  'adminInvalidName': {'fr': 'Veuillez saisir un nom.', 'en': 'Please enter a name.'},
  'adminUnitLabel': {'fr': 'Unité (ex: %, bar, ppm)', 'en': 'Unit (e.g. %, bar, ppm)'},
  'adminInvalidUnit': {'fr': 'Veuillez saisir une unité.', 'en': 'Please enter a unit.'},
  'adminMinLabel': {'fr': 'Seuil minimum', 'en': 'Minimum threshold'},
  'adminMaxLabel': {'fr': 'Seuil maximum', 'en': 'Maximum threshold'},
  'adminInvalidThreshold': {'fr': 'Valeur numérique requise.', 'en': 'A numeric value is required.'},
  'adminMinMaxOrder': {
    'fr': 'Le minimum doit être inférieur au maximum.',
    'en': 'The minimum must be lower than the maximum.',
  },
  'adminFrequencyLabel': {'fr': 'Fréquence attendue', 'en': 'Expected frequency'},
  'adminSave': {'fr': 'Enregistrer', 'en': 'Save'},
  'adminTypeUpdated': {'fr': 'Type d\'analyse mis à jour.', 'en': 'Analysis type updated.'},
  'adminTypeAdded': {'fr': 'Type d\'analyse ajouté.', 'en': 'Analysis type added.'},
};

/// Traduit une clé pour une [Locale] donnée ; retombe sur le français.
String tr(Locale locale, String key) {
  final entry = _strings[key];
  if (entry == null) return key;
  return entry[locale.languageCode] ?? entry['fr'] ?? key;
}

extension TrX on BuildContext {
  String t(String key, WidgetRef ref) => tr(ref.watch(localeProvider), key);
}

class LocaleController extends StateNotifier<Locale> {
  LocaleController() : super(const Locale('fr'));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    if (code != null) {
      state = supportedLocales.firstWhere(
        (l) => l.languageCode == code,
        orElse: () => const Locale('fr'),
      );
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
  }
}

final localeProvider =
    StateNotifierProvider<LocaleController, Locale>((ref) => LocaleController());
