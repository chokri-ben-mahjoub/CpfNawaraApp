import 'package:flutter/material.dart';

import '../../../../core/models/analysis_record.dart';
import '../../../../core/widgets/series_chart.dart';

/// Courbe d'évolution dessinée à la main (pas de dépendance externe) :
/// ligne reliant les valeurs dans l'ordre chronologique (abscisse
/// proportionnelle au temps), bande de seuil min/max en arrière-plan, points
/// hors seuil mis en évidence, interventions en lignes verticales.
class TrendChart extends StatelessWidget {
  final List<AnalysisRecord> records;
  final double min;
  final double max;
  final Color lineColor;
  final List<(DateTime, String)> markers;

  const TrendChart({
    super.key,
    required this.records,
    required this.min,
    required this.max,
    required this.lineColor,
    this.markers = const [],
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
          markers: markers,
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
  final List<(DateTime, String)> markers;
  final double min;
  final double max;
  final Color lineColor;
  final Color errorColor;
  final Color gridColor;
  final Color bandColor;

  _TrendPainter({
    required this.records,
    required this.markers,
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
    final topPadding = markers.isEmpty ? 0.0 : 14.0;
    final chartWidth = size.width - leftPadding * 2;
    final chartHeight = size.height - bottomPadding - topPadding;

    final values = records.map((r) => r.value).toList();
    final dataMin = values.isEmpty ? min : values.reduce((a, b) => a < b ? a : b);
    final dataMax = values.isEmpty ? max : values.reduce((a, b) => a > b ? a : b);
    final lo = [min, dataMin].reduce((a, b) => a < b ? a : b);
    final hi = [max, dataMax].reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1 : (hi - lo);

    double yFor(double value) => topPadding + chartHeight - ((value - lo) / span) * chartHeight;

    final dates = [for (final r in records) r.dateTime, for (final m in markers) m.$1];
    final minDate = dates.isEmpty ? DateTime.now() : dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final maxDate = dates.isEmpty ? DateTime.now() : dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final totalSpan = maxDate.difference(minDate).inMinutes;
    double xForDate(DateTime d) =>
        leftPadding + (totalSpan <= 0 ? chartWidth / 2 : chartWidth * d.difference(minDate).inMinutes / totalSpan);
    double xFor(int index) => xForDate(records[index].dateTime);

    // Bande de seuil min/max.
    final bandPaint = Paint()..color = bandColor;
    final bandTop = yFor(max).clamp(topPadding, topPadding + chartHeight);
    final bandBottom = yFor(min).clamp(topPadding, topPadding + chartHeight);
    canvas.drawRect(Rect.fromLTRB(leftPadding, bandTop, size.width - leftPadding, bandBottom), bandPaint);

    // Lignes de seuil.
    final dashPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(leftPadding, yFor(max)), Offset(size.width - leftPadding, yFor(max)), dashPaint);
    canvas.drawLine(Offset(leftPadding, yFor(min)), Offset(size.width - leftPadding, yFor(min)), dashPaint);

    // Interventions : lignes verticales pointillées + libellé court.
    var lastLabelEnd = double.negativeInfinity;
    for (final (date, label) in [...markers]..sort((a, b) => a.$1.compareTo(b.$1))) {
      final x = xForDate(date);
      final markerPaint = Paint()
        ..color = interventionMarkerColor.withValues(alpha: 0.8)
        ..strokeWidth = 1.4;
      for (var y = topPadding; y < topPadding + chartHeight; y += 9) {
        canvas.drawLine(Offset(x, y), Offset(x, (y + 5).clamp(0, topPadding + chartHeight)), markerPaint);
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
      oldDelegate.records != records ||
      oldDelegate.markers != markers ||
      oldDelegate.min != min ||
      oldDelegate.max != max;
}
