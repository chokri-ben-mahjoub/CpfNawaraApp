/// Types d'intervention proposés (clés de traduction, voir `app_strings.dart`).
/// Stockés tels quels en base : ne pas renommer une clé existante.
const interventionTypeKeys = [
  'interventionTypeWorkover',
  'interventionTypeStimulation',
  'interventionTypeFracturing',
  'interventionTypeChokeChange',
  'interventionTypeCleanout',
  'interventionTypeWireline',
  'interventionTypePerforation',
  'interventionTypeArtificialLift',
  'interventionTypeShutIn',
  'interventionTypeOther',
];

/// Résultat d'une intervention (clé de traduction stockée en base).
const interventionResultKeys = [
  'interventionResultSuccess',
  'interventionResultPartial',
  'interventionResultFailure',
  'interventionResultPending',
];

const interventionCurrencies = ['TND', 'USD', 'EUR'];

/// Une intervention sur un puits (workover, stimulation, changement de
/// duse...) : affichée en marqueur sur les courbes, et point de bascule de la
/// comparaison avant/après et de la courbe de déclin.
class Intervention {
  final String id;
  final String wellId;

  /// Jour de l'intervention (minuit, heure locale).
  final DateTime date;
  final String typeKey;
  final double? cost;
  final String currency;
  final String resultKey;
  final String? description;
  final String operatorName;

  const Intervention({
    required this.id,
    required this.wellId,
    required this.date,
    required this.typeKey,
    this.cost,
    this.currency = 'TND',
    required this.resultKey,
    this.description,
    required this.operatorName,
  });
}
