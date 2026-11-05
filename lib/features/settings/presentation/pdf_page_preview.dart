import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/branding/app_logo.dart';
import '../../../core/export/pdf_export_settings.dart';
import '../../../core/l10n/app_strings.dart' show currentAppName;
import '../../../core/plant/plant_catalog.dart' show PlantCircuit;

const _navy = Color(0xFF0B1E2D);
const _grey = Color(0xFF757575);
const _ok = Color(0xFF2E7D32);
const _out = Color(0xFFC62828);

/// Aperçu en direct d'une page PDF : reproduit la mise en page des vrais
/// exports (en-tête, titre, date, tableaux, courbes, photo, bloc signature,
/// pied de page) d'après les réglages [cfg], sur une page A4 à l'échelle.
class PdfPagePreview extends StatelessWidget {
  final PdfExportSettings cfg;
  final String Function(String) s;
  final String operatorName;

  /// Circuit en cours d'édition ([cfg.circuitId]) : le badge de l'aperçu
  /// reprend son nom et sa couleur au lieu d'un exemple générique, pour
  /// qu'il reflète vraiment le circuit choisi dans « Style par circuit ».
  final PlantCircuit? circuit;
  const PdfPagePreview({
    super.key,
    required this.cfg,
    required this.s,
    required this.operatorName,
    this.circuit,
  });

  bool get _landscape => switch (cfg.orientation) {
    PdfOrientation.landscape => true,
    PdfOrientation.portrait => false,
    PdfOrientation.auto => !cfg.kind.isPlant,
  };

