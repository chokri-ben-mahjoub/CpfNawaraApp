import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/export/pdf_style_set.dart';

const _swatches = <int>[
  0xFF000000,
  0xFF0B1E2D,
  0xFF757575,
  0xFFFFFFFF,
  0xFFFF7A33,
  0xFF1E88E5,
  0xFF2E7D32,
  0xFF8E24AA,
  0xFFC62828,
  0xFF00897B,
];

/// Éditeur du style fin des PDF (polices, tailles, couleurs, alignements,
/// fonds, bordures, espacements). Sans état propre : tout vient de [style] et
/// remonte par [onChanged].
class PdfStyleEditor extends StatelessWidget {
  final PdfStyleSet style;
  final String Function(String) s;
  final ValueChanged<PdfStyleSet> onChanged;
  final VoidCallback onReset;
  final VoidCallback onApplyAll;

  const PdfStyleEditor({
    super.key,
    required this.style,
    required this.s,
    required this.onChanged,
    required this.onReset,
    required this.onApplyAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textBlock(s('pdfStyleReportTitle'), style.reportTitle, (v) => onChanged(style.copyWith(reportTitle: v)), autoSize: false),
        _textBlock(s('pdfStyleTableTitle'), style.tableTitle, (v) => onChanged(style.copyWith(tableTitle: v)), autoSize: false),
        _textBlock(s('pdfStyleColHeader'), style.columnHeader, (v) => onChanged(style.copyWith(columnHeader: v)), autoSize: true),
        _textBlock(s('pdfStyleCell'), style.cell, (v) => onChanged(style.copyWith(cell: v)), autoSize: true),
        _frameBlock(),
        _textBlock(s('pdfStylePageHeader'), style.pageHeader, (v) => onChanged(style.copyWith(pageHeader: v)), autoSize: true, plain: true),
        _textBlock(s('pdfStylePageFooter'), style.pageFooter, (v) => onChanged(style.copyWith(pageFooter: v)), autoSize: true, plain: true),
        _textBlock(s('pdfStyleSecondary'), style.secondary, (v) => onChanged(style.copyWith(secondary: v)), autoSize: true, plain: true),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(onPressed: onReset, icon: const Icon(Icons.restore), label: Text(s('pdfStyleReset'))),
            OutlinedButton.icon(onPressed: onApplyAll, icon: const Icon(Icons.copy_all_outlined), label: Text(s('pdfStyleApplyAll'))),
          ],
        ),
      ],
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(t, style: const TextStyle(fontSize: 13)),
  );

  Widget _textBlock(String title, PdfTextStyleSpec v, ValueChanged<PdfTextStyleSpec> set, {required bool autoSize, bool plain = false}) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      children: [
        _label(s('pdfStyleFont')),
        Wrap(
          spacing: 8,
          children: [
            for (final f in PdfFontFamily.values)
              ChoiceChip(
                label: Text(const {PdfFontFamily.helvetica: 'Helvetica', PdfFontFamily.times: 'Times', PdfFontFamily.courier: 'Courier'}[f]!),
                selected: v.family == f,
                showCheckmark: false,
                onSelected: (_) => set(v.copyWith(family: f)),
              ),
          ],
        ),
        _label(s('pdfStyleSize')),
        Row(
          children: [
            if (autoSize)
              FilterChip(
                label: Text(s('pdfStyleAuto')),
                selected: v.size == null,
                onSelected: (on) => set(on ? v.copyWith(clearSize: true) : v.copyWith(size: 9)),
              ),
            Expanded(
              child: Slider(
                min: 6,
                max: 32,
                divisions: 52,
                label: v.size?.toStringAsFixed(1),
                value: (v.size ?? 9).clamp(6, 32).toDouble(),
                onChanged: v.size == null && autoSize ? null : (x) => set(v.copyWith(size: x)),
              ),
            ),
            SizedBox(width: 40, child: Text(v.size == null ? s('pdfStyleAuto') : v.size!.toStringAsFixed(1), textAlign: TextAlign.end)),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(label: Text(s('pdfStyleBold')), selected: v.bold, onSelected: (on) => set(v.copyWith(bold: on))),
            FilterChip(label: Text(s('pdfStyleItalic')), selected: v.italic, onSelected: (on) => set(v.copyWith(italic: on))),
          ],
        ),
        if (!plain) _label(s('pdfStyleAlign')),
        if (!plain)
        Wrap(
          spacing: 8,
          children: [
            for (final (a, key) in [
              (PdfTextAlign.left, 'pdfStyleLeft'),
              (PdfTextAlign.center, 'pdfStyleCenter'),
              (PdfTextAlign.right, 'pdfStyleRight'),
            ])
              ChoiceChip(
                label: Text(s(key)),
                selected: v.align == a,
                showCheckmark: false,
                onSelected: (_) => set(v.copyWith(align: a)),
              ),
          ],
        ),
        _label(s('pdfStyleColor')),
        _colors(v.colorArgb, (c) => set(c == null ? v.copyWith(clearColor: true) : v.copyWith(colorArgb: c))),
      ],
    );
  }

  Widget _colors(int? current, ValueChanged<int?> pick, {bool allowAuto = true}) {
    Widget dot(int? argb, {VoidCallback? onTap}) {
      final selected = current == argb;
      return InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap ?? () => pick(argb),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: argb == null ? null : Color(argb),
            border: Border.all(color: selected ? Colors.blueGrey.shade900 : Colors.grey, width: selected ? 3 : 1),
          ),
          child: argb == null ? Text(s('pdfStyleAuto'), style: const TextStyle(fontSize: 9)) : null,
        ),
      );
    }

    final custom = current != null && !_swatches.contains(current);
    return Builder(
      builder: (context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (allowAuto) dot(null),
          for (final c in _swatches) dot(c),
          if (custom) dot(current),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () async {
              final picked = await showPdfColorPickerDialog(context, current ?? 0xFF000000, s);
              if (picked != null) pick(picked);
            },
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey),
                gradient: const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red]),
              ),
              child: const Icon(Icons.add, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> set, {String? auto, VoidCallback? onAuto}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        Row(
          children: [
            if (onAuto != null)
              FilterChip(label: Text(s('pdfStyleAuto')), selected: auto != null, onSelected: (_) => onAuto()),
            Expanded(
              child: Slider(
                min: min,
                max: max,
                divisions: ((max - min) * 2).round(),
                value: value.clamp(min, max).toDouble(),
                onChanged: auto != null ? null : set,
              ),
            ),
            SizedBox(width: 40, child: Text(auto ?? value.toStringAsFixed(1), textAlign: TextAlign.end)),
          ],
        ),
      ],
    );
  }

  Widget _frameBlock() {
    final t = style.table;
    void set(PdfTableStyleSpec n) => onChanged(style.copyWith(table: n));
    final autoPad = t.padH == null && t.padV == null;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(s('pdfStyleFrame'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      children: [
        _label(s('pdfStyleHeaderBg')),
        _colors(t.headerBgArgb, (c) => set(c == null ? t.copyWith(clearHeaderBg: true) : t.copyWith(headerBgArgb: c))),
        _label(s('pdfStyleBorderColor')),
        _colors(t.borderArgb, (c) => set(t.copyWith(borderArgb: c)), allowAuto: false),
        _slider(s('pdfStyleBorderWidth'), t.borderWidth, 0, 3, (x) => set(t.copyWith(borderWidth: x))),
        _slider(
          s('pdfStylePadH'),
          t.padH ?? 5,
          0,
          20,
          (x) => set(t.copyWith(padH: x, padV: t.padV ?? 5)),
          auto: autoPad ? s('pdfStyleAuto') : null,
          onAuto: () => set(autoPad ? t.copyWith(padH: 5, padV: 5) : t.copyWith(clearPadding: true)),
        ),
        if (!autoPad) _slider(s('pdfStylePadV'), t.padV ?? 5, 0, 20, (x) => set(t.copyWith(padV: x, padH: t.padH ?? 5))),
        _slider(s('pdfStyleSpaceBefore'), t.spaceBeforeTable, 0, 40, (x) => set(t.copyWith(spaceBeforeTable: x))),
        _slider(s('pdfStyleSpaceAfter'), t.spaceAfterTitle, 0, 30, (x) => set(t.copyWith(spaceAfterTitle: x))),
      ],
    );
  }
}

