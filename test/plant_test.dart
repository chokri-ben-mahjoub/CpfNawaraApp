import 'dart:convert';

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:puitstrack/core/plant/plant_catalog.dart';
import 'package:puitstrack/core/plant/plant_repository.dart';
import 'package:puitstrack/features/plant/plant_report.dart';

final _circuitsById = {
  for (final row in plantSeedCircuits)
    row['id']! as String: PlantCircuit(
      id: row['id']! as String,
      labelKey: row['label_key']! as String,
      colorValue: row['color']! as int,
      iconKey: row['icon']! as String,
      defaultProfile: row['default_profile']! as String,
      sortOrder: row['sort_order']! as int,
    ),
};

SamplePoint _point(Map<String, Object> row) => SamplePoint(
  id: row['id']! as String,
  code: row['code']! as String,
  circuit: _circuitsById[row['circuit']! as String]!,
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
      circuits: _circuitsById.values.toList(),
    ),
  );
}

void main() {
  final today = DateTime(2026, 10, 9);
  setUpAll(() => initializeDateFormatting('fr'));

  test('catalogue : 20 points, paramètres par profil', () {
    expect(plantSeedPoints, hasLength(20));
    expect(paramsForProfile('condensate').map((p) => p.key), ['density', 'bsw', 'water_cut', 'salinity', 'chlorides']);
    expect(paramsForProfile('gas_export').map((p) => p.key), containsAll(['h2s', 'hc_dew_point', 'water_dew_point']));
    expect(paramsForProfile('gas').map((p) => p.key), isNot(contains('hc_dew_point')));
    expect(paramsForProfile('amine').map((p) => p.key), containsAll(['concentration', 'foam', 'pz', 'co2_loading']));
    expect(paramsForProfile('water_treatment').map((p) => p.key), containsAll(['free_chlorine', 'ph', 'tds']));
    expect(plantSeedPoints.map((p) => p['id']).toSet(), hasLength(20), reason: 'ids uniques');
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

  test('variation : hausse, baisse, stable par rapport à l\'analyse précédente', () {
    PlantAnalysis a(DateTime d, double bsw) => PlantAnalysis(
      id: plantAnalysisId('pp_c1', d),
      pointId: 'pp_c1',
      date: d,
      values: {'bsw': bsw},
      source: 'plantSourceLab',
      operatorName: '',
      recordedAt: d,
    );
    final d1 = today.subtract(const Duration(days: 2));
    final d2 = today.subtract(const Duration(days: 1));
    final controller = PlantController.seeded(
      PlantState(
        points: seededPlant(today).state.points,
        analyses: [a(today, 0.6), a(d2, 0.5), a(d1, 0.505)],
        thresholds: const {},
      ),
    );
    final last = controller.variation('pp_c1', 'bsw')!;
    expect(last.previous, 0.5);
    expect(last.value, 0.6);
    expect(last.percent, closeTo(20, 1e-9));
    expect(last.direction, 1);
    final before = controller.variation('pp_c1', 'bsw', at: d2)!;
    expect(before.direction, 0, reason: '-1 % : stable');
    expect(controller.variation('pp_c1', 'bsw', at: d1), isNull, reason: 'pas d\'analyse précédente');
    expect(controller.variation('pp_c1', 'density'), isNull);
  });

  test('schémas : positions par défaut, déplacées, retirées', () {
    final c1 = seededPlant(today).point('pp_c1')!;
    final pfd = PlantSchema.builtIn;
    expect(pfd.positionOf(c1), const Offset(376 / 1000, 180 / 560));
    expect(pfd.copyWith(positions: {'pp_c1': const Offset(0.1, 0.2)}).positionOf(c1), const Offset(0.1, 0.2));
    expect(pfd.copyWith(positions: {'pp_c1': null}).positionOf(c1), isNull);
    final blank = PlantSchema(id: 'x', name: 'x', kind: PlantSchemaKind.blank);
    expect(blank.positionOf(c1), isNull, reason: 'rien de placé par défaut');
    final image = PlantSchema(id: 'i', name: 'i', kind: PlantSchemaKind.image, imageWidth: 2000, imageHeight: 1000);
    expect(image.canvasSize, const Size(1000, 500));
    expect(const PlantState(points: [], analyses: [], thresholds: {}).visibleSchemas.single.id, 'pfd');
  });

  test('paramètres personnalisés et modèles modifiés', () {
    addTearDown(() {
      PlantCustomCatalog.params = const {};
      PlantCustomCatalog.profiles = const {};
    });
    final turbidity = customPlantParam(key: 'cp_turb', label: 'Turbidité', unit: 'NTU');
    final aspect = customPlantParam(
      key: 'cp_asp',
      label: 'Couleur',
      unit: '',
      kind: ParamKind.choice,
      choices: const ['Claire', 'Jaune', 'Noire'],
      okChoices: const ['Claire'],
    );
    PlantCustomCatalog.params = {turbidity.key: turbidity, aspect.key: aspect};
    PlantCustomCatalog.profiles = {
      // Modèle intégré modifié : pH retiré, turbidité ajoutée.
      'water': const PlantProfileDef(id: 'water', label: 'plantProfileWater', paramKeys: ['density', 'cp_turb']),
      'pm_cool': const PlantProfileDef(id: 'pm_cool', label: 'Eau de refroidissement', paramKeys: ['ph', 'cp_asp']),
    };
    expect(paramsForProfile('water').map((p) => p.key), ['density', 'cp_turb']);
    expect(paramsForProfile('water').first.fixedUnit, isTrue, reason: 'densité de l\'eau : variante du modèle');
    expect(paramsForProfile('condensate').map((p) => p.key), contains('bsw'), reason: 'modèle intact');
    expect(plantProfileLabelKeys['pm_cool'], 'Eau de refroidissement');
    expect(plantProfileLabelKeys.keys.last, 'pm_cool');
    expect(plantParamCatalog.map((p) => p.key), containsAll(['cp_turb', 'cp_asp', 'bsw']));
    expect(plantParamByKey('cp_turb')!.unit, 'NTU');
    final turb = plantParamByKey('cp_turb')!;
    expect(turb.displayed(), same(turb), reason: 'unité libre, jamais convertie');
    expect(turb.toSi(12), 12);

    final point = SamplePoint(
      id: 'p',
      code: 'CW1',
      circuit: _circuitsById['water']!,
      name: 'Refroidissement',
      equipment: '',
      profile: 'pm_cool',
    );
    final controller = PlantController.seeded(
      PlantState(
        points: [point],
        analyses: [
          PlantAnalysis(
            id: plantAnalysisId('p', today),
            pointId: 'p',
            date: today,
            values: const {'ph': 7.0, 'cp_asp': 'Noire'},
            source: 'plantSourceLab',
            operatorName: '',
            recordedAt: today,
          ),
        ],
        thresholds: const {},
      ),
    );
    expect(point.params.map((p) => p.key), ['ph', 'cp_asp']);
    expect(controller.status(point, today), PlantStatus.outOfRange, reason: 'choix non conforme');
  });

  test('une analyse par point et par jour (identifiant naturel)', () {
    expect(plantAnalysisId('pp_c1', DateTime(2026, 1, 5, 14, 30)), 'pp_c1_2026-01-05');
  });

  test('rapport PDF journalier', () async {
    final plant = seededPlant(today);
    final bytes = await buildPlantDailyReport(
      controller: plant,
      day: today,
      circuits: _circuitsById.values.toList(),
      s: (key) => key,
      languageCode: 'fr',
      operatorName: 'Ahmed',
    );
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });
}
