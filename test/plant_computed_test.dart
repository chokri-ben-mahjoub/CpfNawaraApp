import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/plant/plant_catalog.dart';

void main() {
  customPointTests();
  test('pertes d\'hydrocarbures : exemple 386,6 m³/j, TPH 4 100 mg/L, densité 745,5', () {
    final r = plantComputedValues({'water_flow': 386.6, 'tph': 4100, 'cond_density': 745.5});
    expect(r['hc_mass'], closeTo(1585.06, 1e-6)); // kg/j
    expect(r['hc_mass_t'], closeTo(1.58506, 1e-9)); // = (386,6 × 4100) / 1 000 000
    expect(r['hc_volume'], closeTo(2126.1, 0.1)); // L/j = kg ÷ densité × 1000
  });

  test('valeurs manquantes : pas de résultat partiel trompeur', () {
    expect(plantComputedValues({'tph': 4100}), isEmpty);
    expect(plantComputedValues({'water_flow': 10}), isEmpty);
    final noDensity = plantComputedValues({'water_flow': 10, 'tph': 100});
    expect(noDensity.containsKey('hc_volume'), isFalse);
    expect(noDensity['hc_mass'], 1);
    expect(plantComputedValues({'water_flow': 10, 'tph': 100, 'cond_density': 0}).containsKey('hc_volume'), isFalse);
  });

  test('le modèle « eau » porte les entrées et les résultats calculés', () {
    final keys = {for (final p in builtInPlantProfiles['water']!) p.key: p};
    expect(keys['water_flow']!.computed, isFalse);
    expect(keys['cond_density']!.computed, isFalse);
    for (final k in ['hc_mass', 'hc_mass_t', 'hc_volume']) {
      expect(keys[k]!.computed, isTrue);
    }
  });
}

void customPointTests() {
  test('un point à paramètres personnalisés qui mesure le TPH reçoit le calcul', () {
    const custom = [PlantParam('ph', 'plantParamPh', ''), PlantParam('tph', 'plantParamTph', 'mg/L')];
    final withCalc = withHydrocarbonCalc(custom);
    expect(withCalc.map((p) => p.key), containsAll(hydrocarbonCalcKeys));
    expect(withCalc.where((p) => p.computed).map((p) => p.key), ['hc_mass', 'hc_mass_t', 'hc_volume']);
    // Sans TPH : rien n'est ajouté ; déjà présent : pas de doublon.
    expect(withHydrocarbonCalc(const [PlantParam('ph', 'plantParamPh', '')]).length, 1);
    expect(withHydrocarbonCalc(withCalc).length, withCalc.length);
  });
}
