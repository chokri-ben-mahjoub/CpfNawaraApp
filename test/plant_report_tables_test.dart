import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/l10n/app_strings.dart';
import 'package:puitstrack/core/export/export_table.dart';
import 'package:puitstrack/features/plant/plant_report.dart';

import 'plant_test.dart' show seededPlant;

void main() {
  final today = DateTime(2026, 10, 25);
  String s(String k) => tr(const Locale('fr'), k);

  test('rapport usine en tableaux (Excel / CSV) : une feuille par circuit, une ligne par analyse', () {
    final plant = seededPlant(today);
    final tables = plantReportTables(controller: plant, day: today, circuits: plant.state.circuits, s: s);
    expect(tables, isNotEmpty);
    // Les circuits sans analyse ce jour-là n'ont pas de feuille.
    expect(tables.every((t) => t.rows.isNotEmpty), isTrue);
    final condensate = tables.first;
    expect(condensate.headers, containsAll([s('colDate'), s('plantSamplingTime'), s('plantColPoint')]));
    // Chaque ligne a autant de cellules que de colonnes.
    for (final t in tables) {
      for (final row in t.rows) {
        expect(row.length, t.headers.length);
      }
    }
    expect(condensate.rows.first.first, isA<DateOnly>());
  });

  test('filtres : un point et des paramètres choisis', () {
    final plant = seededPlant(today);
    final tables = plantReportTables(
      controller: plant,
      day: today,
      circuits: plant.state.circuits,
      s: s,
      onlyPointId: 'pp_c1',
      paramKeys: {'bsw'},
    );
    expect(tables, hasLength(1));
    final t = tables.single;
    expect(t.rows, hasLength(1));
    expect(t.headers.where((h) => h.contains('%')).length, 1, reason: 'une seule colonne de paramètre (BSW)');
    expect(t.rows.single, contains(0.8));
  });
}
