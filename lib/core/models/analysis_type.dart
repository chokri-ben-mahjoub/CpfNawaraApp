enum AnalysisFrequency { daily, weekly, monthly }

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
    }
  }

  static AnalysisFrequency fromStorageKey(String key) {
    switch (key) {
      case 'weekly':
        return AnalysisFrequency.weekly;
      case 'monthly':
        return AnalysisFrequency.monthly;
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
  final String unit;
  final double min;
  final double max;
  final AnalysisFrequency frequency;

  const AnalysisType({
    required this.id,
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    required this.frequency,
  });

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
    }
  }
}
