import '../export/pdf_chart.dart';
import 'plant_repository.dart';

/// Une courbe par paramètre numérique de [point] (historique complet, trié
/// par date) — partagée entre l'export PDF du point (`plant_point_screen.dart`)
/// et le rapport journalier (`plant_report.dart`). Ignore les paramètres sans
/// au moins deux valeurs saisies (rien à tracer).
List<PdfReportChart> plantPointCharts(PlantController controller, SamplePoint point, String Function(String) s) {
  final history = controller.analysesFor(point.id).toList()..sort((a, b) => a.date.compareTo(b.date));
  final numericParams = point.params.where((p) => p.isNumeric).toList();

  return [
    for (var i = 0; i < numericParams.length; i++)
      PdfReportChart(
        title: numericParams[i].unit.isEmpty ? s(numericParams[i].labelKey) : '${s(numericParams[i].labelKey)} (${numericParams[i].unit})',
        series: [
          PdfChartSeries(
            label: s(numericParams[i].labelKey),
            color: pdfChartPalette[i % pdfChartPalette.length],
            points: [
              for (final a in history)
                if (a.number(numericParams[i].key) != null) (a.date, a.number(numericParams[i].key)!),
            ],
          ),
        ],
      ),
  ];
}