  @override
  Widget build(BuildContext context) {
    final w = _landscape ? 842.0 : 595.0;
    final h = _landscape ? 595.0 : 842.0;
    return AspectRatio(
      aspectRatio: w / h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: w,
              height: h,
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  height: 1.25,
                  decoration: TextDecoration.none,
                ),
                child: _Page(
                  cfg: cfg,
                  s: s,
                  operatorName: operatorName,
                  width: w,
                  circuit: circuit,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final PdfExportSettings cfg;
  final String Function(String) s;
  final String operatorName;
  final double width;
  final PlantCircuit? circuit;
  const _Page({
    required this.cfg,
    required this.s,
    required this.operatorName,
    required this.width,
    this.circuit,
  });

  double get k => cfg.textScale;
  Color get accent => Color(cfg.accentArgb);

  String get _title {
    final custom = cfg.reportTitle.trim();
    if (custom.isNotEmpty) return custom;
    return switch (cfg.kind) {
      PdfReportKind.allCircuits => s('plantReportTitle'),
      PdfReportKind.samples => s('plantSampleReportTitle'),
      PdfReportKind.tables => s('navAlerts'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final stamp = cfg.stamp();
    final dateGenerated = '${s('plantReportGenerated')} $stamp';
    final footerParts = [
      if (cfg.datePlacement == PdfDatePlacement.footer) dateGenerated,
      if (cfg.showOperator) operatorName,
      if (cfg.footerText.trim().isNotEmpty) cfg.footerText.trim(),
    ];
    final logo = currentAppLogo;

    final body = <Widget>[
      if (cfg.showTitle)
        Text(
          _title,
          style: TextStyle(
            fontSize: (cfg.kind.isPlant ? 18 : 16) * k,
            fontWeight: FontWeight.w800,
            color: _navy,
          ),
        ),
      if (cfg.kind.isPlant && cfg.showReportNumber)
        Text(
          '${s('plantReportNumberLabel')} 289/26',
          style: TextStyle(
            fontSize: 12 * k,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
      if (cfg.datePlacement == PdfDatePlacement.top)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            dateGenerated,
            style: TextStyle(fontSize: 10 * k, color: _grey),
          ),
        ),
      const SizedBox(height: 14),
      if (cfg.kind.isPlant) ..._plantBody() else ..._tablesBody(),
    ];

    final page = Padding(
      padding: EdgeInsets.symmetric(horizontal: 32 * cfg.marginScale, vertical: 28 * cfg.marginScale),
      child: Stack(
        children: [
          Positioned.fill(
            bottom: 26,
            child: ClipRect(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (!cfg.logoRight && cfg.showLogo) ...[
                          logo != null
                              ? Image.memory(
                                  logo,
                                  height: 30,
                                  errorBuilder: (_, _, _) => const _LogoMock(),
                                )
                              : const _LogoMock(),
                          const SizedBox(width: 8),
                        ],
                        if (cfg.showAppName)
                          Flexible(
                            child: Text(
                              currentAppName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 12 * k,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (cfg.kind == PdfReportKind.tables && cfg.showTitle)
                          Flexible(
                            child: Text(
                              _title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: _grey, fontSize: 9 * k),
                            ),
                          ),
                        if (cfg.datePlacement == PdfDatePlacement.header) ...[
                          if (cfg.kind == PdfReportKind.tables && cfg.showTitle)
                            const SizedBox(width: 10),
                          Text(
                            stamp,
                            style: TextStyle(
                              color: cfg.kind.isPlant ? _grey : _navy,
                              fontSize: 9 * k,
                              fontWeight: cfg.kind.isPlant
                                  ? FontWeight.w400
                                  : FontWeight.w700,
                            ),
                          ),
                        ],
                        if (cfg.logoRight && cfg.showLogo) ...[
                          const SizedBox(width: 8),
                          logo != null
                              ? Image.memory(
                                  logo,
                                  height: 30,
                                  errorBuilder: (_, _, _) => const _LogoMock(),
                                )
                              : const _LogoMock(),
                        ],
                      ],
                    ),
                    if (cfg.headerText.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          cfg.headerText.trim(),
                          style: TextStyle(color: _grey, fontSize: 8.5 * k),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Divider(color: accent, thickness: 1.5, height: 1),
                    ),
                    ...body,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    footerParts.join(' - '),
                    style: TextStyle(color: _grey, fontSize: 8 * k),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (cfg.showPageNumbers)
                  Text(
                    '1 / 1',
                    style: TextStyle(color: _grey, fontSize: 8 * k),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    final wm = cfg.watermark.trim();
    if (wm.isEmpty) return page;
    return Stack(
      children: [
        page,
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Transform.rotate(
                angle: -0.62,
                child: Opacity(
                  opacity: 0.12,
                  child: Text(
                    wm.toUpperCase(),
                    style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: _grey),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _plantBody() {
    final analyses = cfg.allAnalyses ? 2 : 1;
    final showCharts = cfg.charts != PdfChartsPosition.hidden;
    return [
      if (cfg.showCircuitBadge) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: circuit?.color ?? const Color(0xFF1E88E5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            (circuit != null ? s(circuit!.labelKey) : s('plantProfileWater')).toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11 * k,
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
      Row(
        children: [
          Flexible(
            child: Text(
              'NCO-440-NCO-01 - CPI separator',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5 * k),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '(CPI separator)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _grey, fontSize: 9 * k),
            ),
          ),
          const Spacer(),
          Text(
            s('plantStatusOut'),
            style: TextStyle(
              color: _out,
              fontWeight: FontWeight.w800,
              fontSize: 9.5 * k,
            ),
          ),
        ],
      ),
      if (showCharts && cfg.charts == PdfChartsPosition.before)
        _chart('TPH (mg/L)'),
      for (var i = 0; i < analyses; i++) ...[
        const SizedBox(height: 6),
        if (cfg.showSamplingTime)
          Text(
            '${s('plantSamplingTime')}: ${i == 0 ? '06:30' : '19:00'}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 9 * k,
              color: _navy,
            ),
          ),
        const SizedBox(height: 3),
        _MockTable(
          accent: accent,
          header: Color(cfg.headerArgb),
          style: cfg.tableStyle,
          k: k,
          headers: [
            s('plantColTest'),
            s('colUnit'),
            s('plantColResults'),
            if (cfg.showLimit) s('plantColSpec'),
            if (cfg.showStatus) s('colStatus'),
          ],
          rows: [
            [
              s('plantParamTph'),
              'mg/L',
              i == 0 ? '4100' : '3650',
              if (cfg.showLimit) '<= 20.00',
              if (cfg.showStatus) s('plantStatusOut'),
            ],
            [
              s('plantParamSalinity'),
              'g/L NaCl',
              '12.0',
              if (cfg.showLimit) '<= 266.0',
              if (cfg.showStatus) s('plantStatusOk'),
            ],
            [
              s('plantParamPh'),
              '',
              '7.1',
              if (cfg.showLimit) '-',
              if (cfg.showStatus) '-',
            ],
          ],
          okColumn: cfg.showStatus ? (cfg.showLimit ? 4 : 3) : -1,
          valueColumn: 2,
          rowOut: const [true, false, null],
          highlightOutOfRange: cfg.highlightOutOfRange,
        ),
        if (cfg.showDetails)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '${s('plantSourceLab')}${operatorName.isEmpty ? '' : ' - $operatorName'}',
              style: TextStyle(color: _grey, fontSize: 8.5 * k),
            ),
          ),
        if (cfg.showPhoto && i == 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: Container(
                width: 220,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E2DD),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCFC5BE)),
                ),
                child: const Icon(Icons.photo_outlined, color: _grey, size: 30),
              ),
            ),
          ),
      ],
      if (showCharts && cfg.charts == PdfChartsPosition.after)
        _chart('TPH (mg/L)'),
      if (cfg.showSignature) ...[
        const SizedBox(height: 20),
        Text(
          '${s('plantReportDateLabel')}: ${DateFormat('dd-MM-yyyy').format(DateTime.now())}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Text(
          '${operatorName.isEmpty ? '-' : operatorName}: ${cfg.signatureRole.trim().isEmpty ? s('plantReportRole') : cfg.signatureRole.trim()}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
        ),
      ],
    ];
  }

  List<Widget> _tablesBody() {
    final showCharts = cfg.charts != PdfChartsPosition.hidden;
    return [
      if (showCharts && cfg.charts == PdfChartsPosition.before)
        _chart(s('plantParamTph')),
      const SizedBox(height: 8),
      Text(
        s('navAlerts'),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12 * k,
          color: _navy,
        ),
      ),
      const SizedBox(height: 6),
      _MockTable(
        accent: accent,
        header: Color(cfg.headerArgb),
        style: cfg.tableStyle,
        k: k,
        headers: [
          s('colDate'),
          s('plantColParam'),
          s('colValue'),
          s('colUnit'),
          s('colStatus'),
        ],
        rows: [
          [
            '25/10/2026',
            s('plantParamTph'),
            '4100',
            'mg/L',
            s('plantStatusOut'),
          ],
          [
            '25/10/2026',
            s('plantParamSalinity'),
            '12.0',
            'g/L',
            s('plantStatusOk'),
          ],
          ['24/10/2026', s('plantParamPh'), '7.1', '', s('plantStatusOk')],
          [
            '23/10/2026',
            s('plantParamTph'),
            '3650',
            'mg/L',
            s('plantStatusOut'),
          ],
        ],
        okColumn: 4,
      ),
      if (showCharts && cfg.charts == PdfChartsPosition.after)
        _chart(s('plantParamTph')),
    ];
  }

  Widget _chart(String title) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 10 * k,
            color: _navy,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 80,
          width: double.infinity,
          child: CustomPaint(painter: _LinePainter(accent)),
        ),
      ],
    ),
  );
}

class _LogoMock extends StatelessWidget {
  const _LogoMock();

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: _navy,
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Icon(Icons.water_drop, color: Colors.white, size: 18),
  );
}

