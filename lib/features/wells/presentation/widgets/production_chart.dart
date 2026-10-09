import 'package:flutter/material.dart';

import '../../../../core/models/analysis_record.dart';
import '../../../../core/widgets/series_chart.dart';

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
///
/// [markers] : interventions (date + libellé) dessinées en lignes verticales.
class ProductionChart extends StatelessWidget {
  final List<ProductionSeries> series;
  final List<(DateTime, String)> markers;

  const ProductionChart({super.key, required this.series, this.markers = const []});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nonEmpty = series.where((s) => s.records.isNotEmpty).toList();

    return SizedBox(
      height: 200,
      width: double.infinity,
      child: CustomPaint(
        painter: _ProductionPainter(
          series: nonEmpty,
          markers: markers,
          gridColor: scheme.outlineVariant,
        ),
      ),
    );
  }
}

class _ProductionPainter extends CustomPainter {
  final List<ProductionSeries> series;
  final List<(DateTime, String)> markers;
  final Color gridColor;

  _ProductionPainter({required this.series, required this.markers, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    const leftPadding = 8.0;
    const bottomPadding = 4.0;
    final topPadding = markers.isEmpty ? 0.0 : 14.0;
    final chartWidth = size.width - leftPadding * 2;
    final chartHeight = size.height - bottomPadding - topPadding;

    final baselinePaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(leftPadding, topPadding + chartHeight),
      Offset(size.width - leftPadding, topPadding + chartHeight),
      baselinePaint,
    );

    if (series.isEmpty) return;

    final allDates = [
      for (final s in series) for (final r in s.records) r.dateTime,
      for (final m in markers) m.$1,
    ];
    final minDate = allDates.reduce((a, b) => a.isBefore(b) ? a : b);
    final maxDate = allDates.reduce((a, b) => a.isAfter(b) ? a : b);
    final totalSpan = maxDate.difference(minDate).inMinutes;

    double xFor(DateTime date) {
      if (totalSpan <= 0) return leftPadding + chartWidth / 2;
      return leftPadding + chartWidth * date.difference(minDate).inMinutes / totalSpan;
    }

    // Interventions : lignes verticales pointillées + libellé court.
    var lastLabelEnd = double.negativeInfinity;
    for (final (date, label) in [...markers]..sort((a, b) => a.$1.compareTo(b.$1))) {
      final x = xFor(date);
      final paint = Paint()
        ..color = interventionMarkerColor.withValues(alpha: 0.8)
        ..strokeWidth = 1.4;
      for (var y = topPadding; y < topPadding + chartHeight; y += 9) {
        canvas.drawLine(Offset(x, y), Offset(x, (y + 5).clamp(0, topPadding + chartHeight)), paint);
      }
      canvas.drawCircle(Offset(x, topPadding), 3.5, Paint()..color = interventionMarkerColor);
      if (x + 5 > lastLabelEnd + 4) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(fontFamily: 'Manrope', fontSize: 9.5, color: interventionMarkerColor, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 90);
        final labelX = (x + 5).clamp(0.0, size.width - painter.width);
        painter.paint(canvas, Offset(labelX, 0));
        lastLabelEnd = labelX + painter.width;
      }
    }

    for (final s in series) {
      final values = s.records.map((r) => r.value).toList();
      final hi = values.reduce((a, b) => a > b ? a : b) * 1.15;
      final span = hi <= 0 ? 1 : hi;
      double yFor(double v) => topPadding + chartHeight - (v / span) * chartHeight;

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
  bool shouldRepaint(covariant _ProductionPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.markers != markers;
}
