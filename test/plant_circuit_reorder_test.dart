// Glisser-déposer des puces de circuits : maintenir une puce puis la déposer
// sur une autre enregistre le nouvel ordre (repris par le rapport PDF).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/l10n/app_strings.dart';
import 'package:puitstrack/core/plant/plant_catalog.dart';
import 'package:puitstrack/core/plant/plant_repository.dart';
import 'package:puitstrack/features/plant/presentation/plant_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plant_test.dart' show seededPlant;

class _RecordingPlant extends PlantController {
  List<String>? saved;
  _RecordingPlant(PlantState s) : super.seeded(s);

  @override
  Future<void> reorderCircuits(List<String> orderedIds) async => saved = orderedIds;
}

void main() {
  testWidgets('glisser une puce sur une autre enregistre le nouvel ordre', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final circuits = seededPlant(DateTime(2026, 10, 25)).state.circuits.take(4).toList();
    final plant = _RecordingPlant(PlantState(points: const [], analyses: const [], thresholds: const {}, circuits: circuits));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [plantControllerProvider.overrideWith((ref) => plant)],
        child: MaterialApp(home: Scaffold(body: PlantCircuitChips(circuits: circuits))),
      ),
    );
    await tester.pump();
    final label = (PlantCircuit c) => tr(const Locale('fr'), c.labelKey);
    final first = find.text(label(circuits[0]));
    final third = find.text(label(circuits[2]));
    expect(first, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(const Duration(milliseconds: 400)); // appui long
    await gesture.moveTo(tester.getCenter(third));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Le 1er circuit est déposé à la place du 3e.
    expect(plant.saved, [circuits[1].id, circuits[2].id, circuits[0].id, circuits[3].id]);
  });

  testWidgets('un simple appui sélectionne la puce sans réordonner', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final circuits = seededPlant(DateTime(2026, 10, 25)).state.circuits.take(3).toList();
    final plant = _RecordingPlant(PlantState(points: const [], analyses: const [], thresholds: const {}, circuits: circuits));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [plantControllerProvider.overrideWith((ref) => plant)],
        child: MaterialApp(home: Scaffold(body: PlantCircuitChips(circuits: circuits))),
      ),
    );
    await tester.pump();
    await tester.tap(find.text(tr(const Locale('fr'), circuits[1].labelKey)));
    await tester.pumpAndSettle();
    expect(plant.saved, isNull);
  });

  testWidgets('bouton « Ordre » : les flèches de la feuille déplacent un circuit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final circuits = seededPlant(DateTime(2026, 10, 25)).state.circuits.take(3).toList();
    final plant = _RecordingPlant(PlantState(points: const [], analyses: const [], thresholds: const {}, circuits: circuits));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [plantControllerProvider.overrideWith((ref) => plant)],
        child: MaterialApp(home: Scaffold(body: PlantCircuitChips(circuits: circuits))),
      ),
    );
    await tester.pump();
    await tester.tap(find.text(tr(const Locale('fr'), 'plantCircuitsReorder')));
    await tester.pumpAndSettle();
    expect(find.text(tr(const Locale('fr'), 'plantCircuitsReorderTitle')), findsOneWidget);
    // Flèche « bas » du 1er circuit.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
    await tester.pumpAndSettle();
    expect(plant.saved, [circuits[1].id, circuits[0].id, circuits[2].id]);
  });
}
