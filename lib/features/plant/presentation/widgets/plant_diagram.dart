import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/plant/plant_catalog.dart';
import '../../../../core/plant/plant_repository.dart';

/// Dimensions logiques du schéma (mis à l'échelle de l'écran).
const _canvas = Size(1000, 560);

/// Diamètre des points de prélèvement (unités du schéma).
const _markerSize = 40.0;

/// Position des points de prélèvement sur le schéma (par code).
const _markerPositions = <String, Offset>{
  'C1': Offset(376, 180),
  'C2': Offset(340, 355),
  'C3': Offset(510, 355),
  'C4': Offset(915, 355),
  'W1': Offset(350, 490),
  'W2': Offset(200, 245),
  'W3': Offset(590, 490),
  'W4': Offset(300, 520),
  'G1': Offset(340, 255),
  'G2': Offset(318, 75),
  'G3': Offset(905, 55),
  'LA': Offset(720, 175),
  'RA': Offset(612, 208),
};

Color plantStatusColor(PlantStatus status, ColorScheme scheme) => switch (status) {
  PlantStatus.ok => Colors.green.shade600,
  PlantStatus.outOfRange => scheme.error,
  PlantStatus.missing => scheme.outline,
};

/// Schéma de procédé de l'usine (PFD simplifié) : circuits gaz, amine,
/// condensat et eau produite, avec les points de prélèvement colorés selon
/// leur état du jour (vert / rouge / gris). Zoom et déplacement au doigt ;
/// toucher un point appelle [onPointTap].
class PlantDiagram extends ConsumerWidget {
  final DateTime day;
  final ValueChanged<SamplePoint> onPointTap;

  const PlantDiagram({super.key, required this.day, required this.onPointTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final points = ref.watch(plantControllerProvider).points.where((p) => p.active).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // Sur téléphone, le schéma garde une taille lisible (points faciles à
        // toucher) et défile horizontalement ; sur grand écran il remplit la
        // largeur et se zoome au doigt / à la molette.
        final narrow = available < 700;
        final width = narrow ? 760.0 : available;
        final height = width * _canvas.height / _canvas.width;
        final diagram = SizedBox(
          width: width,
          height: height,
          child: FittedBox(
            child: SizedBox.fromSize(
              size: _canvas,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PlantPainter(
                        s: s,
                        text: scheme.onSurface,
                        muted: scheme.onSurfaceVariant,
                        vessel: scheme.surfaceContainerHighest,
                        vesselEdge: scheme.outline,
                        background: scheme.surface,
                      ),
                    ),
                  ),
                  for (final point in points)
                    if (_markerPositions[point.code] != null)
                      Positioned(
                        left: _markerPositions[point.code]!.dx - _markerSize / 2,
                        top: _markerPositions[point.code]!.dy - _markerSize / 2,
                        child: _Marker(
                          point: point,
                          status: controller.status(point, day),
                          onTap: () => onPointTap(point),
                        ),
                      ),
                ],
              ),
            ),
          ),
        );
        if (narrow) {
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: diagram);
        }
        return ClipRect(child: InteractiveViewer(minScale: 1, maxScale: 4, child: diagram));
      },
    );
  }
}

class _Marker extends StatelessWidget {
  final SamplePoint point;
  final PlantStatus status;
  final VoidCallback onTap;

