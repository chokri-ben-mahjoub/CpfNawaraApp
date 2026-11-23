import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'machine_history.dart';
import 'machine_test.dart';

PdfColor _statusColor(MachineStatus s) => switch (s) {
      MachineStatus.ok => PdfColors.green700,
      MachineStatus.warning => PdfColors.amber800,
      MachineStatus.incomplete => PdfColors.orange700,
      MachineStatus.fault => PdfColors.red700,
      MachineStatus.notTested => PdfColors.grey600,
    };

String _num(double? v, [int d = 4]) => v == null ? '-' : v.toStringAsFixed(d);

/// Certificat de contrôle d'une machine : identification, conclusion, résultats
/// par standard, historique des imports et zones de signature.
Future<Uint8List> buildMachineCertificatePdf(MachineEntry e, {String labName = 'CPF Laboratory NAWARA'}) async {
  final m = e.result;
  final fmt = DateFormat('dd/MM/yyyy');
  final doc = pw.Document(title: 'Certificat ${m.machine}', author: labName);
  final color = _statusColor(m.status);

  pw.Widget cell(String t, {bool bold = false, PdfColor? c}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: c)),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('$labName - page ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ),
    build: (ctx) => [
      pw.Text(labName, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.Text('CERTIFICAT DE CONTROLE DE MACHINE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),
      pw.Text(m.machine, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.Text('Édité le ${fmt.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 12),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: color, width: 2), borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(m.status.label.toUpperCase(), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: color)),
          pw.SizedBox(height: 4),
          pw.Text(m.verdict, style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Action : ${m.recommendation}', style: const pw.TextStyle(fontSize: 10)),
        ]),
      ),
      pw.SizedBox(height: 10),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5), children: [
        pw.TableRow(children: [
          cell('Mesures saisies / prévues', bold: true), cell('${m.measured} / ${m.total}'),
          cell('Conformité', bold: true), cell(m.conformityRate == null ? '-' : '${m.conformityRate!.toStringAsFixed(1)} %'),
        ]),
        pw.TableRow(children: [
          cell('Hors tolérance', bold: true), cell('${m.failed}'),
          cell('En attente', bold: true), cell('${m.pending}'),
        ]),
        pw.TableRow(children: [
          cell('Dernière calibration', bold: true), cell(e.due.last == null ? 'Jamais' : fmt.format(e.due.last!)),
          cell('Prochaine échéance', bold: true), cell(e.due.due == null ? '-' : '${fmt.format(e.due.due!)} (${e.settings.intervalDays} j)'),
        ]),
      ]),
      for (final sh in m.sheets) ...[
        pw.SizedBox(height: 14),
        pw.Text('${sh.sheet} - ${sh.status.label}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.2), 2: pw.FlexColumnWidth(1.2), 3: pw.FlexColumnWidth(1.2), 4: pw.FlexColumnWidth(1.2), 5: pw.FlexColumnWidth(1.6)},
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [cell('Standard', bold: true), cell('Référence', bold: true), cell('Tolérance', bold: true), cell('Écart moyen', bold: true), cell('Pire écart', bold: true), cell('Résultat', bold: true)],
            ),
            for (final s in sh.standards)
              pw.TableRow(children: [
                cell(s.standard),
                cell('${s.reference}'),
                cell(s.tolerance.text),
                cell(_num(s.meanError)),
                cell(_num(s.worstError)),
                cell(s.status.label, bold: true, c: _statusColor(s.status)),
              ]),
          ],
        ),
      ],
      pw.SizedBox(height: 14),
      pw.Text('Historique des imports', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5), children: [
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
          cell('Import', bold: true), cell('Mesures saisies', bold: true), cell('Statut', bold: true), cell('Conformité', bold: true),
        ]),
        for (final h in e.history.reversed.take(12)) ...[
          () {
            final r = evaluateCalibration(h.points, overrides: {
              for (final t in e.settings.tolerances.entries) toleranceKey(e.machine, t.key): t.value,
            }).first;
            return pw.TableRow(children: [
              cell(DateFormat('dd/MM/yyyy HH:mm').format(h.importedAt)),
              cell('${r.measured}/${r.total}'),
              cell(r.status.label, c: _statusColor(r.status)),
              cell(r.conformityRate == null ? '-' : '${r.conformityRate!.toStringAsFixed(0)} %'),
            ]);
          }(),
        ],
      ]),
      pw.SizedBox(height: 36),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Container(width: 220, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.8))), padding: const pw.EdgeInsets.only(top: 4), child: pw.Text('Réalisé par', style: const pw.TextStyle(fontSize: 9))),
        pw.Container(width: 220, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.8))), padding: const pw.EdgeInsets.only(top: 4), child: pw.Text('Vérifié par', style: const pw.TextStyle(fontSize: 9))),
      ]),
    ],
  ));
  return doc.save();
}
