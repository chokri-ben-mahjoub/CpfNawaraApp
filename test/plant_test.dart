import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:puitstrack/core/plant/plant_catalog.dart';
import 'package:puitstrack/core/plant/plant_repository.dart';
import 'package:puitstrack/features/plant/plant_report.dart';

SamplePoint _point(Map<String, Object> row) => SamplePoint(
  id: row['id']! as String,
  code: row['code']! as String,
  circuit: PlantCircuitX.fromKey(row['circuit']! as String),
  name: row['name']! as String,
  equipment: row['equipment']! as String,
  profile: row['profile']! as String,
);

PlantController seededPlant(DateTime today) {
  final points = [for (final row in plantSeedPoints) _point(Map<String, Object>.from(row))];
  return PlantController.seeded(
    PlantState(
      points: points,
      analyses: [
        PlantAnalysis(
          id: plantAnalysisId('pp_c1', today),
          pointId: 'pp_c1',
          date: today,
          values: const {'density': 735.0, 'bsw': 0.8, 'salinity': 12.0},
          source: 'plantSourceLab',
          operatorName: 'Ahmed',
          recordedAt: today,
        ),
        PlantAnalysis(
          id: plantAnalysisId('pp_w1', today),
          pointId: 'pp_w1',
          date: today,
          values: const {'ph': 6.8, 'appearance': 'plantAppearanceOily', 'tph': 12.0},
          source: 'plantSourceLab',
          operatorName: 'Ahmed',
          recordedAt: today,
        ),
        PlantAnalysis(
          id: plantAnalysisId('pp_g3', today),
          pointId: 'pp_g3',
          date: today,
          values: const {'ch4': 88.2, 'h2s': 2.0, 'water_dew_point': -12.0},
          source: 'plantSourceLab',
          operatorName: 'Ahmed',
          recordedAt: today,
        ),
      ],
      thresholds: const {
        'pp_c1': {'bsw': PlantThreshold(max: 0.5)},
        'pp_g3': {'h2s': PlantThreshold(max: 4), 'water_dew_point': PlantThreshold(max: -10)},
      },
    ),
  );
}

void main() {
  final today = DateTime(2026, 10, 9);
  setUpAll(() => initializeDateFormatting('fr'));

  test('catalogue : 13 points, paramètres par profil', () {
    expect(plantSeedPoints, hasLength(13));
    expect(paramsForProfile('condensate').map((p) => p.key), ['density', 'bsw', 'water_cut', 'salinity', 'chlorides']);
    expect(paramsForProfile('gas_export').map((p) => p.key), containsAll(['h2s', 'hc_dew_point', 'water_dew_point']));
    expect(paramsForProfile('gas').map((p) => p.key), isNot(contains('hc_dew_point')));
    expect(paramsForProfile('amine').map((p) => p.key), containsAll(['concentration', 'foam', 'pz', 'co2_loading']));
    expect(plantSeedPoints.map((p) => p['id']).toSet(), hasLength(13), reason: 'ids uniques');
  });

  test('état du jour : vert, rouge, gris', () {
    final plant = seededPlant(today);
    SamplePoint p(String id) => plant.point(id)!;
    expect(plant.status(p('pp_c1'), today), PlantStatus.outOfRange, reason: 'BSW 0,8 > 0,5');
    expect(plant.outOfRange(p('pp_c1'), plant.analysisOn('pp_c1', today)!).map((x) => x.key), ['bsw']);
    expect(plant.status(p('pp_w1'), today), PlantStatus.outOfRange, reason: 'aspect huileux');
    expect(plant.status(p('pp_g3'), today), PlantStatus.ok, reason: 'H2S et point de rosée conformes');
    expect(plant.status(p('pp_c2'), today), PlantStatus.missing);
    expect(plant.status(p('pp_c1'), today.add(const Duration(days: 1))), PlantStatus.missing);
    // Sans seuil défini, une valeur n'est jamais signalée.
    final density = paramsForProfile('condensate').first;
    expect(plant.isOut('pp_c1', density, 735.0), isNull);
  });

  test('une analyse par point et par jour (identifiant naturel)', () {
    expect(plantAnalysisId('pp_c1', DateTime(2026, 1, 5, 14, 30)), 'pp_c1_2026-01-05');
  });

  test('rapport PDF journalier', () async {
    final plant = seededPlant(today);
    final bytes = await buildPlantDailyReport(
      controller: plant,
      day: today,
      circuits: PlantCircuit.values,
      s: (key) => key,
      languageCode: 'fr',
      operatorName: 'Ahmed',
    );
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });
}