class _MockTable extends StatelessWidget {
  final double k;
  final List<String> headers;
  final List<List<String>> rows;
  final int okColumn;
  final Color accent;
  final Color header;

  /// 0 en-tête plein, 1 filets, 2 lignes alternées.
  final int style;

  /// Colonne « Valeur » et, pour chaque ligne, vrai = hors seuil, faux = dans
  /// les seuils, nul = pas de seuil — coloriée en vert/rouge comme le vrai
  /// PDF quand [highlightOutOfRange] est actif.
  final int valueColumn;
  final List<bool?>? rowOut;
  final bool highlightOutOfRange;

  const _MockTable({
    required this.k,
    required this.headers,
    required this.rows,
    required this.accent,
    required this.header,
    required this.style,
    this.okColumn = -1,
    this.valueColumn = -1,
    this.rowOut,
    this.highlightOutOfRange = true,
  });

  @override
  Widget build(BuildContext context) {
    final filled = style == 0 || style == 2;
    Widget cell(String text, int col, {bool head = false, String? status, int? rowIndex}) {
      final isStatus = !head && col == okColumn;
      final rowValueOut = rowIndex == null || rowOut == null || rowIndex >= rowOut!.length ? null : rowOut![rowIndex];
      final isValue = !head && col == valueColumn && highlightOutOfRange && rowValueOut != null;
      final color = head
          ? (filled ? Colors.white : header)
          : isStatus
          ? (text == status ? _out : _ok)
          : isValue
          ? (rowValueOut! ? _out : _ok)
          : Colors.black;
      return Expanded(
        flex: col == 0 ? 3 : 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: col == 0 ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              fontSize: 8.5 * k,
              fontWeight: head || isStatus || isValue ? FontWeight.w800 : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      );
    }

    final outText = rows.isEmpty || okColumn < 0 ? null : rows.first[okColumn];
    return Container(
      decoration: BoxDecoration(border: style == 1 ? null : Border.all(color: const Color(0xFFBDBDBD), width: 0.5)),
      child: Column(
        children: [
          Container(
            decoration: filled
                ? BoxDecoration(color: header)
                : (style == 3 ? null : BoxDecoration(border: Border(bottom: BorderSide(color: accent, width: 1.4)))),
            child: Row(children: [for (var i = 0; i < headers.length; i++) cell(headers[i], i, head: true)]),
          ),
          for (var r = 0; r < rows.length; r++)
            Container(
              decoration: BoxDecoration(
                color: style == 2 && r.isEven ? accent.withValues(alpha: 0.08) : null,
                border: const Border(top: BorderSide(color: Color(0xFFBDBDBD), width: 0.5)),
              ),
              child: Row(
                children: [for (var i = 0; i < rows[r].length; i++) cell(rows[r][i], i, status: outText, rowIndex: r)],
              ),
            ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final Color color;
  _LinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = const Color(0xFFBDBDBD)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axis,
    );
    canvas.drawLine(Offset.zero, Offset(0, size.height), axis);
    final pts = [0.7, 0.55, 0.62, 0.35, 0.45, 0.2, 0.3];
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final p = Offset(size.width * i / (pts.length - 1), size.height * pts[i]);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
