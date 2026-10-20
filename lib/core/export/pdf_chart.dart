import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _navy = PdfColor.fromInt(0xFF0B1E2D);
const _grey = PdfColor.fromInt(0xFF757575);

/// Une courbe (une série de points datés) à dessiner dans un rapport PDF —
/// même principe que les graphiques de l'app (`ProductionChart`,
/// `TrendChart`), mais rendus avec l'API de graphiques du paquet `pdf`.
class PdfChartSeries {
  final String label;
  final PdfColor color;
  final List<(DateTime, double)> points;
  const PdfChartSeries({required this.label, required this.color, required this.points});
}

/// Une section "courbe" d'un export PDF : titre + une ou plusieurs séries
/// partageant le même axe temporel (ex: une courbe par type d'analyse, ou
/// plusieurs débits superposés).
class PdfReportChart {
  final String title;
  final List<PdfChartSeries> series;
  const PdfReportChart({required this.title, required this.series});
}

/// Couleurs appliquées aux séries dans l'ordre, pour les appels qui n'ont pas
/// de couleur métier précise (ex: une courbe par type d'analyse).
const pdfChartPalette = [
  PdfColor.fromInt(0xFFFF7A33),
  PdfColor.fromInt(0xFF1E88E5),
  PdfColor.fromInt(0xFF43A047),
  PdfColor.fromInt(0xFF8E24AA),
  PdfColor.fromInt(0xFFC62828),
  PdfColor.fromInt(0xFF00897B),
];

/// Construit la section complète (titre + courbe + légende) d'un
/// [PdfReportChart], ou un widget vide si moins de 2 points au total.
pw.Widget buildPdfChartSection(PdfReportChart chart, {double height = 170}) {
  final nonEmpty = chart.series.where((s) => s.points.length >= 2).toList();
  if (nonEmpty.isEmpty) return pw.SizedBox();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(chart.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: _navy)),
      pw.SizedBox(height: 6),
      _buildChart(nonEmpty, height: height),
    ],
  );
}

pw.Widget _buildChart(List<PdfChartSeries> series, {required double height}) {
  final allPoints = [for (final s in series) ...s.points];
  final xs = allPoints.map((p) => p.$1.millisecondsSinceEpoch.toDouble());
  final minX = xs.reduce((a, b) => a < b ? a : b);
  final maxXRaw = xs.reduce((a, b) => a > b ? a : b);
  final maxX = maxXRaw <= minX ? minX + 1 : maxXRaw;
  final ys = allPoints.map((p) => p.$2);
  final maxYRaw = ys.reduce((a, b) => a > b ? a : b) * 1.15;
  final maxY = maxYRaw <= 0 ? 1.0 : maxYRaw;
  final spanDays = (maxX - minX) / (1000 * 60 * 60 * 24);
  final dateFormat = DateFormat(spanDays > 400 ? 'MM/yyyy' : 'dd/MM');

  return pw.SizedBox(
    height: height,
    child: pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis<double>(
          [minX, maxX],
          divisions: true,
          divisionsColor: PdfColors.grey300,
          format: (v) => dateFormat.format(DateTime.fromMillisecondsSinceEpoch(v.toInt())),
          textStyle: const pw.TextStyle(fontSize: 7, color: _grey),
        ),
        yAxis: pw.FixedAxis<double>(
          [0, maxY],
          divisions: true,
          divisionsColor: PdfColors.grey300,
          format: (v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1),
          textStyle: const pw.TextStyle(fontSize: 7, color: _grey),
        ),
      ),
      overlay: series.length > 1
          ? pw.ChartLegend(
              position: pw.Alignment.topRight,
              direction: pw.Axis.horizontal,
              textStyle: const pw.TextStyle(fontSize: 7.5),
              decoration: const pw.BoxDecoration(color: PdfColors.white),
            )
          : null,
      datasets: [
        for (final s in series)
          pw.LineDataSet(
            legend: s.label,
            color: s.color,
            lineColor: s.color,
            drawPoints: s.points.length <= 60,
            pointSize: 1.5,
            lineWidth: 1.3,
            data: [for (final (date, value) in s.points) pw.PointChartValue(date.millisecondsSinceEpoch.toDouble(), value)],
          ),
      ],
    ),
  );
}
