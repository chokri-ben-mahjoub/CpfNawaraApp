import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/export/export_service.dart';
import '../../../core/l10n/app_strings.dart';
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

Future<void> exportMachine(BuildContext context, WidgetRef ref, MachineResult m) {
  return runExport(
    context: context,
    locale: ref.read(localeProvider),
    baseName: 'test_${m.machine}',
    tables: machineExportTables(m),
    pdfHeaderName: m.machine,
  );
}

/// Grand affichage du résultat d'une machine : verdict, indicateurs, un bloc
/// par standard avec graphique des écarts, et téléchargement.
class MachineDetailScreen extends ConsumerWidget {
  final MachineResult machine;
  const MachineDetailScreen({super.key, required this.machine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = machine;
    final color = machineStatusColor(m.status);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(m.machine, overflow: TextOverflow.ellipsis),
        actions: [IconButton(tooltip: 'Télécharger', icon: const Icon(Icons.download), onPressed: () => exportMachine(context, ref, m))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => exportMachine(context, ref, m),
        icon: const Icon(Icons.download),
        label: const Text('Télécharger le résultat'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          // Bandeau verdict
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
          const SizedBox(height: 16),
          // Indicateurs
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Kpi('Conformité', m.conformityRate == null ? '—' : '${m.conformityRate!.toStringAsFixed(0)} %', color),
            _Kpi('Couverture', '${m.coverage.toStringAsFixed(0)} %', Colors.blueGrey),
            _Kpi('Saisies', '${m.measured}/${m.total}', Colors.blueGrey),
            _Kpi('Hors tolérance', '${m.failed}', m.failed > 0 ? machineStatusColor(MachineStatus.fault) : Colors.blueGrey),
            _Kpi('En attente', '${m.pending}', m.pending > 0 ? machineStatusColor(MachineStatus.incomplete) : Colors.blueGrey),
          ]),
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

class _StandardCard extends StatelessWidget {
  final StandardResult s;
  const _StandardCard(this.s);

  String _n(double? v) => v == null ? '—' : v.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    final color = machineStatusColor(s.status);
    final theme = Theme.of(context);
    final done = s.readings.where((r) => r.error != null).toList();
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
            SizedBox(height: 120, child: CustomPaint(size: Size.infinite, painter: _ErrorChart(done, s.tolerance.value, color, theme.colorScheme.onSurface))),
            Text('Écart de chaque mesure (zone verte = tolérance ${s.tolerance.text})', style: theme.textTheme.bodySmall),
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
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: s.readings[i].pass == null ? Colors.grey : (s.readings[i].pass! ? Colors.green : Colors.red),
                        ),
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
  final Color color, axis;
  _ErrorChart(this.pts, this.tol, this.color, this.axis);

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
    final line = Paint()..color = axis.withValues(alpha: 0.4)..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), line);
    final w = size.width / pts.length;
    for (var i = 0; i < pts.length; i++) {
      final e = pts[i].error!;
      final bad = pts[i].pass == false;
      final paint = Paint()..color = bad ? Colors.red : Colors.green;
      final x = i * w + w * 0.15;
      final top = y(e.isFinite ? e : -maxAbs);
      canvas.drawRect(Rect.fromLTRB(x, top < mid ? top : mid, x + w * 0.7, top < mid ? mid : top), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ErrorChart old) => old.pts != pts || old.tol != tol;
}
