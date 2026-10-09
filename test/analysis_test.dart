import 'dart:convert';
import 'dart:math' as math;

import 'package:puitstrack/core/analysis/decline.dart';
import 'package:puitstrack/core/analysis/production_metrics.dart';
import 'package:puitstrack/core/analysis/series.dart';
import 'package:puitstrack/core/export/csv_exporter.dart';
import 'package:puitstrack/core/export/excel_exporter.dart';
import 'package:puitstrack/core/export/export_table.dart';
import 'package:puitstrack/core/filters/well_filter.dart';
import 'package:puitstrack/core/models/analysis_record.dart';
import 'package:puitstrack/core/models/production_types.dart';
import 'package:puitstrack/core/models/well.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

AnalysisRecord _rec(String typeId, double value, DateTime at) => AnalysisRecord(
      id: '${typeId}_${at.toIso8601String()}',
      wellId: 'w1',
      typeId: typeId,
      value: value,
      serviceKey: 'serviceProduction',
      operatorName: 'Test',
      dateTime: at,
    );

void main() {
  group('Déclin exponentiel', () {
    test('retrouve D et qi sur une série exacte', () {
      const qi = 120.0;
      const d = 0.002; // par jour
      final t0 = DateTime(2026, 1, 1);
      final points = [
        for (var i = 0; i < 60; i += 3) SeriesPoint(t0.add(Duration(days: i)), qi * math.exp(-d * i)),
      ];
      final fit = fitExponentialDecline(points)!;
      expect(fit.dailyRate, closeTo(d, 1e-9));
      expect(fit.qi, closeTo(qi, 1e-6));
      expect(fit.r2, closeTo(1, 1e-9));
      expect(fit.isDeclining, isTrue);
      // Déclin effectif annuel = 1 − e^(−0,002 × 365,25) ≈ 51,8 %
      expect(fit.effectiveAnnualPct, closeTo((1 - math.exp(-d * 365.25)) * 100, 1e-9));
      expect(fit.nominalAnnualPct, closeTo(d * 365.25 * 100, 1e-9));
      // Cumul sur 30 jours = qi/D (1 − e^(−30D))
      expect(fit.cumulativeBetween(t0, t0.add(const Duration(days: 30))), closeTo(qi / d * (1 - math.exp(-30 * d)), 1e-6));
      // Temps pour passer de 120 à 60 = ln 2 / D
      expect(fit.daysUntilRate(60, t0), closeTo(math.log(2) / d, 1e-6));
    });

    test('production en hausse : D négatif, pas de date limite', () {
      final t0 = DateTime(2026, 1, 1);
      final points = [for (var i = 0; i < 5; i++) SeriesPoint(t0.add(Duration(days: i)), 50.0 + i * 5)];
      final fit = fitExponentialDecline(points)!;
      expect(fit.isDeclining, isFalse);
      expect(fit.daysUntilRate(10, t0), isNull);
    });

    test('pas assez de points → null', () {
      final t0 = DateTime(2026, 1, 1);
      expect(fitExponentialDecline([SeriesPoint(t0, 10), SeriesPoint(t0.add(const Duration(days: 1)), 9)]), isNull);
      // 3 points le même jour : pas de durée exploitable.
      expect(
        fitExponentialDecline([SeriesPoint(t0, 10), SeriesPoint(t0, 9), SeriesPoint(t0, 8)]),
        isNull,
      );
      // Les débits nuls sont ignorés.
      expect(
        fitExponentialDecline([
          SeriesPoint(t0, 0),
          SeriesPoint(t0.add(const Duration(days: 1)), 10),
          SeriesPoint(t0.add(const Duration(days: 2)), 9),
        ]),
        isNull,
      );
    });

    test('mode auto : repart après la dernière intervention', () {
      final t0 = DateTime(2026, 1, 1);
      final rates = [for (var i = 0; i < 20; i++) SeriesPoint(t0.add(Duration(days: i)), 100.0 - i)];
      final result = analyzeDecline(
        rates,
        window: DeclineWindow.auto,
        lastInterventionDate: t0.add(const Duration(days: 10)),
        now: t0.add(const Duration(days: 20)),
      );
      expect(result.sinceIntervention, isTrue);
      expect(result.used.first.t, t0.add(const Duration(days: 11)));
      expect(result.used.length, 9);

      // Intervention trop récente (moins de 3 points après) → tout l'historique.
      final recent = analyzeDecline(
        rates,
        window: DeclineWindow.auto,
        lastInterventionDate: t0.add(const Duration(days: 18)),
        now: t0.add(const Duration(days: 20)),
      );
      expect(recent.sinceIntervention, isFalse);
      expect(recent.used.length, 20);
    });
  });

  group('Ratios de production', () {
    final day1 = DateTime(2026, 3, 1, 8);
    final day2 = DateTime(2026, 3, 2, 8);
    final records = [
      _rec(oilFlowTypeId, 100, day1),
      _rec(gasFlowTypeId, 15000, day1),
      _rec(waterFlowTypeId, 25, day1),
      // Jour 2 : huile saisie deux fois, la dernière saisie du jour compte.
      _rec(oilFlowTypeId, 90, day2),
      _rec(oilFlowTypeId, 80, day2.add(const Duration(hours: 2))),
      _rec(gasFlowTypeId, 16000, day2),
      // Pwf mesurée le jour 2, pas d'eau ce jour-là → eau du jour 1 reprise.
      _rec(bottomHolePressureTypeId, 150, day2),
    ];

    test('GOR / WOR / GLR', () {
      final m = ProductionMetrics.fromRecords(records, reservoirPressure: 200);
      final gor = m.series(DerivedRatio.gor);
      expect(gor.map((p) => p.v), [150, 200]);
      final wor = m.series(DerivedRatio.wor);
      expect(wor.single.v, 0.25); // seul le jour 1 a de l'eau
      final glr = m.series(DerivedRatio.glr);
      expect(glr.single.v, closeTo(15000 / 125, 1e-9));
    });

    test('PI = liquide / (Pr − Pwf), débits repris jusqu\'à 3 jours', () {
      final m = ProductionMetrics.fromRecords(records, reservoirPressure: 200);
      final pi = m.series(DerivedRatio.pi).single;
      expect(pi.v, closeTo((80 + 25) / (200 - 150), 1e-9));
    });

    test('PI indisponible sans Pr ou si Pwf ≥ Pr', () {
      expect(ProductionMetrics.fromRecords(records).series(DerivedRatio.pi), isEmpty);
      expect(ProductionMetrics.fromRecords(records, reservoirPressure: 140).series(DerivedRatio.pi), isEmpty);
    });

    test('unités déduites des débits', () {
      expect(ratioUnit(DerivedRatio.gor), 'Sm³/m³');
      expect(ratioUnit(DerivedRatio.wor), 'm³/m³');
      expect(ratioUnit(DerivedRatio.pi), 'm³/j/bar');
    });
  });

  group('Statistiques de comparaison', () {
    test('moyenne, min, max, première, dernière', () {
      final t0 = DateTime(2026, 1, 1);
      final stats = SeriesStats.of([
        SeriesPoint(t0.add(const Duration(days: 2)), 30),
        SeriesPoint(t0, 10),
        SeriesPoint(t0.add(const Duration(days: 1)), 20),
      ])!;
      expect(stats.count, 3);
      expect(stats.mean, 20);
      expect(stats.min, 10);
      expect(stats.max, 30);
      expect(stats.first, 10);
      expect(stats.last, 30);
      expect(percentChange(10, 12), closeTo(20, 1e-9));
      expect(percentChange(0, 12), isNull);
    });
  });

  group('Filtres', () {
    const nord = Well(id: '1', code: 'PN-01', name: 'Puits Nord 1', active: true, group: 'Zone Nord');
    const sud = Well(id: '2', code: 'PS-02', name: 'Puits Sud 2', active: false, group: 'Zone Sud');
    const libre = Well(id: '3', code: 'X-1', name: 'Isolé', active: true);

    test('champ, statut, recherche', () {
      expect(const WellFilter(group: 'Zone Nord').matches(nord), isTrue);
      expect(const WellFilter(group: 'Zone Nord').matches(sud), isFalse);
      expect(const WellFilter(group: '').matches(libre), isTrue);
      expect(const WellFilter(status: WellStatusFilter.stopped).matches(sud), isTrue);
      expect(const WellFilter(status: WellStatusFilter.stopped).matches(nord), isFalse);
      expect(const WellFilter(query: 'ps-0').matches(sud), isTrue);
      expect(const WellFilter(query: 'nord').matches(sud), isFalse);
    });

    test('période : jours entiers inclus', () {
      final now = DateTime(2026, 10, 9, 15);
      const p = PeriodSelection.days7;
      expect(p.contains(DateTime(2026, 10, 3, 0, 1), now), isTrue);
      expect(p.contains(DateTime(2026, 10, 2, 23, 59), now), isFalse);
      expect(p.contains(DateTime(2026, 10, 9, 23, 59), now), isTrue);
    });
  });

  group('Export', () {
    const table = ExportTable(
      name: 'Analyses',
      headers: ['Date', 'Valeur', 'Commentaire'],
      rows: [
        ['x', 1.5, 'a;b'],
        ['y', 2.0, null],
      ],
    );

    test('CSV : séparateur ;, virgule décimale, BOM, échappement', () {
      final bytes = CsvExporter.encode(ExportTable(
        name: table.name,
        headers: table.headers,
        rows: [
          [DateOnly(DateTime(2026, 10, 9)), 1.5, 'a;b'],
          [DateTime(2026, 10, 9, 14, 5), 2.0, null],
        ],
      ));
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      final text = utf8.decode(bytes.skip(3).toList());
      expect(text.split('\n')[0].trim(), 'Date;Valeur;Commentaire');
      expect(text.split('\n')[1].trim(), '09/10/2026;1,5;"a;b"');
      expect(text.split('\n')[2].trim(), '09/10/2026 14:05;2;');
    });

    test('Excel : une feuille par tableau, nombres en vraies valeurs', () {
      final bytes = ExcelExporter.encode([
        table,
        const ExportTable(name: 'Production et ratios', headers: ['GOR'], rows: [
          [150.25],
        ]),
      ])!;
      final book = Excel.decodeBytes(bytes);
      expect(book.tables.keys, containsAll(['Analyses', 'Production et ratios']));
      final cell = book.tables['Analyses']!.rows[1][1]!.value;
      expect(cell, isA<DoubleCellValue>());
      expect((cell as DoubleCellValue).value, 1.5);
      expect(book.tables['Analyses']!.rows[1][2]!.value.toString(), 'a;b');
    });
  });
}
