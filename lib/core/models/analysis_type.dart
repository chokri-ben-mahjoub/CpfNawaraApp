import '../l10n/app_strings.dart';

/// `onDemand` : analyse ponctuelle (ex: pression de fond mesurée lors d'un
/// test de puits), jamais attendue un jour donné — n'apparaît donc ni dans
/// le "à faire" du tableau de bord ni dans les alertes de retard.
enum AnalysisFrequency { daily, weekly, monthly, onDemand }

extension AnalysisFrequencyX on AnalysisFrequency {
  /// Clé de traduction associée (voir `app_strings.dart`).
  String get labelKey {
    switch (this) {
      case AnalysisFrequency.daily:
        return 'frequencyDaily';
      case AnalysisFrequency.weekly:
        return 'frequencyWeekly';
      case AnalysisFrequency.monthly:
        return 'frequencyMonthly';
      case AnalysisFrequency.onDemand:
        return 'frequencyOnDemand';
    }
  }

  /// Valeur stockée en base (locale et Firestore), stable indépendamment de la
  /// langue ou de l'ordre de l'enum.
  String get storageKey {
    switch (this) {
      case AnalysisFrequency.daily:
        return 'daily';
      case AnalysisFrequency.weekly:
        return 'weekly';
      case AnalysisFrequency.monthly:
        return 'monthly';
      case AnalysisFrequency.onDemand:
        return 'on_demand';
    }
  }

  static AnalysisFrequency fromStorageKey(String key) {
    switch (key) {
      case 'weekly':
        return AnalysisFrequency.weekly;
      case 'monthly':
        return AnalysisFrequency.monthly;
      case 'on_demand':
        return AnalysisFrequency.onDemand;
      case 'daily':
      default:
        return AnalysisFrequency.daily;
    }
  }
}

class AnalysisType {
  final String id;

  /// Nom affiché (ex: "BSW", "Salinité") : donnée venant de la base, pas une
  /// clé de traduction — les types d'analyse sont paramétrables par l'Admin.
  final String label;

  /// Unité affichée (voir `Units` : SI ou API selon les Réglages).
  final String unit;
  final double min;
  final double max;
  final AnalysisFrequency frequency;

  /// Unité enregistrée en base (toujours SI).
  final String storedUnit;

  /// Regroupement visuel (ex: "Tête de puits", "Séparateur de test") : les
  /// types qui partagent le même groupe sont affichés ensemble, par
  /// section, à la saisie comme dans l'historique — plutôt qu'en liste
  /// plate. Vide = pas de groupe (affiché seul, comme avant).
  final String group;

  const AnalysisType({
    required this.id,
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    required this.frequency,
    String? storedUnit,
    this.group = '',
  }) : storedUnit = storedUnit ?? unit;

  /// Nom et groupe traduits dans la langue courante (prédéfinis seulement).
  String get shownLabel => trData(label);
  String get shownGroup => trData(group);

  bool isOutOfRange(double value) => value < min || value > max;

  /// Nombre de jours de tolérance avant qu'une analyse manquante soit
  /// considérée "en retard" plutôt que simplement "à faire".
  int get graceDays {
    switch (frequency) {
      case AnalysisFrequency.daily:
        return 1;
      case AnalysisFrequency.weekly:
        return 7;
      case AnalysisFrequency.monthly:
        return 30;
      case AnalysisFrequency.onDemand:
        return 100000;
    }
  }

  /// Vrai si ce type d'analyse est attendu à la date [day] (milieu de nuit).
  bool isDueOn(DateTime day) {
    switch (frequency) {
      case AnalysisFrequency.daily:
        return true;
      case AnalysisFrequency.weekly:
        return day.weekday == DateTime.monday;
      case AnalysisFrequency.monthly:
        return day.day == 1;
      case AnalysisFrequency.onDemand:
        return false;
    }
  }
}
