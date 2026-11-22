import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/plant/pfd_flow_arrows.dart';
import '../../../../core/plant/plant_repository.dart';
import '../../../../core/theme/status_style.dart';
import '../../../../core/theme/status_colors.dart';

/// Diamètre des points de prélèvement (unités du schéma, largeur 1000).
const _markerSize = 40.0;

Color plantStatusColor(PlantStatus status, ColorScheme scheme) => switch (status) {
  PlantStatus.ok => AppStatus.ok.color(scheme),
  PlantStatus.outOfRange => AppStatus.out.color(scheme),
  PlantStatus.missing => AppStatus.none.color(scheme),
};

/// Schéma de l'usine affiché dans l'onglet Usine : points de prélèvement
/// colorés selon leur état du jour (vert / rouge / gris). Sur téléphone, le
/// schéma garde une taille lisible et défile horizontalement ; sur grand
/// écran il remplit la largeur et se zoome au doigt / à la molette.
class PlantDiagram extends StatelessWidget {
  final PlantSchema schema;
  final DateTime day;
  final ValueChanged<SamplePoint> onPointTap;

  const PlantDiagram({super.key, required this.schema, required this.day, required this.onPointTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final narrow = available < 700;
        final canvas = PlantSchemaCanvas(
          schema: schema,
          day: day,
          width: narrow ? 900.0 : available,
          onMarkerTap: onPointTap,
        );
        if (narrow) {
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: canvas);
        }
        return ClipRect(child: InteractiveViewer(minScale: 1, maxScale: 6, child: canvas));
      },
    );
  }
}

/// Dessin d'un schéma à une largeur donnée : fond (dessin intégré, image
/// importée ou quadrillage) et points de prélèvement placés.
///
/// En configuration ([onMarkerMoved] renseigné), les points se déplacent au
/// doigt / à la souris, et [positions] remplace les positions enregistrées.
class PlantSchemaCanvas extends ConsumerWidget {
  final PlantSchema schema;
  final DateTime day;
  final double width;
  final Map<String, Offset?>? positions;
  final String? selectedId;
  final ValueChanged<SamplePoint>? onMarkerTap;
  final void Function(SamplePoint point, Offset position)? onMarkerMoved;
  final ValueChanged<Offset>? onBackgroundTap;

  const PlantSchemaCanvas({
    super.key,
    required this.schema,
    required this.day,
    required this.width,
    this.positions,
    this.selectedId,
    this.onMarkerTap,
    this.onMarkerMoved,
    this.onBackgroundTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);

    final logical = schema.canvasSize;
    final height = width * logical.height / logical.width;
    final scale = width / logical.width;
    final marker = math.max(28.0, _markerSize * scale);
    final shown = schema.copyWith(positions: positions);

    final Widget background = switch (schema.kind) {
      PlantSchemaKind.pfd => Container(
        color: Colors.white,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/plant/pfd_nawara.jpg',
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
            ),
            const _PfdFlow(),
          ],
        ),
      ),
      PlantSchemaKind.image when schema.imageBytes != null => Image.memory(
        schema.imageBytes!,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
      ),
      _ => CustomPaint(painter: _GridPainter(scheme.outlineVariant)),
    };

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: onBackgroundTap == null
                  ? null
                  : (d) => onBackgroundTap!(Offset(d.localPosition.dx / width, d.localPosition.dy / height)),
              child: background,
            ),
          ),
          for (final point in state.points.where((p) => p.active))
            if (shown.positionOf(point) case final pos?)
              Positioned(
                left: pos.dx * width - marker / 2,
                top: pos.dy * height - marker / 2,
                child: GestureDetector(
                  onPanUpdate: onMarkerMoved == null
                      ? null
                      : (d) {
                          final current = shown.positionOf(point) ?? pos;
                          onMarkerMoved!(
                            point,
                            Offset(
                              (current.dx + d.delta.dx / width).clamp(0.0, 1.0),
                              (current.dy + d.delta.dy / height).clamp(0.0, 1.0),
                            ),
                          );
                        },
                  child: _Marker(
                    point: point,
                    size: marker,
                    selected: point.id == selectedId,
                    status: controller.status(point, day),
                    onTap: onMarkerTap == null ? null : () => onMarkerTap!(point),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  final SamplePoint point;
  final PlantStatus status;
  final double size;
  final bool selected;
  final VoidCallback? onTap;

  const _Marker({
    required this.point,
    required this.status,
    required this.size,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = plantStatusColor(status, scheme);
    return Tooltip(
      message: '${point.code} — ${point.name}',
      child: Container(
        decoration: selected
            ? BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: scheme.primary, blurRadius: 0, spreadRadius: 4)],
              )
            : null,
        child: Material(
          color: fill,
          shape: CircleBorder(
            side: BorderSide(color: point.circuit.color, width: size * 0.09),
          ),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: FittedBox(
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
          ),
        ),
      ),
    );
  }
}

/// Fond quadrillé d'un schéma vierge.
class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 0.6;
    final major = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    final step = size.width / 40;
    var i = 0;
    for (var x = 0.0; x <= size.width; x += step, i++) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? major : minor);
    }
    i = 0;
    for (var y = 0.0; y <= size.height; y += step, i++) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), i % 5 == 0 ? major : minor);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.color != color;
}

/// Légende : couleurs des circuits (tuyaux du schéma intégré, ou circuits
/// des points placés sur un autre schéma) et des états.
class PlantDiagramLegend extends ConsumerWidget {
  final PlantSchema schema;
  const PlantDiagramLegend({super.key, required this.schema});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final plant = ref.watch(plantControllerProvider);
    String s(String key) => tr(locale, key);

    Widget line(Color color, String label) => Row(
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

    final placed = {
      for (final p in plant.points)
        if (p.active && schema.positionOf(p) != null) p.circuit.id,
    };
    final circuits = plant.circuits.where((c) => placed.contains(c.id));

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final c in circuits) line(c.color, s(c.labelKey)),
        dot(statusOk, s('plantStatusOk')),
        dot(scheme.error, s('plantStatusOut')),
        dot(scheme.outline, s('plantStatusMissing')),
      ],
    );
  }
}

/// Flèches d'écoulement animées du PFD (reprises du PowerPoint : chaque
/// flèche glisse le long de sa conduite, en boucle). Figées si l'utilisateur
/// a demandé de réduire les animations.
class _PfdFlow extends StatefulWidget {
  const _PfdFlow();

  @override
  State<_PfdFlow> createState() => _PfdFlowState();
}

class _PfdFlowState extends State<_PfdFlow> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _FlowPainter(_controller)),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  final Animation<double> animation;
  _FlowPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    // Fondu à l'entrée et à la sortie : pas de saut quand la flèche repart.
    final fade = math.sin(t * math.pi).clamp(0.0, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;
    for (final a in pfdFlowArrows) {
      final w = a.w * size.width * 1.25;
      final h = a.h * size.width * 1.25;
      canvas.save();
      canvas.translate((a.cx + a.dx * t) * size.width, (a.cy + a.dy * t) * size.height);
      canvas.rotate(a.rot * math.pi / 180);
      paint.color = Color(a.color).withValues(alpha: 0.35 + 0.65 * fade);
      canvas.drawPath(
        Path()
          ..moveTo(0, -h / 2)
          ..lineTo(w / 2, h / 2)
          ..lineTo(-w / 2, h / 2)
          ..close(),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) => false;
}