  const _Marker({required this.point, required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = plantStatusColor(status, scheme);
    return Tooltip(
      message: '${point.code} — ${point.name}',
      child: Material(
        color: fill,
        shape: CircleBorder(side: BorderSide(color: point.circuit.color, width: 3.5)),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: _markerSize,
            height: _markerSize,
            child: Center(
              child: Text(
                point.code,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: status == PlantStatus.missing ? scheme.surface : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlantPainter extends CustomPainter {
  final String Function(String) s;
  final Color text;
  final Color muted;
  final Color vessel;
  final Color vesselEdge;
  final Color background;

  _PlantPainter({
    required this.s,
    required this.text,
    required this.muted,
    required this.vessel,
    required this.vesselEdge,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gas = PlantCircuit.gas.color;
    final cond = PlantCircuit.condensate.color;
    final water = PlantCircuit.water.color;
    const lean = Color(0xFF2E9E5B);
    const rich = Color(0xFF8E24AA);

    // --- Lignes (dessinées avant les équipements) ---
    // Effluent des puits vers les deux séparateurs.
    _line(canvas, [
      const Offset(110, 280),
      const Offset(150, 280),
      const Offset(150, 125),
      const Offset(220, 125),
    ], muted);
    _line(canvas, [const Offset(150, 280), const Offset(150, 355), const Offset(220, 355)], muted);
    _label(canvas, s('plantEqWellStream'), const Offset(42, 318), muted, size: 10.5);

    // Gaz : séparateurs -> contacteur amine -> contacteur TEG -> export.
    _line(canvas, [const Offset(296, 75), const Offset(440, 75)], gas);
    _line(canvas, [const Offset(296, 300), const Offset(340, 300), const Offset(340, 75)], gas, arrow: false);
    _line(canvas, [const Offset(516, 55), const Offset(820, 55)], gas);
    _line(canvas, [const Offset(884, 55), const Offset(990, 55)], gas);
    _label(canvas, s('plantEqExportGas'), const Offset(926, 70), gas, bold: true, size: 12);

    // Amine : pauvre (pompe HP -> contacteur), riche (contacteur -> flash drum),
    // régénération (flash drum -> pompe).
    _line(canvas, [const Offset(720, 228), const Offset(720, 110), const Offset(516, 110)], lean);
    _line(canvas, [
      const Offset(516, 190),
      const Offset(540, 190),
      const Offset(540, 162),
      const Offset(560, 162),
    ], rich);
    _line(
      canvas,
      [const Offset(660, 162), const Offset(770, 162), const Offset(770, 250), const Offset(742, 250)],
      lean,
      dashed: true,
    );
    _label(canvas, s('plantEqLeanAmine'), const Offset(600, 92), lean, size: 10.5);
    _label(canvas, s('plantEqRichAmine'), const Offset(522, 214), rich, size: 10.5);
    _label(canvas, s('plantEqRegeneration'), const Offset(776, 196), muted, size: 10);

    // Condensat : séparateurs -> rebouilleur -> bac de stockage -> stockage.
    _line(canvas, [const Offset(296, 180), const Offset(400, 180), const Offset(400, 355)], cond, arrow: false);
    _line(canvas, [const Offset(296, 355), const Offset(560, 355)], cond);
    _line(canvas, [const Offset(680, 355), const Offset(760, 355)], cond);
    _line(canvas, [const Offset(860, 355), const Offset(985, 355)], cond);
    _label(canvas, s('plantEqToStorage'), const Offset(905, 372), cond, bold: true, size: 11);

    // Eau produite : séparateurs -> séparateur W/C -> CPI -> traitement/rejet.
    _line(canvas, [const Offset(258, 430), const Offset(258, 490), const Offset(420, 490)], water);
    _line(canvas, [
      const Offset(220, 190),
      const Offset(200, 190),
      const Offset(200, 520),
      const Offset(420, 520),
    ], water);
    _line(canvas, [const Offset(530, 490), const Offset(640, 490)], water);
    _line(canvas, [const Offset(750, 498), const Offset(985, 498)], water);
    _label(canvas, s('plantEqWaterDisposal'), const Offset(800, 512), water, bold: true, size: 11);

    // --- Équipements ---
    _box(canvas, const Rect.fromLTWH(20, 250, 90, 60), s('plantEqWells'), bold: true);
    _vertical(canvas, const Rect.fromLTWH(220, 50, 76, 150), s('plantEqInletSeparator'));
    _vertical(canvas, const Rect.fromLTWH(220, 280, 76, 150), s('plantEqTestSeparator'));
    _vertical(canvas, const Rect.fromLTWH(440, 40, 76, 170), s('plantEqAmineContactor'), packed: true);
    _horizontal(canvas, const Rect.fromLTWH(560, 140, 100, 44), s('plantEqFlashDrum'));
    _pump(canvas, const Offset(720, 250), s('plantEqHpPump'));
    _vertical(canvas, const Rect.fromLTWH(820, 30, 64, 150), s('plantEqTegContactor'), packed: true);
    _horizontal(canvas, const Rect.fromLTWH(560, 330, 120, 50), s('plantEqReboiler'));
    _tank(canvas, const Rect.fromLTWH(760, 305, 100, 95), s('plantEqStorageTank'));
    _horizontal(canvas, const Rect.fromLTWH(420, 465, 110, 60), s('plantEqWcSeparator'));
    _horizontal(canvas, const Rect.fromLTWH(640, 470, 110, 56), s('plantEqCpiSeparator'));
  }

  // ------------------------------------------------------------ Dessin

  void _line(Canvas canvas, List<Offset> points, Color color, {bool arrow = true, bool dashed = false}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 1; i < points.length; i++) {
      if (dashed) {
        _dash(canvas, points[i - 1], points[i], paint);
      } else {
        canvas.drawLine(points[i - 1], points[i], paint);
      }
    }
    if (!arrow || points.length < 2) return;
    final end = points.last;
    final from = points[points.length - 2];
    final angle = math.atan2(end.dy - from.dy, end.dx - from.dx);
    const headLength = 12.0;
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx - headLength * math.cos(angle - 0.45), end.dy - headLength * math.sin(angle - 0.45))
      ..lineTo(end.dx - headLength * math.cos(angle + 0.45), end.dy - headLength * math.sin(angle + 0.45))
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += 14) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + 8, total), paint);
    }
  }

  Paint get _fill => Paint()..color = vessel;

  Paint get _edge => Paint()
    ..color = vesselEdge
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  void _box(Canvas canvas, Rect rect, String label, {bool bold = false}) {
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(r, _fill);
    canvas.drawRRect(r, _edge);
    _centered(canvas, label, rect, bold: bold);
  }

  /// Colonne / séparateur vertical (extrémités arrondies).
  void _vertical(Canvas canvas, Rect rect, String label, {bool packed = false}) {
    final r = RRect.fromRectAndRadius(rect, Radius.circular(rect.width / 2));
    canvas.drawRRect(r, _fill);
    if (packed) {
      // Garnissage symbolisé par des croisillons.
      final hatch = Paint()
        ..color = vesselEdge.withValues(alpha: 0.5)
        ..strokeWidth = 1.2;
      final top = rect.top + rect.height * 0.55;
      final bottom = rect.bottom - rect.width * 0.4;
      canvas.drawLine(Offset(rect.left + 6, top), Offset(rect.right - 6, bottom), hatch);
      canvas.drawLine(Offset(rect.right - 6, top), Offset(rect.left + 6, bottom), hatch);
      canvas.drawLine(Offset(rect.left + 6, top), Offset(rect.right - 6, top), hatch);
      canvas.drawLine(Offset(rect.left + 6, bottom), Offset(rect.right - 6, bottom), hatch);
    }
    canvas.drawRRect(r, _edge);
    _centered(canvas, label, Rect.fromLTWH(rect.left - 20, rect.top + 18, rect.width + 40, rect.height * 0.45));
  }

  void _horizontal(Canvas canvas, Rect rect, String label) {
    final r = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    canvas.drawRRect(r, _fill);
    canvas.drawRRect(r, _edge);
    _centered(canvas, label, rect);
  }

  void _tank(Canvas canvas, Rect rect, String label) {
    final body = Rect.fromLTWH(rect.left, rect.top + 10, rect.width, rect.height - 10);
    canvas.drawRect(body, _fill);
    canvas.drawRect(body, _edge);
    final lid = Rect.fromLTWH(rect.left, rect.top, rect.width, 20);
    canvas.drawOval(lid, _fill);
    canvas.drawOval(lid, _edge);
    _centered(canvas, label, Rect.fromLTWH(rect.left, rect.top + 20, rect.width, rect.height - 20));
  }

  void _pump(Canvas canvas, Offset center, String label) {
    canvas.drawCircle(center, 22, _fill);
    canvas.drawCircle(center, 22, _edge);
    canvas.drawCircle(center, 8, Paint()..color = vesselEdge.withValues(alpha: 0.6));
    _label(canvas, label, Offset(center.dx - 26, center.dy + 26), text, bold: true, size: 11);
  }

  void _centered(Canvas canvas, String label, Rect rect, {bool bold = true}) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 11.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: text,
          height: 1.15,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width);
    painter.paint(canvas, Offset(rect.center.dx - painter.width / 2, rect.center.dy - painter.height / 2));
  }

  void _label(Canvas canvas, String label, Offset at, Color color, {bool bold = false, double size = 11}) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Fond pour rester lisible quand le texte passe sur une ligne.
    canvas.drawRect(
      Rect.fromLTWH(at.dx - 2, at.dy - 1, painter.width + 4, painter.height + 2),
      Paint()..color = background.withValues(alpha: 0.85),
    );
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _PlantPainter old) => old.text != text || old.vessel != vessel;
}

/// Légende : couleurs des circuits et des états.
class PlantDiagramLegend extends ConsumerWidget {
  const PlantDiagramLegend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);

    Widget line(Color color, String label, {bool dashed = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 4,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
      ],
    );
    Widget dot(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
      ],
    );

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final c in PlantCircuit.values) line(c.color, s(c.labelKey)),
        line(const Color(0xFF8E24AA), s('plantEqRichAmine')),
        dot(Colors.green.shade600, s('plantStatusOk')),
        dot(scheme.error, s('plantStatusOut')),
        dot(scheme.outline, s('plantStatusMissing')),
      ],
    );
  }
}
