import 'package:flutter/material.dart';

/// Jauge horizontale montrant où se situe [value] par rapport au seuil
/// [min]–[max] : bande claire = plage attendue, point coloré = valeur
/// actuelle (vert si dans la plage, rouge sinon — y compris si le point
/// déborde visuellement du côté hors seuil).
class ThresholdGauge extends StatelessWidget {
  final double min;
  final double max;
  final double value;

  const ThresholdGauge({super.key, required this.min, required this.max, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final span = (max - min) <= 0 ? 1.0 : (max - min);
    final margin = span * 0.3;
    final trackMin = min - margin;
    final trackMax = max + margin;
    final trackSpan = (trackMax - trackMin) <= 0 ? 1.0 : (trackMax - trackMin);

    final safeStart = ((min - trackMin) / trackSpan).clamp(0.0, 1.0);
    final safeEnd = ((max - trackMin) / trackSpan).clamp(0.0, 1.0);
    final valuePos = ((value - trackMin) / trackSpan).clamp(0.0, 1.0);
    final inRange = value >= min && value <= max;
    final markerColor = inRange ? Colors.green.shade600 : scheme.error;

    return SizedBox(
      height: 22,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          const markerSize = 14.0;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 7,
                left: 0,
                right: 0,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Positioned(
                top: 7,
                left: width * safeStart,
                width: (width * (safeEnd - safeStart)).clamp(0.0, width),
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Positioned(
                top: 3,
                left: (width * valuePos - markerSize / 2).clamp(0.0, width - markerSize),
                child: Container(
                  width: markerSize,
                  height: markerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: markerColor,
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
