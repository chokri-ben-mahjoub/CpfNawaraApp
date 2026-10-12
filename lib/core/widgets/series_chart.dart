import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../analysis/series.dart';

/// Un point du graphique (x : millisecondes depuis l'époque pour un axe
/// temporel, ou numéro de jour pour un axe "jours depuis le début").
class ChartPoint {
  final double x;
  final double y;
  const ChartPoint(this.x, this.y);
}

class ChartSeries {
  final String label;
  final Color color;
  final List<ChartPoint> points;
  final bool dashed;
  final bool showDots;
  final double strokeWidth;

  /// Masque la série dans la bulle de lecture au toucher (ex: courbe
  /// ajustée, déjà lisible sur l'axe).
  final bool inTooltip;

  /// Courbe lissée (passe par chaque point sans dépasser les valeurs
  /// voisines) plutôt que des segments droits.
  final bool smooth;

  /// Remplissage dégradé sous la courbe.
  final bool area;

  const ChartSeries({
    required this.label,
    required this.color,
    required this.points,
    this.dashed = false,
    this.showDots = true,
    this.strokeWidth = 2.4,
    this.inTooltip = true,
    this.smooth = false,
    this.area = false,
  });

  /// Construit une série temporelle à partir de [SeriesPoint].
  factory ChartSeries.fromTime({
    required String label,
    required Color color,
    required List<SeriesPoint> points,
    bool dashed = false,
    bool showDots = true,
    double strokeWidth = 2.4,
    bool inTooltip = true,
    bool smooth = false,
    bool area = false,
  }) => ChartSeries(
    label: label,
    color: color,
    points: [for (final p in points) ChartPoint(p.t.millisecondsSinceEpoch.toDouble(), p.v)],
    dashed: dashed,
    showDots: showDots,
    strokeWidth: strokeWidth,
    inTooltip: inTooltip,
    smooth: smooth,
    area: area,
  );
}

/// Marqueur vertical (ex: intervention sur le puits).
class ChartMarker {
  final double x;
  final String label;
  final Color color;
  const ChartMarker({required this.x, required this.label, required this.color});

  factory ChartMarker.at(DateTime t, {required String label, required Color color}) =>
      ChartMarker(x: t.millisecondsSinceEpoch.toDouble(), label: label, color: color);
}

/// Couleur des marqueurs d'intervention, commune à tous les graphiques.
const interventionMarkerColor = Color(0xFF8E24AA);

/// Graphique multi-courbes dessiné à la main (pas de dépendance externe) :
/// axes gradués, bande de seuil optionnelle, échelle logarithmique
/// optionnelle (courbes de déclin), marqueurs verticaux, et lecture des
/// valeurs au toucher (glisser le doigt sur le graphique).
class SeriesChart extends StatefulWidget {
  final List<ChartSeries> series;
  final List<ChartMarker> markers;
  final String Function(double x) xLabel;
  final String Function(double y) yLabel;
  final bool logScale;

  /// Bande min/max (seuil attendu) dessinée en arrière-plan.
  final (double, double)? band;
  final double height;

  /// Domaine x imposé (sinon : du premier au dernier point/marqueur).
  final double? xMin;
  final double? xMax;

  const SeriesChart({
    super.key,
    required this.series,
    required this.xLabel,
    this.yLabel = formatNumber,
    this.markers = const [],
    this.logScale = false,
    this.band,
    this.height = 220,
    this.xMin,
    this.xMax,
  });

  @override
  State<SeriesChart> createState() => _SeriesChartState();
}

class _SeriesChartState extends State<SeriesChart> {
  double? _touchX; // position du doigt, en pixels

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Un second appui au même endroit masque la bulle de lecture.
        onTapDown: (d) => setState(() {
          final x = d.localPosition.dx;
          _touchX = _touchX != null && (x - _touchX!).abs() < 16 ? null : x;
        }),
        onHorizontalDragStart: (d) => setState(() => _touchX = d.localPosition.dx),
        onHorizontalDragUpdate: (d) => setState(() => _touchX = d.localPosition.dx),
        onLongPressEnd: (_) => setState(() => _touchX = null),
        child: CustomPaint(
          painter: _SeriesPainter(
            series: widget.series.where((s) => s.points.isNotEmpty).toList(),
            markers: widget.markers,
            xLabel: widget.xLabel,
            yLabel: widget.yLabel,
            logScale: widget.logScale,
            band: widget.band,
            xMinOverride: widget.xMin,
            xMaxOverride: widget.xMax,
            touchX: _touchX,
            gridColor: scheme.outlineVariant,
            labelColor: scheme.onSurfaceVariant,
            bandColor: scheme.primary.withValues(alpha: 0.07),
            tooltipBackground: scheme.inverseSurface,
            tooltipText: scheme.onInverseSurface,
          ),
        ),
      ),
    );
  }
}

