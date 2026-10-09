import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localeKey = 'app_locale';

/// Langues gérées par l'app. Ajouter une entrée ici + dans [_strings] suffit
/// pour supporter une langue supplémentaire.
const supportedLocales = [Locale('fr'), Locale('en')];

/// Clés de service stables (indépendantes de la langue), utilisées partout
/// où un service doit être choisi (inscription, saisie rapide, correction
/// d'une analyse). La traduction affichée vient de [tr].
const serviceKeys = [
  'serviceLaboratoire',
  'serviceProduction',
  'serviceExploitation',
  'serviceReservoir',
  'serviceHse',
];

final _strings = <String, Map<String, String>>{
  'appName': {'fr': 'PuitsTrack', 'en': 'PuitsTrack'},
  'appTagline': {
    'fr': 'CPF Nawara — suivi quotidien des analyses',
    'en': 'CPF Nawara — daily analysis tracking',
  },
  'onboardingTitle': {
    'fr': 'Bienvenue sur PuitsTrack',
    'en': 'Welcome to PuitsTrack',
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
  'languageLabel': {'fr': 'Langue', 'en': 'Language'},
  'signupTitle': {'fr': 'Configurez votre profil', 'en': 'Set up your profile'},
  'signupSubtitle': {
    'fr': 'Ces informations identifient vos saisies dans l\'historique.',
    'en': 'This information identifies your entries in the history.',
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
  'phoneHint': {'fr': '00 000 000', 'en': '00 000 000'},
  'signupPasswordLabel': {'fr': 'Mot de passe', 'en': 'Password'},
  'signupInvalidPassword': {
    'fr': '8 caractères minimum.',
    'en': 'At least 8 characters.',
  },
  'signupSubmit': {'fr': 'Continuer', 'en': 'Continue'},
  'pinSetupTitle': {'fr': 'Créez votre code', 'en': 'Create your code'},
  'pinSetupSubtitle': {
    'fr': 'Ce code à 4 chiffres vous servira à déverrouiller l\'app rapidement à chaque ouverture.',
    'en': 'This 4-digit code will let you quickly unlock the app every time you open it.',
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
    'fr': 'Déverrouillez PuitsTrack',
    'en': 'Unlock PuitsTrack',
  },
  'unlockWrongPin': {'fr': 'Code incorrect, réessayez.', 'en': 'Incorrect code, try again.'},
  'unlockForgotPin': {'fr': 'Code oublié ? En créer un nouveau', 'en': 'Forgot your code? Create a new one'},
  'unlockForgotPinConfirmTitle': {'fr': 'Créer un nouveau code ?', 'en': 'Create a new code?'},
  'unlockForgotPinConfirmBody': {
    'fr': 'L\'ancien code ne fonctionnera plus. Vos puits et votre historique restent intacts.',
    'en': 'The old code will stop working. Your wells and history stay intact.',
  },
  'accountChangePin': {'fr': 'Modifier mon code', 'en': 'Change my code'},
  'logout': {'fr': 'Réinitialiser mon profil', 'en': 'Reset my profile'},

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
  'wellDetailViewAllHistory': {'fr': 'Voir tout l\'historique', 'en': 'View full history'},
  'wellHistoryTitle': {'fr': 'Historique', 'en': 'History'},
  'wellHistoryYesterday': {'fr': 'Hier', 'en': 'Yesterday'},
  'wellHistoryAllTypes': {'fr': 'Tous', 'en': 'All'},
  'wellHistoryEmpty': {
    'fr': 'Aucune analyse enregistrée pour ce filtre.',
    'en': 'No analysis recorded for this filter.',
  },
  'wellDetailNoHistory': {
    'fr': 'Aucune analyse enregistrée pour ce puits.',
    'en': 'No analysis recorded yet for this well.',
  },
  'wellDetailAddAnalysis': {'fr': 'Nouvelle analyse', 'en': 'New analysis'},
  'wellDetailNoValue': {'fr': 'Aucune valeur', 'en': 'No value yet'},
  'outOfRangeBadge': {'fr': 'Hors seuil', 'en': 'Out of range'},
  'productionTitle': {'fr': 'Production', 'en': 'Production'},
  'productionSubtitle': {
    'fr': 'Débits huile / gaz / eau — 30 derniers jours',
    'en': 'Oil / gas / water flow rates — last 30 days',
  },
  'productionOil': {'fr': 'Huile', 'en': 'Oil'},
  'productionGas': {'fr': 'Gaz', 'en': 'Gas'},
  'productionWater': {'fr': 'Eau', 'en': 'Water'},

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
  'dashboardTrendTitle': {'fr': 'Tendance de production', 'en': 'Production trend'},
  'dashboardTrendSubtitle': {'fr': 'Total, 7 derniers jours', 'en': 'Total, last 7 days'},
  'dashboardTrendNoData': {
    'fr': 'Pas encore de données sur les 7 derniers jours.',
    'en': 'No data yet for the last 7 days.',
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
  'exportTooltip': {'fr': 'Exporter', 'en': 'Export'},
  'exportStarted': {'fr': 'Préparation du fichier...', 'en': 'Preparing the file...'},
  'exportEmpty': {
    'fr': 'Rien à exporter pour le moment.',
    'en': 'Nothing to export right now.',
  },
  'exportError': {
    'fr': 'L\'export a échoué. Réessayez.',
    'en': 'Export failed. Please try again.',
  },
  'exportChooseFormatTitle': {'fr': 'Exporter en...', 'en': 'Export as...'},
  'exportFormatExcel': {'fr': 'Excel (.xlsx)', 'en': 'Excel (.xlsx)'},
  'exportFormatExcelHint': {
    'fr': 'Mise en forme tableau, s\'ouvre dans Excel ou Google Sheets.',
    'en': 'Table formatting, opens in Excel or Google Sheets.',
  },
  'exportFormatCsv': {'fr': 'CSV (.csv)', 'en': 'CSV (.csv)'},
  'exportFormatCsvHint': {
    'fr': 'Fichier texte simple, compatible avec tous les tableurs.',
    'en': 'Plain text file, compatible with any spreadsheet app.',
  },
  'wellsExportZoneTooltip': {'fr': 'Exporter cette zone', 'en': 'Export this zone'},
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
  'recordDelete': {'fr': 'Supprimer cette analyse', 'en': 'Delete this analysis'},
  'recordDeleteConfirmTitle': {'fr': 'Supprimer cette analyse ?', 'en': 'Delete this analysis?'},
  'recordDeleteConfirmBody': {
    'fr': 'Cette valeur sera définitivement supprimée de l\'historique.',
    'en': 'This value will be permanently removed from the history.',
  },
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
  'trendCompareWith': {'fr': 'Comparer avec', 'en': 'Compare with'},
  'trendCompareNone': {'fr': 'Aucune comparaison', 'en': 'No comparison'},
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
    'fr': 'Accès complet (mode local mono-appareil).',
    'en': 'Full access (local single-device mode).',
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
  'adminDeleteType': {'fr': 'Supprimer ce type', 'en': 'Delete this type'},
  'adminDeleteTypeConfirmTitle': {'fr': 'Supprimer ce type d\'analyse ?', 'en': 'Delete this analysis type?'},
  'adminDeleteTypeConfirmBody': {
    'fr': 'Tout l\'historique saisi pour ce type, sur tous les puits, sera perdu définitivement.',
    'en': 'All history recorded for this type, across every well, will be permanently lost.',
  },
  'adminTypeDeleted': {'fr': 'Type d\'analyse supprimé.', 'en': 'Analysis type deleted.'},

  // Gestion des puits
  'wellsManageTitle': {'fr': 'Gestion des puits', 'en': 'Manage wells'},
  'wellsManageAdd': {'fr': 'Ajouter un puits', 'en': 'Add a well'},
  'wellsManageNew': {'fr': 'Nouveau puits', 'en': 'New well'},
  'wellsManageEdit': {'fr': 'Modifier le puits', 'en': 'Edit well'},
  'wellsManageNameLabel': {'fr': 'Nom du puits', 'en': 'Well name'},
  'wellsManageNameHint': {'fr': 'Ex: Puits Nord 3', 'en': 'e.g. North Well 3'},
  'wellsManageInvalidName': {'fr': 'Veuillez saisir un nom.', 'en': 'Please enter a name.'},
  'wellsManageCodeLabel': {'fr': 'Code', 'en': 'Code'},
  'wellsManageCodeHint': {'fr': 'Ex: PN-03', 'en': 'e.g. PN-03'},
  'wellsManageInvalidCode': {'fr': 'Veuillez saisir un code.', 'en': 'Please enter a code.'},
  'wellsManageGroupLabel': {'fr': 'Groupe / Zone', 'en': 'Group / Zone'},
  'wellsManageGroupHint': {'fr': 'Ex: Zone Nord', 'en': 'e.g. North Zone'},
  'wellsManageActiveLabel': {'fr': 'Puits actif', 'en': 'Active well'},
  'wellsManageSave': {'fr': 'Enregistrer', 'en': 'Save'},
  'wellsManageAdded': {'fr': 'Puits ajouté.', 'en': 'Well added.'},
  'wellsManageUpdated': {'fr': 'Puits mis à jour.', 'en': 'Well updated.'},
  'wellsManageDeleted': {'fr': 'Puits supprimé.', 'en': 'Well deleted.'},
  'wellsManageDelete': {'fr': 'Supprimer ce puits', 'en': 'Delete this well'},
  'wellsManageDeleteConfirmTitle': {'fr': 'Supprimer ce puits ?', 'en': 'Delete this well?'},
  'wellsManageDeleteConfirmBody': {
    'fr': 'Tout l\'historique d\'analyses de ce puits sera perdu définitivement.',
    'en': 'All analysis history for this well will be permanently lost.',
  },
  'wellsManageEmpty': {'fr': 'Aucun puits pour le moment.', 'en': 'No wells yet.'},

  // Statistiques
  'statsTitle': {'fr': 'Statistiques', 'en': 'Statistics'},
  'statsModeCompliance': {'fr': 'Conformité', 'en': 'Compliance'},
  'statsModeThresholds': {'fr': 'Seuils', 'en': 'Thresholds'},
  'navStats': {'fr': 'Stats', 'en': 'Stats'},
  'statsPeriod7': {'fr': '7 jours', 'en': '7 days'},
  'statsPeriod30': {'fr': '30 jours', 'en': '30 days'},
  'statsPeriodAll': {'fr': 'Tout', 'en': 'All time'},
  'statsCompliance': {'fr': 'conformité', 'en': 'compliance'},
  'statsAnalysesCount': {'fr': 'analyses', 'en': 'analyses'},
  'statsOutOfRangeCount': {'fr': 'hors seuil', 'en': 'out of range'},
  'statsNoData': {'fr': 'Aucune analyse sur cette période.', 'en': 'No analysis for this period.'},
  'statsUnassignedGroup': {'fr': 'Sans groupe', 'en': 'Unassigned'},
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
