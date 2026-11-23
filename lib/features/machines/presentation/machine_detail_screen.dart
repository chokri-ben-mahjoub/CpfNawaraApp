import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/export/export_format_sheet.dart';
import '../../../core/export/export_service.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/machines/control_chart.dart';
import '../../../core/machines/machine_certificate_pdf.dart';
import '../../../core/machines/machine_history.dart';
import '../../../core/machines/machine_schedule.dart';
import '../../../core/machines/machine_test.dart';

Color machineStatusColor(MachineStatus s) => switch (s) {
      MachineStatus.ok => const Color(0xFF2E9E5B),
      MachineStatus.warning => const Color(0xFFE0A100),
      MachineStatus.incomplete => const Color(0xFFEF8A1F),
      MachineStatus.fault => const Color(0xFFD93A3A),
      MachineStatus.notTested => Colors.grey,
    };

IconData machineStatusIcon(MachineStatus s) => switch (s) {
      MachineStatus.ok => Icons.check_circle,
      MachineStatus.warning => Icons.warning_amber_rounded,
      MachineStatus.incomplete => Icons.hourglass_bottom,
      MachineStatus.fault => Icons.cancel,
      MachineStatus.notTested => Icons.help_outline,
    };

/// Télécharge le résultat d'une machine : le PDF est un certificat complet,
/// Excel / CSV contiennent synthèse, standards et mesures.
Future<void> exportMachine(BuildContext context, WidgetRef ref, MachineEntry e) async {
  final locale = ref.read(localeProvider);
  final choice = await chooseExport(context, locale);
  if (choice == null || !context.mounted) return;
  await exportWithChoice(
    context: context,
    locale: locale,
    choice: choice,
    baseName: 'test_${e.machine}',
    tables: machineExportTables(e.result),
    pdfHeaderName: e.machine,
    pdfBuilder: () => buildMachineCertificatePdf(e),
  );
}

