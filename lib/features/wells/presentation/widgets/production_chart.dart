import 'package:flutter/material.dart';

import '../../../../core/models/analysis_record.dart';

/// Une courbe de production (huile, gaz ou eau) à tracer dans [ProductionChart].
class ProductionSeries {
  final String label;
  final String unit;
  final Color color;
  final List<AnalysisRecord> records;

  const ProductionSeries({
    required this.label,
    required this.unit,
    required this.color,
    required this.records,
  });
}

/// Courbes de débit (huile/gaz/eau) superposées sur un même axe temporel,
/// dessinées à la main (pas de dépendance externe). Chaque courbe a sa
/// propre échelle verticale (affichée en légende) pour rester lisible même
/// si les débits ont des ordres de grandeur très différents.
class ProductionChart extends StatelessWidget {
  final List<ProductionSeries> series;

  const ProductionChart({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nonEmpty = series.where((s) => s.records.isNotEmpty).toList();

    return SizedBox(
      height: 200,
      width: double.infinity,
      child: CustomPaint(
        painter: _ProductionPainter(series: nonEmpty, gridColor: scheme.outlineVariant),
      ),
    );
  }
}

class _ProductionPainter extends CustomPainter {
  final List<ProductionSeries> series;
  final Color gridColor;

  _ProductionPainter({required this.series, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    const leftPadding = 8.0;
    const bottomPadding = 4.0;
    final chartWidth = size.width - leftPadding * 2;
    final chartHeight = size.height - bottomPadding;

    final baselinePaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(leftPadding, chartHeight), Offset(size.width - leftPadding, chartHeight), baselinePaint);

    if (series.isEmpty) return;

    final allDates = [for (final s in series) for (final r in s.records) r.dateTime];
    final minDate = allDates.reduce((a, b) => a.isBefore(b) ? a : b);
    final maxDate = allDates.reduce((a, b) => a.isAfter(b) ? a : b);
    final totalSpan = maxDate.difference(minDate).inMinutes;

    double xFor(DateTime date) {
      if (totalSpan <= 0) return leftPadding + chartWidth / 2;
      return leftPadding + chartWidth * date.difference(minDate).inMinutes / totalSpan;
    }

    for (final s in series) {
      final values = s.records.map((r) => r.value).toList();
      final hi = values.reduce((a, b) => a > b ? a : b) * 1.15;
      final span = hi <= 0 ? 1 : hi;
      double yFor(double v) => chartHeight - (v / span) * chartHeight;

      final linePaint = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path();
      for (var i = 0; i < s.records.length; i++) {
        final point = Offset(xFor(s.records[i].dateTime), yFor(s.records[i].value));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, linePaint);

      for (final record in s.records) {
        canvas.drawCircle(Offset(xFor(record.dateTime), yFor(record.value)), 3, Paint()..color = s.color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ProductionPainter oldDelegate) => oldDelegate.series != series;
}
