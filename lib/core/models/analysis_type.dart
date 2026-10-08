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
}

class AnalysisType {
  final String id;

  /// Clé de traduction (voir `app_strings.dart`), ex: `analysisBsw`.
  final String labelKey;
  final String unit;
  final double min;
  final double max;
  final AnalysisFrequency frequency;

  const AnalysisType({
    required this.id,
    required this.labelKey,
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