/// Grand affichage du résultat d'une machine : verdict, échéance, indicateurs,
/// historique, un bloc par standard avec carte de contrôle, et téléchargement.
class MachineDetailScreen extends ConsumerWidget {
  final String machineName;
  const MachineDetailScreen({super.key, required this.machineName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(machineHistoryProvider).valueOrNull?.where((e) => e.machine == machineName).firstOrNull;
    if (entry == null) return Scaffold(appBar: AppBar(title: Text(machineName)), body: const Center(child: CircularProgressIndicator()));
    final m = entry.result;
    final color = machineStatusColor(m.status);
    final theme = Theme.of(context);
    final fmt = DateFormat('dd/MM/yyyy');
    final dueColor = switch (entry.due.state) {
      DueState.overdue => machineStatusColor(MachineStatus.fault),
      DueState.soon => machineStatusColor(MachineStatus.warning),
      DueState.ok => machineStatusColor(MachineStatus.ok),
      DueState.unknown => Colors.grey,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(m.machine, overflow: TextOverflow.ellipsis),
        actions: [IconButton(tooltip: 'Télécharger', icon: const Icon(Icons.download), onPressed: () => exportMachine(context, ref, entry))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => exportMachine(context, ref, entry),
        icon: const Icon(Icons.download),
        label: const Text('Télécharger le résultat'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color, width: 2)),
            child: Column(children: [
              Icon(machineStatusIcon(m.status), size: 84, color: color),
              const SizedBox(height: 8),
              Text(m.status.label.toUpperCase(), style: theme.textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(m.verdict, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Action : ${m.recommendation}', style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: dueColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(Icons.event, size: 40, color: dueColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.due.label, style: theme.textTheme.titleLarge?.copyWith(color: dueColor, fontWeight: FontWeight.w800)),
                  Text(entry.due.last == null
                      ? 'Aucune calibration enregistrée'
                      : 'Dernière : ${fmt.format(entry.due.last!)} · échéance ${fmt.format(entry.due.due!)} · tous les ${entry.settings.intervalDays} j'),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Kpi('Conformité', m.conformityRate == null ? '—' : '${m.conformityRate!.toStringAsFixed(0)} %', color),
            _Kpi('Couverture', '${m.coverage.toStringAsFixed(0)} %', Colors.blueGrey),
            _Kpi('Saisies', '${m.measured}/${m.total}', Colors.blueGrey),
            _Kpi('Hors tolérance', '${m.failed}', m.failed > 0 ? machineStatusColor(MachineStatus.fault) : Colors.blueGrey),
            _Kpi('En attente', '${m.pending}', m.pending > 0 ? machineStatusColor(MachineStatus.incomplete) : Colors.blueGrey),
          ]),
          if (entry.history.length > 1) ...[
            const SizedBox(height: 24),
            Text('Historique (${entry.history.length} imports)', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _HistoryCard(entry),
          ],
          for (final sh in m.sheets) ...[
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: Text(sh.sheet, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              Chip(
                avatar: Icon(machineStatusIcon(sh.status), size: 18, color: machineStatusColor(sh.status)),
                label: Text('${sh.status.label} · ${sh.standards.first.tolerance.text}'),
              ),
            ]),
            for (final s in sh.standards) _StandardCard(s),
          ],
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Kpi(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ]),
      );
}

/// Évolution du taux de conformité d'un import à l'autre + liste des imports.
class _HistoryCard extends StatelessWidget {
  final MachineEntry entry;
  const _HistoryCard(this.entry);

  @override
  Widget build(BuildContext context) {
    final rows = [for (var i = 0; i < entry.history.length; i++) (entry.history[i], entry.historyResults[i])];
    final rates = [for (final r in rows) r.$2.conformityRate ?? 0.0];
    final fmt = DateFormat('dd/MM/yy HH:mm');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Taux de conformité à chaque import (%)'),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: CustomPaint(
              size: Size.infinite,
              painter: _LinePainter(values: rates, color: machineStatusColor(entry.result.status), axis: Theme.of(context).colorScheme.onSurface, fixedRange: const (0, 100)),
            ),
          ),
          const SizedBox(height: 8),
          for (final r in rows.reversed.take(10))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(machineStatusIcon(r.$2.status), color: machineStatusColor(r.$2.status), size: 20),
              title: Text('${fmt.format(r.$1.importedAt)} · ${r.$2.status.label}'),
              subtitle: Text('${r.$2.measured}/${r.$2.total} mesurées · ${r.$2.failed} hors tolérance'),
              trailing: Text(r.$2.conformityRate == null ? '—' : '${r.$2.conformityRate!.toStringAsFixed(0)} %'),
            ),
        ]),
      ),
    );
  }
}

class _StandardCard extends StatelessWidget {
  final StandardResult s;
  const _StandardCard(this.s);

  String _n(double? v) => v == null ? '—' : v.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    final color = machineStatusColor(s.status);
    final theme = Theme.of(context);
    final done = s.readings.where((r) => r.error != null).toList();
    final errors = [for (final r in done) r.error!].where((e) => e.isFinite).toList();
    final stats = errors.length >= 5 ? controlStats(errors) : null;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(machineStatusIcon(s.status), color: color, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text('${s.standard}  ·  réf. ${s.reference}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            Text(s.status.label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text(s.reason),
          const SizedBox(height: 4),
          Text('Écart moyen ${_n(s.meanError)} · pire ${_n(s.worstError)} · σ ${_n(s.stdDev)} · ${s.passCount} OK / ${s.failCount} KO / ${s.pendingCount} en attente',
              style: theme.textTheme.bodySmall),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(height: 120, child: CustomPaint(size: Size.infinite, painter: _ErrorChart(done, s.tolerance.value, theme.colorScheme.onSurface))),
            Text('Écart de chaque mesure (zone verte = tolérance ${s.tolerance.text})', style: theme.textTheme.bodySmall),
          ],
          if (stats != null) ...[
            const SizedBox(height: 12),
            Text('Carte de contrôle (moyenne ${_n(stats.mean)}, ±2σ orange, ±3σ rouge)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SizedBox(
              height: 140,
              child: CustomPaint(
                size: Size.infinite,
                painter: _LinePainter(values: errors, color: color, axis: theme.colorScheme.onSurface, stats: stats),
              ),
            ),
          ],
          if (s.readings.length <= 40) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 36,
                headingRowHeight: 36,
                columns: const [DataColumn(label: Text('#')), DataColumn(label: Text('Mesuré')), DataColumn(label: Text('Écart')), DataColumn(label: Text('Résultat'))],
                rows: [
                  for (var i = 0; i < s.readings.length; i++)
                    DataRow(cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(s.readings[i].point.measured?.toString() ?? '—')),
                      DataCell(Text(_n(s.readings[i].error))),
                      DataCell(Text(
                        s.readings[i].pass == null ? 'En attente' : (s.readings[i].pass! ? 'PASS' : 'FAIL'),
                        style: TextStyle(fontWeight: FontWeight.w700, color: s.readings[i].pass == null ? Colors.grey : (s.readings[i].pass! ? Colors.green : Colors.red)),
                      )),
                    ]),
                ],
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Barres des écarts autour de zéro, bande verte = tolérance.
class _ErrorChart extends CustomPainter {
  final List<PointResult> pts;
  final double tol;
  final Color axis;
  _ErrorChart(this.pts, this.tol, this.axis);

