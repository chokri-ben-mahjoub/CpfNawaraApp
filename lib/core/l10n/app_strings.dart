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
    'fr': 'Suivi quotidien des analyses de puits',
    'en': 'Daily well analysis tracking',
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
  'exportFormatExcel': {'fr': 'Excel (.xlsx)', 'en': 'Excel (.xlsx)'},
  'exportFormatExcelHint': {
    'fr': 'Une feuille par thème, s\'ouvre dans Excel ou Sheets.',
    'en': 'One sheet per topic, opens in Excel or Sheets.',
  },
  'exportFormatCsv': {'fr': 'CSV (.csv)', 'en': 'CSV (.csv)'},
  'exportFormatCsvHint': {
    'fr': 'Texte simple, un fichier par thème.',
    'en': 'Plain text, one file per topic.',
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
  'statsCompliance': {'fr': 'conformité', 'en': 'compliance'},
  'statsAnalysesCount': {'fr': 'analyses', 'en': 'analyses'},
  'statsOutOfRangeCount': {'fr': 'hors seuil', 'en': 'out of range'},
  'statsNoData': {'fr': 'Aucune analyse sur cette période.', 'en': 'No analysis for this period.'},
  'statsUnassignedGroup': {'fr': 'Sans groupe', 'en': 'Unassigned'},

  // Commun
  'yes': {'fr': 'Oui', 'en': 'Yes'},
  'no': {'fr': 'Non', 'en': 'No'},
  'edit': {'fr': 'Modifier', 'en': 'Edit'},
  'set': {'fr': 'Renseigner', 'en': 'Set'},
  'notSet': {'fr': 'non renseignée', 'en': 'not set'},
  'seeAll': {'fr': 'Voir tout', 'en': 'See all'},
  'daysShort': {'fr': 'j', 'en': 'd'},
  'yearShort': {'fr': 'an', 'en': 'yr'},
  'dayPrefix': {'fr': 'J', 'en': 'D'},
  'frequencyOnDemand': {'fr': 'À la demande (ponctuelle)', 'en': 'On demand (occasional)'},

  // Export : télécharger ou partager
  'exportSheetTitle': {'fr': 'Exporter', 'en': 'Export'},
  'exportSheetSubtitle': {
    'fr': 'Choisissez le format, puis téléchargez le fichier sur cet appareil ou partagez-le.',
    'en': 'Choose the format, then download the file to this device or share it.',
  },
  'exportActionDownload': {'fr': 'Télécharger', 'en': 'Download'},
  'exportActionDownloadHint': {
    'fr': 'Enregistré dans Téléchargements › PuitsTrack',
    'en': 'Saved to Downloads › PuitsTrack',
  },
  'exportActionShare': {'fr': 'Partager', 'en': 'Share'},
  'exportActionShareHint': {
    'fr': 'WhatsApp, e-mail, Drive...',
    'en': 'WhatsApp, email, Drive...',
  },
  'exportSavedOne': {
    'fr': 'Fichier enregistré dans Téléchargements › PuitsTrack :',
    'en': 'File saved to Downloads › PuitsTrack:',
  },
  'exportSavedMany': {
    'fr': 'fichiers enregistrés dans Téléchargements › PuitsTrack',
    'en': 'files saved to Downloads › PuitsTrack',
  },
  'exportOpen': {'fr': 'Ouvrir', 'en': 'Open'},
  'exportDownloadedOne': {'fr': 'Fichier téléchargé :', 'en': 'File downloaded:'},
  'exportDownloadedMany': {'fr': 'fichiers téléchargés', 'en': 'files downloaded'},
  'exportActionDownloadHintWeb': {
    'fr': 'Dans le dossier Téléchargements du navigateur',
    'en': 'To the browser\'s Downloads folder',
  },
  'exportNoAppToOpen': {
    'fr': 'Aucune application installée pour ouvrir ce fichier (Excel, Google Sheets, WPS...). '
        'Il reste disponible dans Téléchargements.',
    'en': 'No installed app can open this file (Excel, Google Sheets, WPS...). '
        'It is still available in Downloads.',
  },
  'exportPermissionDenied': {
    'fr': 'Autorisation de stockage refusée : impossible d\'enregistrer le fichier. Utilisez "Partager".',
    'en': 'Storage permission denied: the file could not be saved. Use "Share" instead.',
  },
  'exportSheetAnalyses': {'fr': 'Analyses', 'en': 'Analyses'},
  'exportSheetProduction': {'fr': 'Production et ratios', 'en': 'Production and ratios'},
  'exportSheetInterventions': {'fr': 'Interventions', 'en': 'Interventions'},
  'exportSheetSummary': {'fr': 'Synthèse', 'en': 'Summary'},
  'exportSheetData': {'fr': 'Données', 'en': 'Data'},
  'colMin': {'fr': 'Seuil min', 'en': 'Min threshold'},
  'colMax': {'fr': 'Seuil max', 'en': 'Max threshold'},
  'colLastEntry': {'fr': 'Dernière saisie', 'en': 'Last entry'},

  // Filtres
  'filterField': {'fr': 'Champ / zone', 'en': 'Field / zone'},
  'filterFieldAll': {'fr': 'Tous les champs', 'en': 'All fields'},
  'filterStatus': {'fr': 'Statut', 'en': 'Status'},
  'filterStatusAll': {'fr': 'Tous statuts', 'en': 'All statuses'},
  'filterStatusActive': {'fr': 'Actifs', 'en': 'Active'},
  'filterStatusStopped': {'fr': 'Arrêtés', 'en': 'Stopped'},
  'filterPeriod': {'fr': 'Période', 'en': 'Period'},
  'filterWell': {'fr': 'Puits', 'en': 'Well'},
  'filterReset': {'fr': 'Effacer', 'en': 'Clear'},
  'periodToday': {'fr': 'Aujourd\'hui', 'en': 'Today'},
  'period7': {'fr': '7 jours', 'en': '7 days'},
  'period30': {'fr': '30 jours', 'en': '30 days'},
  'period90': {'fr': '90 jours', 'en': '90 days'},
  'period180': {'fr': '6 mois', 'en': '6 months'},
  'period365': {'fr': '12 mois', 'en': '12 months'},
  'periodAll': {'fr': 'Tout l\'historique', 'en': 'All time'},
  'periodCustom': {'fr': 'Dates personnalisées...', 'en': 'Custom dates...'},
  'wellsCountSingular': {'fr': 'puits', 'en': 'well'},
  'wellsCountPlural': {'fr': 'puits', 'en': 'wells'},

  // Indicateurs calculés
  'ratiosTitle': {'fr': 'Indicateurs calculés', 'en': 'Calculated indicators'},
  'ratiosSubtitle': {
    'fr': 'Calculés automatiquement à partir des débits saisis — touchez un indicateur pour son évolution.',
    'en': 'Calculated automatically from the entered rates — tap an indicator to see its trend.',
  },
  'ratioGor': {'fr': 'GOR', 'en': 'GOR'},
  'ratioWor': {'fr': 'WOR', 'en': 'WOR'},
  'ratioGlr': {'fr': 'GLR', 'en': 'GLR'},
  'ratioPi': {'fr': 'PI', 'en': 'PI'},
  'ratioGorDesc': {
    'fr': 'GOR (Gas-Oil Ratio) = débit gaz ÷ débit huile, le même jour.',
    'en': 'GOR (Gas-Oil Ratio) = gas rate ÷ oil rate, same day.',
  },
  'ratioWorDesc': {
    'fr': 'WOR (Water-Oil Ratio) = débit eau ÷ débit huile, le même jour.',
    'en': 'WOR (Water-Oil Ratio) = water rate ÷ oil rate, same day.',
  },
  'ratioGlrDesc': {
    'fr': 'GLR (Gas-Liquid Ratio) = débit gaz ÷ (débit huile + débit eau), le même jour.',
    'en': 'GLR (Gas-Liquid Ratio) = gas rate ÷ (oil rate + water rate), same day.',
  },
  'ratioPiDesc': {
    'fr': 'PI (indice de productivité) = débit liquide ÷ (Pr − Pwf). Calculé à chaque mesure de la '
        'pression de fond (Pwf), avec la pression de gisement (Pr) du puits.',
    'en': 'PI (productivity index) = liquid rate ÷ (Pr − Pwf). Calculated for every bottom-hole '
        'pressure (Pwf) measurement, using the well\'s reservoir pressure (Pr).',
  },
  'ratioMissingInputs': {
    'fr': 'Pas encore de données : ce ratio nécessite des débits saisis le même jour.',
    'en': 'No data yet: this ratio needs rates entered on the same day.',
  },
  'piMissingInputs': {
    'fr': 'Le PI nécessite la pression de gisement (Pr) du puits et au moins une mesure de '
        '"Pression de fond (Pwf)" avec un débit huile saisi à moins de 3 jours.',
    'en': 'PI needs the well\'s reservoir pressure (Pr) and at least one "Bottom-hole pressure (Pwf)" '
        'measurement with an oil rate entered within 3 days.',
  },
  'piNeedsPr': {'fr': 'Renseigner Pr', 'en': 'Set Pr first'},
  'reservoirPressureTitle': {'fr': 'Pression de gisement', 'en': 'Reservoir pressure'},
  'reservoirPressureLabel': {'fr': 'Pression de gisement (Pr)', 'en': 'Reservoir pressure (Pr)'},
  'reservoirPressureHint': {
    'fr': 'Valeur issue du dernier test de remontée de pression. Elle sert au calcul de l\'indice de '
        'productivité (PI). Laisser vide si inconnue.',
    'en': 'Value from the latest pressure build-up test. Used to compute the productivity index (PI). '
        'Leave empty if unknown.',
  },
  'reservoirPressureHelper': {
    'fr': 'Optionnel — nécessaire pour calculer le PI',
    'en': 'Optional — needed to compute PI',
  },

  // Déclin
  'declineTitle': {'fr': 'Courbe de déclin', 'en': 'Decline curve'},
  'declineCardSubtitle': {
    'fr': 'Taux de déclin effectif annuel, calculé automatiquement (depuis la dernière intervention).',
    'en': 'Effective annual decline rate, calculated automatically (since the last intervention).',
  },
  'declineFluid': {'fr': 'Débit analysé', 'en': 'Analysed rate'},
  'declineWindow': {'fr': 'Données utilisées', 'en': 'Data used'},
  'declineWindowAuto': {'fr': 'Auto (depuis la dernière intervention)', 'en': 'Auto (since last intervention)'},
  'declineHorizon': {'fr': 'Horizon de prévision', 'en': 'Forecast horizon'},
  'declineForecast': {'fr': 'Prévision', 'en': 'Forecast'},
  'declineLogScale': {'fr': 'Échelle log', 'en': 'Log scale'},
  'declineMeasured': {'fr': 'Mesuré', 'en': 'Measured'},
  'declineFitted': {'fr': 'Ajusté', 'en': 'Fitted'},
  'declineOutsideWindow': {'fr': 'Hors fenêtre', 'en': 'Outside window'},
  'declineNoData': {
    'fr': 'Pas encore assez de débits saisis pour tracer une courbe.',
    'en': 'Not enough rates entered yet to draw a curve.',
  },
  'declineNotEnoughPoints': {
    'fr': 'Le calcul du déclin nécessite au moins 3 débits positifs, sur au moins 2 jours différents, '
        'dans la fenêtre choisie.',
    'en': 'The decline calculation needs at least 3 positive rates, on at least 2 different days, '
        'within the selected window.',
  },
  'declineNotEnoughShort': {'fr': 'Données insuffisantes', 'en': 'Not enough data'},
  'declineEffectiveAnnual': {'fr': 'Déclin effectif annuel', 'en': 'Effective annual decline'},
  'declineGrowthAnnual': {'fr': 'Hausse annuelle (pas de déclin)', 'en': 'Annual growth (no decline)'},
  'declineEffectiveMonthly': {'fr': 'Déclin effectif mensuel', 'en': 'Effective monthly decline'},
  'declineNominalAnnual': {'fr': 'Déclin nominal annuel (D × 365)', 'en': 'Nominal annual decline (D × 365)'},
  'declineQi': {'fr': 'Débit initial ajusté', 'en': 'Fitted initial rate'},
  'declinePoints': {'fr': 'Mesures utilisées', 'en': 'Measurements used'},
  'declineFitGood': {'fr': 'bon ajustement', 'en': 'good fit'},
  'declineFitMedium': {'fr': 'ajustement moyen', 'en': 'moderate fit'},
  'declineFitPoor': {'fr': 'données dispersées, à interpréter avec prudence', 'en': 'scattered data, interpret with care'},
  'declineSinceIntervention': {
    'fr': 'Calculé depuis la dernière intervention.',
    'en': 'Calculated since the last intervention.',
  },
  'declineOnWindow': {'fr': 'Calculé sur la fenêtre de données choisie.', 'en': 'Calculated on the selected data window.'},
  'declineForecastTitle': {'fr': 'Prévision (modèle exponentiel)', 'en': 'Forecast (exponential model)'},
  'declineRateIn': {'fr': 'Débit prévu dans', 'en': 'Forecast rate in'},
  'declineCumulative': {'fr': 'Production cumulée prévue sur', 'en': 'Forecast cumulative production over'},
  'declineLimitLabel': {'fr': 'Débit limite économique (optionnel)', 'en': 'Economic limit rate (optional)'},
  'declineLimitReached': {
    'fr': 'Débit limite atteint dans environ {days} jours (vers le {date}).',
    'en': 'Limit rate reached in about {days} days (around {date}).',
  },
  'declineLimitNever': {
    'fr': 'Le débit limite n\'est pas atteint avec la tendance actuelle (ou est déjà dépassé).',
    'en': 'The limit rate is not reached with the current trend (or is already passed).',
  },
  'declineMethodNote': {
    'fr': 'Méthode : déclin exponentiel d\'Arps (b = 0), q(t) = qi·e^(−D·t), ajusté par régression '
        'linéaire de ln(q) sur le temps. Déclin effectif = 1 − e^(−D·durée). En mode Auto, le calcul '
        'repart du lendemain de la dernière intervention, qui modifie généralement le comportement du puits.',
    'en': 'Method: Arps exponential decline (b = 0), q(t) = qi·e^(−D·t), fitted by linear regression of '
        'ln(q) over time. Effective decline = 1 − e^(−D·duration). In Auto mode, the fit restarts the day '
        'after the last intervention, which usually changes the well\'s behaviour.',
  },
  'declineIndicator': {'fr': 'Indicateur', 'en': 'Indicator'},
  'declineFrom': {'fr': 'Du', 'en': 'From'},
  'declineTo': {'fr': 'Au', 'en': 'To'},
  'declineUsed': {'fr': 'Utilisé pour le calcul', 'en': 'Used in fit'},

  // Comparaison
  'compareTitle': {'fr': 'Comparer', 'en': 'Compare'},
  'compareEntrySubtitle': {
    'fr': 'Deux puits, deux périodes, ou avant/après une intervention',
    'en': 'Two wells, two periods, or before/after an intervention',
  },
  'compareModeWells': {'fr': 'Deux puits', 'en': 'Two wells'},
  'compareModePeriods': {'fr': 'Deux périodes', 'en': 'Two periods'},
  'compareMetric': {'fr': 'Paramètre', 'en': 'Parameter'},
  'compareWellA': {'fr': 'Puits A', 'en': 'Well A'},
  'compareWellB': {'fr': 'Puits B', 'en': 'Well B'},
  'comparePivot': {'fr': 'Comparer autour de', 'en': 'Compare around'},
  'compareFreeDates': {'fr': 'Dates libres (période A / B)', 'en': 'Free dates (period A / B)'},
  'compareWindow': {'fr': 'Durée avant / après', 'en': 'Window before / after'},
  'comparePeriodA': {'fr': 'Période A', 'en': 'Period A'},
  'comparePeriodB': {'fr': 'Période B', 'en': 'Period B'},
  'compareBefore': {'fr': 'Avant', 'en': 'Before'},
  'compareAfter': {'fr': 'Après', 'en': 'After'},
  'compareNoData': {'fr': 'Pas de données sur ces périodes pour ce paramètre.', 'en': 'No data for this parameter over these periods.'},
  'compareNoInterventionHint': {
    'fr': 'Astuce : enregistrez une intervention sur ce puits (fiche puits › Interventions) pour comparer '
        'automatiquement avant / après.',
    'en': 'Tip: record an intervention on this well (well page › Interventions) to compare before / after '
        'automatically.',
  },
  'compareStatPeriod': {'fr': 'Période', 'en': 'Period'},
  'compareStatCount': {'fr': 'Mesures', 'en': 'Measurements'},
  'compareStatMean': {'fr': 'Moyenne', 'en': 'Average'},
  'compareStatMin': {'fr': 'Minimum', 'en': 'Minimum'},
  'compareStatMax': {'fr': 'Maximum', 'en': 'Maximum'},
  'compareStatFirst': {'fr': 'Première', 'en': 'First'},
  'compareStatLast': {'fr': 'Dernière', 'en': 'Last'},
  'compareDeltaPct': {'fr': 'Écart', 'en': 'Change'},
  'compareSeries': {'fr': 'Série', 'en': 'Series'},
  'compareHigher': {'fr': 'supérieure', 'en': 'higher'},
  'compareLower': {'fr': 'inférieure', 'en': 'lower'},
  'compareVerdictWells': {
    'fr': 'Période {period} : la moyenne de {b} est {diff} {dir} à celle de {a}.',
    'en': 'Period {period}: the average of {b} is {diff} {dir} than that of {a}.',
  },
  'compareVerdictIntervention': {
    'fr': 'Après {type} du {date}, la moyenne de {metric} a varié de {change}.',
    'en': 'After the {type} on {date}, the {metric} average changed by {change}.',
  },
  'compareVerdictPeriods': {
    'fr': 'De la période A à la période B, la moyenne de {metric} a varié de {change}.',
    'en': 'From period A to period B, the {metric} average changed by {change}.',
  },

  // Interventions
  'interventionsTitle': {'fr': 'Interventions', 'en': 'Interventions'},
  'interventionsShort': {'fr': 'intervention(s)', 'en': 'intervention(s)'},
  'interventionsEmpty': {
    'fr': 'Aucune intervention enregistrée sur ce puits.\nAjoutez workovers, stimulations, changements de '
        'duse... : ils apparaîtront en marqueurs sur les courbes.',
    'en': 'No intervention recorded on this well.\nAdd workovers, stimulations, choke changes...: they will '
        'show up as markers on the charts.',
  },
  'interventionsEmptyShort': {
    'fr': 'Aucune intervention — touchez + pour en ajouter une.',
    'en': 'No intervention — tap + to add one.',
  },
  'interventionsCount': {'fr': 'Interventions', 'en': 'Interventions'},
  'interventionsTotalCost': {'fr': 'Coût total', 'en': 'Total cost'},
  'interventionsMarkersHint': {
    'fr': 'Chaque intervention apparaît en ligne verticale violette sur les courbes du puits. '
        'Le bouton à flèches violettes compare le paramètre choisi avant / après.',
    'en': 'Each intervention appears as a purple vertical line on the well\'s charts. '
        'The purple arrows button compares the chosen parameter before / after.',
  },
  'interventionAdd': {'fr': 'Ajouter une intervention', 'en': 'Add an intervention'},
  'interventionNew': {'fr': 'Nouvelle intervention', 'en': 'New intervention'},
  'interventionEdit': {'fr': 'Modifier l\'intervention', 'en': 'Edit intervention'},
  'interventionAdded': {'fr': 'Intervention enregistrée.', 'en': 'Intervention saved.'},
  'interventionUpdated': {'fr': 'Intervention mise à jour.', 'en': 'Intervention updated.'},
  'interventionDeleted': {'fr': 'Intervention supprimée.', 'en': 'Intervention deleted.'},
  'interventionDelete': {'fr': 'Supprimer', 'en': 'Delete'},
  'interventionDeleteConfirmTitle': {'fr': 'Supprimer cette intervention ?', 'en': 'Delete this intervention?'},
  'interventionDeleteConfirmBody': {
    'fr': 'Elle disparaîtra du journal et des courbes. Les analyses du puits ne sont pas touchées.',
    'en': 'It will be removed from the log and the charts. The well\'s analyses are not affected.',
  },
  'interventionDateLabel': {'fr': 'Date', 'en': 'Date'},
  'interventionTypeLabel': {'fr': 'Type d\'intervention', 'en': 'Intervention type'},
  'interventionCostLabel': {'fr': 'Coût (optionnel)', 'en': 'Cost (optional)'},
  'interventionInvalidCost': {'fr': 'Montant invalide.', 'en': 'Invalid amount.'},
  'interventionCurrencyLabel': {'fr': 'Devise', 'en': 'Currency'},
  'interventionResultLabel': {'fr': 'Résultat', 'en': 'Result'},
  'interventionDescriptionLabel': {'fr': 'Description / observations', 'en': 'Description / notes'},
  'interventionDescriptionHint': {
    'fr': 'Ex: duse 32/64 → 40/64, acidification 15 % HCl...',
    'en': 'e.g. choke 32/64 → 40/64, 15% HCl acid job...',
  },
  'interventionCompareBeforeAfter': {'fr': 'Comparer avant / après', 'en': 'Compare before / after'},
  'interventionTypeWorkover': {'fr': 'Workover', 'en': 'Workover'},
  'interventionTypeStimulation': {'fr': 'Stimulation (acidification)', 'en': 'Stimulation (acidizing)'},
  'interventionTypeFracturing': {'fr': 'Fracturation', 'en': 'Hydraulic fracturing'},
  'interventionTypeChokeChange': {'fr': 'Changement de duse', 'en': 'Choke change'},
  'interventionTypeCleanout': {'fr': 'Nettoyage (coiled tubing)', 'en': 'Cleanout (coiled tubing)'},
  'interventionTypeWireline': {'fr': 'Wireline / slickline', 'en': 'Wireline / slickline'},
  'interventionTypePerforation': {'fr': 'Perforation', 'en': 'Perforation'},
  'interventionTypeArtificialLift': {'fr': 'Activation (pompe, gas lift)', 'en': 'Artificial lift (pump, gas lift)'},
  'interventionTypeShutIn': {'fr': 'Arrêt / remise en production', 'en': 'Shut-in / back on production'},
  'interventionTypeOther': {'fr': 'Autre', 'en': 'Other'},
  'interventionResultSuccess': {'fr': 'Succès', 'en': 'Success'},
  'interventionResultPartial': {'fr': 'Partiel', 'en': 'Partial'},
  'interventionResultFailure': {'fr': 'Échec', 'en': 'Failure'},
  'interventionResultPending': {'fr': 'À évaluer', 'en': 'To be assessed'},

  // Réglages
  'settingsTitle': {'fr': 'Réglages', 'en': 'Settings'},
  'settingsEntrySubtitle': {
    'fr': 'Apparence, sécurité, sauvegarde, rappels...',
    'en': 'Appearance, security, backup, reminders...',
  },
  'settingsProfile': {'fr': 'Profil', 'en': 'Profile'},
  'settingsEditProfile': {'fr': 'Modifier le profil', 'en': 'Edit profile'},
  'settingsAppearance': {'fr': 'Apparence', 'en': 'Appearance'},
  'settingsTheme': {'fr': 'Thème', 'en': 'Theme'},
  'themeLight': {'fr': 'Clair', 'en': 'Light'},
  'themeAuto': {'fr': 'Auto', 'en': 'Auto'},
  'themeDark': {'fr': 'Sombre', 'en': 'Dark'},
  'themeAutoHint': {
    'fr': 'Auto suit le réglage du téléphone (clair le jour, sombre si le mode sombre est activé).',
    'en': 'Auto follows the phone setting (light, or dark when dark mode is on).',
  },
  'settingsSecurity': {'fr': 'Sécurité', 'en': 'Security'},
  'settingsBiometric': {'fr': 'Déverrouillage par empreinte', 'en': 'Fingerprint unlock'},
  'settingsBiometricHint': {
    'fr': 'Proposer l\'empreinte (ou le visage) au déverrouillage, en plus du code.',
    'en': 'Offer fingerprint (or face) unlock, in addition to the code.',
  },
  'settingsBiometricUnavailable': {
    'fr': 'Non disponible ou non configuré sur ce téléphone.',
    'en': 'Not available or not set up on this phone.',
  },
  'settingsAutoLock': {'fr': 'Verrouillage automatique', 'en': 'Auto-lock'},
  'settingsAutoLockHint': {
    'fr': 'Délai avant de redemander le code quand l\'app passe en arrière-plan.',
    'en': 'Delay before asking for the code again once the app is in the background.',
  },
  'autoLockImmediate': {'fr': 'Immédiat', 'en': 'Immediately'},
  'settingsSecureScreen': {'fr': 'Écran protégé', 'en': 'Protected screen'},
  'settingsSecureScreenHint': {
    'fr': 'Bloque les captures d\'écran et masque le contenu dans les applications récentes.',
    'en': 'Blocks screenshots and hides the content in the recent apps view.',
  },
  'settingsBackup': {'fr': 'Sauvegarde', 'en': 'Backup'},
  'backupIntro': {
    'fr': 'Les données (puits, seuils, analyses, interventions) sont stockées uniquement sur cet appareil. '
        'Envoyez régulièrement une sauvegarde sur Drive ou par e-mail pour ne rien perdre en cas de perte '
        'ou de changement de téléphone.',
    'en': 'Data (wells, thresholds, analyses, interventions) is stored on this device only. '
        'Regularly send a backup to Drive or by email so nothing is lost if the phone is lost or replaced.',
  },
  'backupLast': {'fr': 'Dernière sauvegarde', 'en': 'Last backup'},
  'backupNever': {'fr': 'jamais', 'en': 'never'},
  'backupToday': {'fr': 'aujourd\'hui', 'en': 'today'},
  'backupDaysAgo': {'fr': 'il y a {n} j', 'en': '{n} days ago'},
  'backupSaveToPhone': {'fr': 'Enregistrer sur le téléphone', 'en': 'Save to phone'},
  'backupDownload': {'fr': 'Télécharger la sauvegarde', 'en': 'Download the backup'},
  'backupDownloaded': {'fr': 'Sauvegarde téléchargée :', 'en': 'Backup downloaded:'},
  'backupShare': {'fr': 'Envoyer (Drive, e-mail, WhatsApp...)', 'en': 'Send (Drive, email, WhatsApp...)'},
  'backupShareSubject': {'fr': 'Sauvegarde PuitsTrack', 'en': 'PuitsTrack backup'},
  'backupRestore': {'fr': 'Restaurer une sauvegarde', 'en': 'Restore a backup'},
  'backupSaved': {
    'fr': 'Sauvegarde enregistrée dans Téléchargements › PuitsTrack › Sauvegardes :',
    'en': 'Backup saved to Downloads › PuitsTrack › Sauvegardes:',
  },
  'backupFailed': {'fr': 'La sauvegarde a échoué. Réessayez.', 'en': 'The backup failed. Try again.'},
  'backupRestoreConfirmTitle': {'fr': 'Restaurer cette sauvegarde ?', 'en': 'Restore this backup?'},
  'backupRestoreConfirmBody': {
    'fr': 'Sauvegarde du {date} : {wells} puits, {records} analyses, {interventions} interventions.\n\n'
        'Toutes les données actuelles seront remplacées. Une copie de sécurité des données actuelles est '
        'd\'abord enregistrée dans Téléchargements › PuitsTrack › Sauvegardes.',
    'en': 'Backup from {date}: {wells} wells, {records} analyses, {interventions} interventions.\n\n'
        'All current data will be replaced. A safety copy of the current data is saved first in '
        'Downloads › PuitsTrack › Sauvegardes.',
  },
  'backupRestoreConfirm': {'fr': 'Restaurer', 'en': 'Restore'},
  'backupRestored': {'fr': 'Sauvegarde restaurée.', 'en': 'Backup restored.'},
  'backupRestoreFailed': {
    'fr': 'La restauration a échoué : les données actuelles n\'ont pas été modifiées.',
    'en': 'The restore failed: current data was not changed.',
  },
  'backupErrorNotJson': {'fr': 'Ce fichier n\'est pas une sauvegarde valide.', 'en': 'This file is not a valid backup.'},
  'backupErrorNotPuitsTrack': {
    'fr': 'Ce fichier n\'est pas une sauvegarde PuitsTrack.',
    'en': 'This file is not a PuitsTrack backup.',
  },
  'backupErrorTooRecent': {
    'fr': 'Sauvegarde créée par une version plus récente de l\'app : mettez d\'abord l\'app à jour.',
    'en': 'Backup made by a newer version of the app: update the app first.',
  },
  'backupErrorCorrupted': {
    'fr': 'Le contenu de la sauvegarde est incomplet ou corrompu.',
    'en': 'The backup content is incomplete or corrupted.',
  },
  'backupErrorEmpty': {'fr': 'Cette sauvegarde ne contient aucune donnée.', 'en': 'This backup contains no data.'},
  'autoBackupTitle': {'fr': 'Sauvegarde automatique', 'en': 'Automatic backup'},
  'autoBackupHint': {
    'fr': 'À l\'ouverture de l\'app, dans Téléchargements › PuitsTrack › Sauvegardes '
        '(2 fichiers utilisés à tour de rôle).',
    'en': 'When the app opens, in Downloads › PuitsTrack › Sauvegardes (2 files used in turn).',
  },
  'autoBackupOff': {'fr': 'Désactivée', 'en': 'Off'},
  'autoBackupDaily': {'fr': 'Chaque jour', 'en': 'Daily'},
  'autoBackupWeekly': {'fr': 'Chaque semaine', 'en': 'Weekly'},
  'settingsReminders': {'fr': 'Rappels', 'en': 'Reminders'},
  'reminderDaily': {'fr': 'Rappel quotidien de saisie', 'en': 'Daily entry reminder'},
  'reminderDailyHint': {
    'fr': 'Notification chaque jour à l\'heure choisie, sautée si tout est déjà saisi.',
    'en': 'Notification every day at the chosen time, skipped when everything is already entered.',
  },
  'reminderTime': {'fr': 'Heure du rappel', 'en': 'Reminder time'},
  'reminderPermissionDenied': {
    'fr': 'Notifications refusées : autorisez-les dans les paramètres du téléphone.',
    'en': 'Notifications denied: allow them in the phone settings.',
  },
  'reminderChannelName': {'fr': 'Rappel de saisie', 'en': 'Entry reminder'},
  'reminderTitle': {'fr': 'Analyses du jour', 'en': 'Today\'s analyses'},
  'reminderBody': {
    'fr': 'Pensez à saisir les analyses de vos puits.',
    'en': 'Remember to enter your wells\' analyses.',
  },
  'settingsEntryExport': {'fr': 'Saisie et export', 'en': 'Entry and export'},
  'settingsDefaultService': {'fr': 'Service par défaut', 'en': 'Default department'},
  'settingsDefaultServiceHint': {
    'fr': 'Pré-sélectionné à chaque nouvelle analyse (modifiable).',
    'en': 'Pre-selected for every new analysis (can be changed).',
  },
  'settingsServiceFromProfile': {'fr': 'Celui de mon profil', 'en': 'From my profile'},
  'settingsServiceNone': {'fr': 'Aucun (choisir à chaque fois)', 'en': 'None (choose every time)'},
  'settingsDefaultCurrency': {'fr': 'Devise des interventions', 'en': 'Intervention currency'},
  'settingsDefaultCurrencyHint': {
    'fr': 'Devise proposée par défaut pour le coût d\'une intervention.',
    'en': 'Currency proposed by default for an intervention cost.',
  },
  'settingsCsvFormat': {'fr': 'Format CSV', 'en': 'CSV format'},
  'csvFormatFr': {'fr': 'Excel FR', 'en': 'Excel FR'},
  'csvFormatIntl': {'fr': 'International', 'en': 'International'},
  'csvFormatFrHint': {
    'fr': 'Séparateur « ; » et virgule décimale (Excel en français).',
    'en': 'Separator ";" and decimal comma (French Excel).',
  },
  'csvFormatIntlHint': {
    'fr': 'Séparateur « , » et point décimal (Excel en anglais, Google Sheets).',
    'en': 'Separator "," and decimal point (English Excel, Google Sheets).',
  },
  'settingsConfiguration': {'fr': 'Paramétrage', 'en': 'Configuration'},
  'settingsData': {'fr': 'Données', 'en': 'Data'},
  'settingsDataHint': {
    'fr': 'Stockées localement sur ce téléphone (mode hors-ligne, sans compte).',
    'en': 'Stored locally on this phone (offline mode, no account).',
  },
  'settingsDbSize': {'fr': 'Taille de la base', 'en': 'Database size'},
  'settingsDataHintWeb': {
    'fr': 'Stockées dans ce navigateur, sur ce PC (effacer les données du site les supprime : '
        'gardez des sauvegardes).',
    'en': 'Stored in this browser, on this PC (clearing site data deletes them: keep backups).',
  },
  'settingsDataHintDesktop': {
    'fr': 'Stockées localement sur ce PC (mode hors-ligne, sans compte).',
    'en': 'Stored locally on this PC (offline mode, no account).',
  },
  'settingsAbout': {'fr': 'À propos', 'en': 'About'},
  'settingsAboutBody': {
    'fr': 'Application personnelle de suivi des analyses de puits. Fonctionne hors-ligne.',
    'en': 'Personal well analysis tracking app. Works offline.',
  },
};

/// Traduit une clé pour une [Locale] donnée ; retombe sur le français.
String tr(Locale locale, String key) {
  final entry = _strings[key];
  if (entry == null) return key;
  return entry[locale.languageCode] ?? entry['fr'] ?? key;
}

/// Remplace les marqueurs `{nom}` d'une chaîne traduite par leurs valeurs.
String fill(String template, Map<String, String> values) {
  var result = template;
  values.forEach((key, value) => result = result.replaceAll('{$key}', value));
  return result;
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
