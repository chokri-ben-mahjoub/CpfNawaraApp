import 'package:flutter/material.dart';

import '../../../core/export/pdf_style_set.dart';

/// Un élément positionnable à la souris sur la maquette de page de garde
/// (logo, bloc titre, filigrane).
class _CanvasItem {
  final String id;
  final String label;
  final IconData icon;
  final PdfElementLayout? layout;
  final ValueChanged<PdfElementLayout> onChanged;
  final VoidCallback onReset;

  const _CanvasItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.layout,
    required this.onChanged,
    required this.onReset,
  });
}

/// Maquette de la page de garde (proportions A4) où déplacer à la souris et
/// redimensionner (poignée en bas à droite de chaque pastille) le logo, le
/// bloc titre et le filigrane. Tant qu'un élément n'a pas été touché, il
/// garde sa position historique (pastille affichée au centre par défaut,
/// repère visuel seulement — le PDF réel ne bouge que si on la déplace).
class PdfLayoutCanvas extends StatelessWidget {
  final PdfStyleSet style;
  final ValueChanged<PdfStyleSet> onChanged;
  final String Function(String) s;

  const PdfLayoutCanvas({super.key, required this.style, required this.onChanged, required this.s});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      _CanvasItem(
        id: 'logo',
        label: s('pdfLayoutLogo'),
        icon: Icons.image_outlined,
        layout: style.logoLayout,
        onChanged: (l) => onChanged(style.copyWith(logoLayout: l)),
        onReset: () => onChanged(style.copyWith(clearLogoLayout: true)),
      ),
      _CanvasItem(
        id: 'title',
        label: s('pdfLayoutTitle'),
        icon: Icons.title,
        layout: style.titleLayout,
        onChanged: (l) => onChanged(style.copyWith(titleLayout: l)),
        onReset: () => onChanged(style.copyWith(clearTitleLayout: true)),
      ),
      _CanvasItem(
        id: 'watermark',
        label: s('pdfLayoutWatermark'),
        icon: Icons.opacity_outlined,
        layout: style.watermarkLayout,
        onChanged: (l) => onChanged(style.copyWith(watermarkLayout: l)),
        onReset: () => onChanged(style.copyWith(clearWatermarkLayout: true)),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s('pdfLayoutHint'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.3)),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.clamp(180, 320).toDouble();
            final height = width / 0.707; // ratio A4
            return Center(
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: scheme.outlineVariant, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final item in items) _marker(context, item, width, height),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in items)
              ActionChip(
                avatar: Icon(item.icon, size: 16),
                label: Text('${item.label}${item.layout == null ? '' : ' ✓'}'),
                onPressed: item.layout == null ? null : item.onReset,
                tooltip: item.layout == null ? s('pdfLayoutDefault') : s('pdfLayoutResetOne'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _marker(BuildContext context, _CanvasItem item, double canvasW, double canvasH) {
    final layout = item.layout ?? const PdfElementLayout();
    const baseSize = 46.0;
    final size = (baseSize * layout.scale).clamp(24.0, 140.0);
    final left = (layout.dx * canvasW - size / 2).clamp(-size / 2, canvasW - size / 2);
    final top = (layout.dy * canvasH - size / 2).clamp(-size / 2, canvasH - size / 2);
    final color = item.layout == null ? Colors.blueGrey : Colors.deepOrange;

    void moveBy(Offset delta) {
      final dx = (layout.dx + delta.dx / canvasW).clamp(0.0, 1.0);
      final dy = (layout.dy + delta.dy / canvasH).clamp(0.0, 1.0);
      item.onChanged(layout.copyWith(dx: dx, dy: dy));
    }

    void resizeBy(Offset delta) {
      final next = (layout.scale + delta.dx / baseSize).clamp(0.3, 3.0);
      item.onChanged(layout.copyWith(scale: next));
    }

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (d) => moveBy(d.delta),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            border: Border.all(color: color, width: item.layout == null ? 1 : 2, style: item.layout == null ? BorderStyle.solid : BorderStyle.solid),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(item.icon, size: (size * 0.4).clamp(14, 36), color: color),
              ),
              Positioned(
                right: -6,
                bottom: -6,
                child: GestureDetector(
                  onPanUpdate: (d) => resizeBy(d.delta),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Icon(Icons.open_in_full, size: 10, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
