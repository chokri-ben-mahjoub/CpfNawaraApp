import 'package:flutter/material.dart';

import '../../../../core/models/analysis_record.dart';

/// Courbe d'évolution dessinée à la main (pas de dépendance externe) :
/// ligne reliant les valeurs dans l'ordre chronologique, bande de seuil
/// min/max en arrière-plan, points hors seuil mis en évidence.
class TrendChart extends StatelessWidget {
  final List<AnalysisRecord> records;
  final double min;
  final double max;
  final Color lineColor;

  const TrendChart({
    super.key,
    required this.records,
    required this.min,
    required this.max,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendPainter(
          records: records,
          min: min,
          max: max,
          lineColor: lineColor,
          errorColor: scheme.error,
          gridColor: scheme.outlineVariant,
          bandColor: lineColor.withValues(alpha: 0.08),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<AnalysisRecord> records;
  final double min;
  final double max;
  final Color lineColor;
  final Color errorColor;
  final Color gridColor;
  final Color bandColor;

  _TrendPainter({
    required this.records,
    required this.min,
    required this.max,
    required this.lineColor,
    required this.errorColor,
    required this.gridColor,
    required this.bandColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPadding = 8.0;
    const bottomPadding = 4.0;
    final chartWidth = size.width - leftPadding * 2;
    final chartHeight = size.height - bottomPadding;

    final values = records.map((r) => r.value).toList();
    final dataMin = values.isEmpty ? min : values.reduce((a, b) => a < b ? a : b);
    final dataMax = values.isEmpty ? max : values.reduce((a, b) => a > b ? a : b);
    final lo = [min, dataMin].reduce((a, b) => a < b ? a : b);
    final hi = [max, dataMax].reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1 : (hi - lo);

    double yFor(double value) => chartHeight - ((value - lo) / span) * chartHeight;
    double xFor(int index) =>
        leftPadding + (records.length <= 1 ? chartWidth / 2 : chartWidth * index / (records.length - 1));

    // Bande de seuil min/max.
    final bandPaint = Paint()..color = bandColor;
    final bandTop = yFor(max).clamp(0.0, chartHeight);
    final bandBottom = yFor(min).clamp(0.0, chartHeight);
    canvas.drawRect(Rect.fromLTRB(leftPadding, bandTop, size.width - leftPadding, bandBottom), bandPaint);

    // Lignes de seuil.
    final dashPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(leftPadding, yFor(max)), Offset(size.width - leftPadding, yFor(max)), dashPaint);
    canvas.drawLine(Offset(leftPadding, yFor(min)), Offset(size.width - leftPadding, yFor(min)), dashPaint);

    if (records.isEmpty) return;

    // Courbe reliant les valeurs.
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < records.length; i++) {
      final point = Offset(xFor(i), yFor(records[i].value));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    // Points, en rouge si hors seuil.
    for (var i = 0; i < records.length; i++) {
      final value = records[i].value;
      final outOfRange = value < min || value > max;
      final point = Offset(xFor(i), yFor(value));
      canvas.drawCircle(point, outOfRange ? 5 : 3.5, Paint()..color = outOfRange ? errorColor : lineColor);
      if (outOfRange) {
        canvas.drawCircle(point, 5, Paint()
          ..color = errorColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.records != records || oldDelegate.min != min || oldDelegate.max != max;
}
