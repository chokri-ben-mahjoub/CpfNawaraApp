import 'package:flutter/material.dart';

/// Mini courbe de tendance (vue d'ensemble) : une seule ligne, pas d'axes ni
/// de bande de seuil — juste l'allure générale de la production totale sur
/// quelques jours, pour un coup d'œil rapide en haut du tableau de bord.
class AggregateTrendChart extends StatelessWidget {
  final List<(DateTime day, double total)> points;
  final Color color;

  const AggregateTrendChart({super.key, required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      width: double.infinity,
      child: CustomPaint(painter: _MiniTrendPainter(points: points, color: color)),
    );
  }
}

class _MiniTrendPainter extends CustomPainter {
  final List<(DateTime, double)> points;
  final Color color;

  _MiniTrendPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final values = [for (final p in points) p.$2];
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) <= 0 ? 1.0 : (hi - lo);

    const verticalPadding = 6.0;
    final chartHeight = size.height - verticalPadding * 2;
    double yFor(double v) => verticalPadding + chartHeight - ((v - lo) / span) * chartHeight;
    double xFor(int i) => points.length <= 1 ? 0 : size.width * i / (points.length - 1);

    final fillPath = Path();
    final linePath = Path();
    for (var i = 0; i < points.length; i++) {
      final point = Offset(xFor(i), yFor(points[i].$2));
      if (i == 0) {
        linePath.moveTo(point.dx, point.dy);
        fillPath.moveTo(point.dx, size.height);
        fillPath.lineTo(point.dx, point.dy);
      } else {
        linePath.lineTo(point.dx, point.dy);
        fillPath.lineTo(point.dx, point.dy);
      }
    }
    fillPath.lineTo(xFor(points.length - 1), size.height);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Point final mis en valeur.
    canvas.drawCircle(Offset(xFor(points.length - 1), yFor(points.last.$2)), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MiniTrendPainter oldDelegate) => oldDelegate.points != points;
}
