import '../export/pdf_chart.dart';
import 'plant_catalog.dart';
import 'plant_repository.dart';

/// Une courbe par paramètre numérique de [point] (historique complet, trié
/// par date) — pour l'export PDF d'un seul point (`plant_point_screen.dart`).
/// Ignore les paramètres sans au moins deux valeurs saisies (rien à tracer).
List<PdfReportChart> plantPointCharts(
  PlantController controller,
  SamplePoint point,
  String Function(String) s, {
  Set<String>? keys,
}) {
  final history = controller.analysesFor(point.id).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final numericParams = point.params
      .where((p) => p.isNumeric && (keys == null || keys.contains(p.key)))
      .toList();

  return [
    for (var i = 0; i < numericParams.length; i++)
      PdfReportChart(
        title: numericParams[i].unit.isEmpty
            ? s(numericParams[i].labelKey)
            : '${s(numericParams[i].labelKey)} (${numericParams[i].unit})',
        series: [
          PdfChartSeries(
            label: s(numericParams[i].labelKey),
            color: pdfChartPalette[i % pdfChartPalette.length],
            points: [
              for (final a in history)
                if (a.number(numericParams[i].key) != null)
                  (a.date, a.number(numericParams[i].key)!),
            ],
          ),
        ],
      ),
  ];
}

/// Une courbe par paramètre numérique ayant au moins une valeur dans
/// [circuit], chacune superposant tous les points du circuit qui en ont une
/// — même principe que l'onglet « Courbes » (`plant_trends_view.dart`), pour
/// le rapport journalier (`plant_report.dart`). Un point sans valeur pour ce
/// paramètre n'apparaît simplement pas (pas de ligne plate à zéro).
List<PdfReportChart> plantCircuitCharts(
  PlantController controller,
  PlantCircuit circuit,
  String Function(String) s,
) {
  final points = controller.pointsOf(circuit);
  if (points.isEmpty) return const [];

  final params = <String, PlantParam>{};
  for (final p in points) {
    for (final param in p.params.where((x) => x.isNumeric)) {
      if (!params.containsKey(param.key) &&
          controller.series(p.id, param.key).isNotEmpty) {
        params[param.key] = param;
      }
    }
  }

  final charts = <PdfReportChart>[];
  for (final param in params.values) {
    final series = <PdfChartSeries>[];
    for (final p in points) {
      if (!p.params.any((x) => x.key == param.key)) continue;
      final data = controller.series(p.id, param.key);
      if (data.isEmpty) continue;
      series.add(
        PdfChartSeries(
          label: p.code,
          color: pdfChartPalette[series.length % pdfChartPalette.length],
          points: data,
        ),
      );
    }
    if (series.isEmpty) continue;
    charts.add(
      PdfReportChart(
        title: param.unit.isEmpty
            ? s(param.labelKey)
            : '${s(param.labelKey)} (${param.unit})',
        series: series,
      ),
    );
  }
  return charts;
}