/// Ouvre une roue de couleurs (teinte/saturation + luminosité) avec un champ
/// hexadécimal, pour choisir n'importe quelle couleur plutôt que les 10
/// pastilles prédéfinies. `null` si l'utilisateur annule.
Future<int?> showPdfColorPickerDialog(BuildContext context, int initialArgb, String Function(String) s) {
  return showDialog<int>(
    context: context,
    builder: (context) => _PdfColorPickerDialog(initialArgb: initialArgb, s: s),
  );
}

class _PdfColorPickerDialog extends StatefulWidget {
  final int initialArgb;
  final String Function(String) s;
  const _PdfColorPickerDialog({required this.initialArgb, required this.s});

  @override
  State<_PdfColorPickerDialog> createState() => _PdfColorPickerDialogState();
}

class _PdfColorPickerDialogState extends State<_PdfColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.initialArgb));
  late final TextEditingController _hex = TextEditingController(text: _hexOf(_hsv.toColor()));

  static String _hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _setColor(Color c, {bool fromHex = false}) {
    setState(() {
      _hsv = HSVColor.fromColor(c);
      if (!fromHex) _hex.text = _hexOf(c);
    });
  }

  void _setFromWheel(Offset local, double size) {
    final center = Offset(size / 2, size / 2);
    final v = local - center;
    final radius = size / 2;
    final dist = v.distance.clamp(0, radius);
    // Convention cohérente avec le placement du curseur (cos, -sin) plus bas.
    final angle = (math.atan2(-v.dy, v.dx) * 180 / math.pi + 360) % 360;
    _setColor(HSVColor.fromAHSV(1, angle, (dist / radius).clamp(0, 1), _hsv.value).toColor());
  }

  @override
  Widget build(BuildContext context) {
    String s(String k) => widget.s(k);
    final color = _hsv.toColor();
    const wheelSize = 220.0;
    return AlertDialog(
      title: Text(s('pdfColorPickerTitle')),
      content: SizedBox(
        width: wheelSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onPanDown: (d) => _setFromWheel(d.localPosition, wheelSize),
              onPanUpdate: (d) => _setFromWheel(d.localPosition, wheelSize),
              child: Container(
                width: wheelSize,
                height: wheelSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 1), Colors.white.withValues(alpha: 0)]),
                  ),
                  child: Align(
                    alignment: Alignment(
                      _hsv.saturation * math.cos(_hsv.hue * math.pi / 180),
                      -_hsv.saturation * math.sin(_hsv.hue * math.pi / 180),
                    ),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(s('pdfColorBrightness'), style: const TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _hsv.value,
                    onChanged: (v) => _setColor(_hsv.withValue(v).toColor()),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: color, border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(6)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: const InputDecoration(isDense: true, prefixText: '#'),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (v) {
                      final hex = v.replaceAll('#', '').trim();
                      if (hex.length == 6) {
                        final parsed = int.tryParse(hex, radix: 16);
                        if (parsed != null) _setColor(Color(0xFF000000 | parsed), fromHex: true);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s('cancel'))),
        FilledButton(onPressed: () => Navigator.of(context).pop(color.toARGB32()), child: Text(s('confirm'))),
      ],
    );
  }
}
