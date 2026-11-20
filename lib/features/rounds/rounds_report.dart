import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/well_round.dart';

const _slate = PdfColor.fromInt(0xFF44546A);
const _blue = PdfColor.fromInt(0xFF5B9BD5);
const _yellow = PdfColor.fromInt(0xFFFFFF00);
const _greyCell = PdfColor.fromInt(0xFFD9D9D9);
const _border = PdfColor.fromInt(0xFF1F1F1F);

/// Une colonne du tableau : [group] seul (cellule sur toute la hauteur) ou
/// [group] avec des sous-colonnes ([keys] / [subs]).
class _Col {
  final String group;
  final List<String> keys;
  final List<String> subs;
  const _Col(this.group, this.keys, [this.subs = const []]);
}

const _cols = [
  _Col('WHP', ['whp_gauge', 'whp_transmitter'], ['Gauge (Bar)', 'Transmitter (Bar)']),
  _Col('Csg "A" Annuls Pressure (Bar)', ['csg_a']),
  _Col('Csg "B" Annuls Pressure (Bar)', ['csg_b']),
  _Col('Csg "C" Annuls Pressure (Bar)', ['csg_c']),
  _Col('SCSSV Pressure (Bar)', ['scssv']),
  _Col('Flow Line Pressure (Bar)', ['flowline_pressure']),
  _Col('Temp U/S choke (°C)', ['temp_us_choke']),
  _Col('Temp D/S choke (°C)', ['temp_ds_choke']),
  _Col('Choke opening (%)', ['choke_opening']),
  _Col('Methanol MOV Opening (%)', ['methanol_mov']),
  _Col('WHCP', ['whcp_n2_bottle', 'whcp_n2_pressure'], ['N2 Bottle (Bar)', 'N2 pressure (Bar)']),
  _Col('SDV N2 pressure (Bar)', ['sdv_n2_pressure']),
  _Col('Hydraulic Oil Level (%)', ['hydraulic_oil_level']),
  _Col('Corrosion Inhibitor level (%)', ['corrosion_inhibitor_level']),
  _Col('DH Corrosion Inhibitor level (L/day)', ['dh_corrosion_inhibitor']),
  _Col('Sand filter DP (Bar)', ['sand_filter_dp']),
  _Col('DRAIN PIT LEVEL (%)', ['drain_pit_level']),
  _Col('Status', ['well_status']),
];

String _num(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

pw.Widget _cell(String text, {PdfColor? bg, PdfColor? fg, bool bold = false, double size = 7, pw.Alignment align = pw.Alignment.center, double? height}) {
  return pw.Container(
    height: height,
    alignment: align,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
    decoration: pw.BoxDecoration(color: bg, border: pw.Border.all(color: _border, width: 0.5)),
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: size, color: fg ?? PdfColors.black, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
    ),
  );
}

/// PDF des tournées du jour, présenté comme la feuille Excel de l'opérateur :
/// titre jaune, bandeau bleu avec la date, en-têtes groupés (WHP, WHCP...),
/// puits en gris, état Open / Closed en couleur.
Future<Uint8List> buildRoundsPdf({
  required DateTime day,
  required Map<String, String> wells,
  required List<WellRound> rounds,
  required String Function(String) s,
}) async {
  final doc = pw.Document(title: 'Well Operator Parameters Reading');
  final dateText = DateFormat('dd-MMM-yyyy', 'en').format(day);
  const wellFlex = 14;
  const headH = 40.0;

  pw.Widget header() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: wellFlex,
          child: _cell('', bg: _slate, height: headH * 2),
        ),
        for (final c in _cols)
          pw.Expanded(
            flex: 10 * c.keys.length,
            child: c.subs.isEmpty
                ? _cell(c.group, bg: _slate, fg: PdfColors.white, bold: true, size: 6.5, height: headH * 2)
                : pw.Column(children: [
                    _cell(c.group, bg: _slate, fg: PdfColors.white, bold: true, size: 7, height: headH),
                    pw.Row(children: [
                      for (final sub in c.subs)
                        pw.Expanded(child: _cell(sub, bg: _slate, fg: PdfColors.white, bold: true, size: 6.5, height: headH)),
                    ]),
                  ]),
          ),
      ],
    );
  }

  pw.Widget wellRow(WellRound r) {
    return pw.Row(children: [
      pw.Expanded(
        flex: wellFlex,
        child: _cell(wells[r.wellId] ?? r.wellId, bg: _greyCell, bold: true, size: 7.5, align: pw.Alignment.centerLeft),
      ),
      for (final c in _cols)
        for (final key in c.keys)
          pw.Expanded(
            flex: 10,
            child: () {
              final f = wellRoundFields.firstWhere((x) => x.key == key);
              if (!f.isNumber) {
                final raw = r.values[key];
                final open = raw == 'roundOpen';
                final closed = raw == 'roundClosed';
                return _cell(
                  open ? 'Open' : (closed ? 'Closed' : ''),
                  bold: true,
                  fg: open ? const PdfColor.fromInt(0xFF1E8E3E) : (closed ? const PdfColor.fromInt(0xFFD32F2F) : null),
                );
              }
              return _cell(_num(r.number(key)));
            }(),
          ),
    ]);
  }

  final wellRounds = rounds.where((r) => !r.isSite).toList();
  final siteRounds = rounds.where((r) => r.isSite).toList();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(18),
      build: (context) => [
        pw.Container(
          width: double.infinity,
          color: _yellow,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          alignment: pw.Alignment.center,
          child: pw.Text('Well Operator Parameters Reading', style: const pw.TextStyle(fontSize: 11)),
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          width: 260,
          color: _blue,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text('Daily Operator Readings | $dateText', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 8),
        header(),
        for (final r in wellRounds) wellRow(r),
        if (siteRounds.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Row(children: [
            for (final f in siteRoundFields)
              pw.Expanded(
                child: _cell(f.unit.isEmpty ? s(f.labelKey) : '${s(f.labelKey)} (${f.unit})', bg: _slate, fg: PdfColors.white, bold: true, size: 6.5, height: 34),
              ),
          ]),
          for (final r in siteRounds)
            pw.Row(children: [
              for (final f in siteRoundFields)
                pw.Expanded(
                  child: _cell(
                    f.isNumber ? _num(r.number(f.key)) : s(r.values[f.key]?.toString() ?? ''),
                    size: 7.5,
                    height: 22,
                  ),
                ),
            ]),
        ],
      ],
    ),
  );
  return doc.save();
}