  @override
  void paint(Canvas canvas, Size size) {
    var maxAbs = tol * 1.3;
    for (final p in pts) {
      final e = p.error!.abs();
      if (e.isFinite && e > maxAbs) maxAbs = e;
    }
    if (maxAbs <= 0) maxAbs = 1;
    final mid = size.height / 2;
    double y(double v) => mid - (v.clamp(-maxAbs, maxAbs)) / maxAbs * (size.height / 2 - 4);
    canvas.drawRect(Rect.fromLTRB(0, y(tol), size.width, y(-tol)), Paint()..color = Colors.green.withValues(alpha: 0.15));
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = axis.withValues(alpha: 0.4)..strokeWidth = 1);
    final w = size.width / pts.length;
    for (var i = 0; i < pts.length; i++) {
      final e = pts[i].error!;
      final paint = Paint()..color = pts[i].pass == false ? Colors.red : Colors.green;
      final x = i * w + w * 0.15;
      final top = y(e.isFinite ? e : -maxAbs);
      canvas.drawRect(Rect.fromLTRB(x, top < mid ? top : mid, x + w * 0.7, top < mid ? mid : top), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ErrorChart old) => old.pts != pts || old.tol != tol;
}

/// Courbe de points ; avec [stats] : ligne centrale et limites ±2σ / ±3σ.
class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color color, axis;
  final ControlStats? stats;
  final (double, double)? fixedRange;
  _LinePainter({required this.values, required this.color, required this.axis, this.stats, this.fixedRange});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (stats != null) {
      if (stats!.lcl3 < lo) lo = stats!.lcl3;
      if (stats!.ucl3 > hi) hi = stats!.ucl3;
    }
    if (fixedRange != null) {
      lo = fixedRange!.$1;
      hi = fixedRange!.$2;
    }
    if (hi - lo < 1e-12) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    double x(int i) => values.length == 1 ? size.width / 2 : i * size.width / (values.length - 1);

    void hline(double v, Color c, {double w = 1}) =>
        canvas.drawLine(Offset(0, y(v)), Offset(size.width, y(v)), Paint()..color = c..strokeWidth = w);
    if (stats != null) {
      hline(stats!.mean, axis.withValues(alpha: 0.6));
      hline(stats!.ucl2, Colors.orange.withValues(alpha: 0.8));
      hline(stats!.lcl2, Colors.orange.withValues(alpha: 0.8));
      hline(stats!.ucl3, Colors.red.withValues(alpha: 0.8));
      hline(stats!.lcl3, Colors.red.withValues(alpha: 0.8));
    } else {
      hline(lo + pad, axis.withValues(alpha: 0.2));
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(x(i), y(values[i]));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2);
    for (var i = 0; i < values.length; i++) {
      var c = color;
      if (stats != null && (values[i] > stats!.ucl3 || values[i] < stats!.lcl3)) c = Colors.red;
      canvas.drawCircle(Offset(x(i), y(values[i])), 3.5, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.values != values || old.stats != stats;
}
