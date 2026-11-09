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

  Widget _textBlock(String title, PdfTextStyleSpec v, ValueChanged<PdfTextStyleSpec> set, {required bool autoSize}) {
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
        _label(s('pdfStyleAlign')),
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
    Widget dot(int? argb) {
      final selected = current == argb;
      return InkWell(
        customBorder: const CircleBorder(),
        onTap: () => pick(argb),
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

    return Wrap(spacing: 8, runSpacing: 8, children: [if (allowAuto) dot(null), for (final c in _swatches) dot(c)]);
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
