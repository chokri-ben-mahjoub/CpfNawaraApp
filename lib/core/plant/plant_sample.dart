import 'plant_catalog.dart';
import 'plant_repository.dart';

/// Données d'exemple (catalogue intégré + quelques analyses du jour) pour
/// l'aperçu des rapports PDF de l'usine : aucune donnée réelle n'est lue.
({PlantController controller, List<PlantCircuit> circuits}) samplePlantForPreview(DateTime day) {
  final circuits = [
    for (final row in plantSeedCircuits)
      PlantCircuit(
        id: row['id']! as String,
        labelKey: row['label_key']! as String,
        colorValue: row['color']! as int,
        iconKey: row['icon']! as String,
        defaultProfile: row['default_profile']! as String,
        sortOrder: row['sort_order']! as int,
      ),
  ];
  final byId = {for (final c in circuits) c.id: c};
  final points = [
    for (final row in plantSeedPoints)
      SamplePoint(
        id: row['id']! as String,
        code: row['code']! as String,
        circuit: byId[row['circuit']! as String]!,
        name: row['name']! as String,
        equipment: row['equipment']! as String,
        profile: row['profile']! as String,
      ),
  ];
  PlantAnalysis analysis(String pointId, Map<String, Object?> values, {String? comment, Map<String, String> notes = const {}}) =>
      PlantAnalysis(
        id: plantAnalysisId(pointId, day),
        pointId: pointId,
        date: day,
        values: values,
        source: 'plantSourceLab',
        operatorName: 'Opérateur',
        comment: comment,
        recordedAt: day,
        paramComments: notes,
      );
  final controller = PlantController.preview(
    PlantState(
      points: points,
      analyses: [
        analysis('pp_c1', const {'density': 735.0, 'bsw': 0.8, 'salinity': 12.0}, notes: const {'bsw': 'Contrôle en cours'}),
        analysis('pp_w1', const {'ph': 6.8, 'appearance': 'plantAppearanceOily', 'tph': 12.0}, comment: 'Exemple de commentaire'),
        analysis('pp_g3', const {'ch4': 88.2, 'h2s': 2.0, 'water_dew_point': -12.0}),
      ],
      thresholds: const {
        'pp_c1': {'bsw': PlantThreshold(max: 0.5)},
        'pp_g3': {'h2s': PlantThreshold(max: 4), 'water_dew_point': PlantThreshold(max: -10)},
      },
      circuits: circuits,
    ),
  );
  return (controller: controller, circuits: circuits);
}