class _SeriesPainter extends CustomPainter {
  final List<ChartSeries> series;
  final List<ChartMarker> markers;
  final String Function(double) xLabel;
  final String Function(double) yLabel;
  final bool logScale;
  final (double, double)? band;
  final double? xMinOverride;
  final double? xMaxOverride;
  final double? touchX;
  final Color gridColor;
  final Color labelColor;
  final Color bandColor;
  final Color tooltipBackground;
  final Color tooltipText;

  _SeriesPainter({
    required this.series,
    required this.markers,
    required this.xLabel,
    required this.yLabel,
    required this.logScale,
    required this.band,
    required this.xMinOverride,
    required this.xMaxOverride,
    required this.touchX,
    required this.gridColor,
    required this.labelColor,
    required this.bandColor,
    required this.tooltipBackground,
    required this.tooltipText,
  });

  static const _leftGutter = 46.0;
  static const _rightPad = 10.0;
  static const _topPad = 16.0;
  static const _bottomGutter = 20.0;

  double _ty(double v) => logScale ? math.log(v) / math.ln10 : v;
  double _fromTy(double v) => logScale ? math.pow(10, v).toDouble() : v;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_leftGutter, _topPad, size.width - _rightPad, size.height - _bottomGutter);
    final usable = [
      for (final s in series)
        for (final p in s.points)
          if (!logScale || p.y > 0) p,
    ];

    if (usable.isEmpty) {
      canvas.drawLine(plot.bottomLeft, plot.bottomRight, Paint()..color = gridColor);
      return;
    }

    // --- Domaine X ---
    var xMin = xMinOverride ?? usable.map((p) => p.x).reduce(math.min);
    var xMax = xMaxOverride ?? usable.map((p) => p.x).reduce(math.max);
    if (xMinOverride == null || xMaxOverride == null) {
      for (final m in markers) {
        if (xMinOverride == null) xMin = math.min(xMin, m.x);
        if (xMaxOverride == null) xMax = math.max(xMax, m.x);
      }
    }
    if (xMax - xMin <= 0) {
      final pad = xMin.abs() > 1e9 ? 43200000.0 : 0.5; // ±12 h sur un axe temporel
      xMin -= pad;
      xMax += pad;
    }

    // --- Domaine Y ---
    var yLo = usable.map((p) => _ty(p.y)).reduce(math.min);
    var yHi = usable.map((p) => _ty(p.y)).reduce(math.max);
    if (band != null && !logScale) {
      yLo = math.min(yLo, band!.$1);
      yHi = math.max(yHi, band!.$2);
    }
    final ticks = logScale ? _logTicks(yLo, yHi) : _niceTicks(yLo, yHi, 4);
    final yMin = ticks.first;
    final yMax = ticks.last;

    double px(double x) => plot.left + (x - xMin) / (xMax - xMin) * plot.width;
    double py(double y) => plot.bottom - (_ty(y) - yMin) / (yMax - yMin) * plot.height;
    double pyT(double ty) => plot.bottom - (ty - yMin) / (yMax - yMin) * plot.height;

    // --- Bande de seuil ---
    if (band != null && !logScale) {
      final top = py(band!.$2).clamp(plot.top, plot.bottom);
      final bottom = py(band!.$1).clamp(plot.top, plot.bottom);
      canvas.drawRect(Rect.fromLTRB(plot.left, top, plot.right, bottom), Paint()..color = bandColor);
    }

    // --- Grille + graduations Y ---
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..strokeWidth = 0.8;
    for (final t in ticks) {
      final y = pyT(t);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(canvas, yLabel(_fromTy(t)), Offset(plot.left - 6, y), align: _Align.rightCenter, size: 10);
    }

    // --- Graduations X (début, milieu, fin) ---
    for (final (frac, align) in [(0.0, _Align.leftTop), (0.5, _Align.centerTop), (1.0, _Align.rightTop)]) {
      final x = xMin + (xMax - xMin) * frac;
      _text(canvas, xLabel(x), Offset(plot.left + plot.width * frac, plot.bottom + 5), align: align, size: 10);
    }

    // --- Marqueurs ---
    var lastLabelEnd = double.negativeInfinity;
    for (final m in [...markers]..sort((a, b) => a.x.compareTo(b.x))) {
      if (m.x < xMin || m.x > xMax) continue;
      final x = px(m.x);
      _dashedLine(
        canvas,
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = m.color.withValues(alpha: 0.8)
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(Offset(x, plot.top), 4, Paint()..color = m.color);
      if (x + 6 > lastLabelEnd + 4) {
        final painter = _layout(m.label, size: 9.5, color: m.color, maxWidth: 90);
        painter.paint(canvas, Offset(x + 6, plot.top - 13));
        lastLabelEnd = x + 6 + painter.width;
      }
    }

    // --- Courbes ---
    canvas.save();
    canvas.clipRect(plot.inflate(6));
    for (final s in series) {
      final pts = [
        for (final p in s.points)
          if (!logScale || p.y > 0) Offset(px(p.x), py(p.y)),
      ];
      if (pts.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (s.dashed) {
        for (var i = 1; i < pts.length; i++) {
          _dashedLine(canvas, pts[i - 1], pts[i], paint);
        }
      } else {
        final path = s.smooth && pts.length > 2 ? _monotonePath(pts) : _polyline(pts);
        if (s.area && pts.length > 1) {
          final fill = Path.from(path)
            ..lineTo(pts.last.dx, plot.bottom)
            ..lineTo(pts.first.dx, plot.bottom)
            ..close();
          canvas.drawPath(
            fill,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [s.color.withValues(alpha: 0.28), s.color.withValues(alpha: 0.02)],
              ).createShader(plot),
          );
        }
        canvas.drawPath(path, paint);
      }
      if (s.showDots && pts.length <= 90) {
        for (final p in pts) {
          canvas.drawCircle(p, pts.length > 40 ? 2 : 3, Paint()..color = s.color);
        }
      }
    }
    canvas.restore();

    // --- Lecture au toucher ---
    final touch = touchX;
    if (touch != null && touch >= plot.left - 8 && touch <= plot.right + 8) {
      final xValue = xMin + ((touch.clamp(plot.left, plot.right) - plot.left) / plot.width) * (xMax - xMin);
      final lines = <(String, Color)>[];
      double? snappedX;
      for (final s in series.where((s) => s.inTooltip)) {
        ChartPoint? nearest;
        for (final p in s.points) {
          if (logScale && p.y <= 0) continue;
          if (nearest == null || (p.x - xValue).abs() < (nearest.x - xValue).abs()) nearest = p;
        }
        if (nearest == null) continue;
        snappedX ??= nearest.x;
        lines.add(('${s.label} : ${yLabel(nearest.y)}', s.color));
        canvas.drawCircle(Offset(px(nearest.x), py(nearest.y)), 5, Paint()..color = s.color);
        canvas.drawCircle(
          Offset(px(nearest.x), py(nearest.y)),
          5,
          Paint()
            ..color = tooltipText
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      if (lines.isNotEmpty) {
        final lineX = px(snappedX!);
        canvas.drawLine(
          Offset(lineX, plot.top),
          Offset(lineX, plot.bottom),
          Paint()
            ..color = labelColor.withValues(alpha: 0.6)
            ..strokeWidth = 1,
        );
        _tooltip(canvas, plot, lineX, xLabel(snappedX), lines);
      }
    }
  }

  static Path _polyline(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  /// Courbe lissée monotone (Fritsch-Carlson) : arrondie comme une vague,
  /// mais sans creux ni bosse inventés entre deux mesures.
  static Path _monotonePath(List<Offset> pts) {
    final n = pts.length;
    final slopes = List<double>.generate(n - 1, (i) {
      final dx = pts[i + 1].dx - pts[i].dx;
      return dx == 0 ? 0 : (pts[i + 1].dy - pts[i].dy) / dx;
    });
    final tangents = List<double>.filled(n, 0);
    tangents[0] = slopes.first;
    tangents[n - 1] = slopes.last;
    for (var i = 1; i < n - 1; i++) {
      final a = slopes[i - 1];
      final b = slopes[i];
      tangents[i] = a * b <= 0 ? 0 : 2 / (1 / a + 1 / b);
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < n - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final h = (p1.dx - p0.dx) / 3;
      path.cubicTo(p0.dx + h, p0.dy + tangents[i] * h, p1.dx - h, p1.dy - tangents[i + 1] * h, p1.dx, p1.dy);
    }
    return path;
  }

  void _tooltip(Canvas canvas, Rect plot, double anchorX, String title, List<(String, Color)> lines) {
    final painters = [
      _layout(title, size: 10.5, color: tooltipText, bold: true),
      for (final (text, _) in lines) _layout(text, size: 10.5, color: tooltipText),
    ];
    final width = painters.map((p) => p.width).reduce(math.max) + 26;
    final height = painters.fold<double>(0, (h, p) => h + p.height + 2) + 10;
    var left = anchorX + 10;
    if (left + width > plot.right) left = anchorX - 10 - width;
    left = left.clamp(plot.left, math.max(plot.left, plot.right - width));
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, plot.top + 4, width, height), const Radius.circular(8));
    canvas.drawRRect(rect, Paint()..color = tooltipBackground.withValues(alpha: 0.92));
    var y = plot.top + 9;
    painters.first.paint(canvas, Offset(left + 8, y));
    y += painters.first.height + 2;
    for (var i = 0; i < lines.length; i++) {
      canvas.drawCircle(Offset(left + 11, y + painters[i + 1].height / 2), 3.5, Paint()..color = lines[i].$2);
      painters[i + 1].paint(canvas, Offset(left + 18, y));
      y += painters[i + 1].height + 2;
    }
  }

  TextPainter _layout(String text, {required double size, Color? color, bool bold = false, double? maxWidth}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: size,
          color: color ?? labelColor,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    return painter;
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    required _Align align,
    required double size,
    Color? color,
    double? maxWidth,
  }) {
    final painter = _layout(text, size: size, color: color, maxWidth: maxWidth);
    late Offset origin;
    switch (align) {
      case _Align.rightCenter:
        origin = Offset(at.dx - painter.width, at.dy - painter.height / 2);
      case _Align.leftTop:
        origin = at;
      case _Align.centerTop:
        origin = Offset(at.dx - painter.width / 2, at.dy);
      case _Align.rightTop:
        origin = Offset(at.dx - painter.width, at.dy);
    }
    painter.paint(canvas, origin);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d = end + gap;
    }
  }

  /// Graduations "rondes" (1, 2, 5 × 10^n) englobant [lo, hi].
  static List<double> _niceTicks(double lo, double hi, int count) {
    if (hi - lo <= 0) {
      final pad = lo.abs() * 0.1 + 1;
      lo -= pad;
      hi += pad;
    }
    final step = _niceNum((hi - lo) / (count - 1));
    final start = (lo / step).floorToDouble() * step;
    final end = (hi / step).ceilToDouble() * step;
    final ticks = <double>[];
    for (var v = start; v <= end + step * 0.5; v += step) {
      ticks.add(double.parse(v.toStringAsPrecision(12)));
    }
    return ticks.length < 2 ? [start, start + step] : ticks;
  }

  static double _niceNum(double range) {
    final exponent = (math.log(range) / math.ln10).floorToDouble();
    final fraction = range / math.pow(10, exponent);
    final nice = fraction <= 1
        ? 1
        : fraction <= 2
        ? 2
        : fraction <= 5
        ? 5
        : 10;
    return nice * math.pow(10, exponent).toDouble();
  }

  /// Graduations d'un axe logarithmique (en log10) : décades, plus 2× et 5×
  /// quand la plage est courte.
  static List<double> _logTicks(double lo, double hi) {
    final start = lo.floorToDouble();
    var end = hi.ceilToDouble();
    if (end <= start) end = start + 1;
    final ticks = <double>[];
    final fine = end - start <= 2;
    for (var d = start; d <= end; d++) {
      ticks.add(d);
      if (fine && d < end) {
        ticks.add(d + math.log(2) / math.ln10);
        ticks.add(d + math.log(5) / math.ln10);
      }
    }
    // Resserre le domaine autour des données pour garder une courbe lisible.
    while (ticks.length > 3 && ticks[1] <= lo) {
      ticks.removeAt(0);
    }
    while (ticks.length > 3 && ticks[ticks.length - 2] >= hi) {
      ticks.removeLast();
    }
    return ticks;
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter old) =>
      old.series != series ||
      old.markers != markers ||
      old.touchX != touchX ||
      old.logScale != logScale ||
      old.band != band ||
      old.gridColor != gridColor;
}

enum _Align { rightCenter, leftTop, centerTop, rightTop }

/// Légende compacte (pastille de couleur + libellé) sous un graphique.
class ChartLegend extends StatelessWidget {
  final List<(String, Color, bool)> entries; // libellé, couleur, pointillés

  const ChartLegend({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (label, color, dashed) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dashed
                  ? SizedBox(width: 16, height: 10, child: CustomPaint(painter: _DashLegendPainter(color)))
                  : Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
      ],
    );
  }
}

class _DashLegendPainter extends CustomPainter {
  final Color color;
  _DashLegendPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(6, y), paint);
    canvas.drawLine(Offset(10, y), Offset(16, y), paint);
  }

  @override
  bool shouldRepaint(covariant _DashLegendPainter old) => old.color != color;
}
