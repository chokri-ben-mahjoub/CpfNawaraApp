import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/machines/machine_history.dart';
import '../../../core/machines/machine_schedule.dart';
import '../../../core/machines/machine_test.dart';
import 'machine_detail_screen.dart';

class MachineTestScreen extends ConsumerStatefulWidget {
  const MachineTestScreen({super.key});

  @override
  ConsumerState<MachineTestScreen> createState() => _MachineTestScreenState();
}

class _MachineTestScreenState extends ConsumerState<MachineTestScreen> {
  Future<void> _pick() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xlsm', 'csv'],
        allowMultiple: true,
        withData: true,
      );
      if (res == null) return;
      final points = <CalPoint>[];
      final warnings = <String>[];
      for (final f in res.files) {
        if (f.bytes == null) continue;
        try {
          final d = parseCalibrationFile(f.name, f.bytes!);
          points.addAll(d.points);
          warnings.addAll(d.warnings);
        } catch (e) {
          warnings.add('« ${f.name} » illisible : $e');
        }
      }
      final report = await ref.read(machineHistoryProvider.notifier).saveImport(points, warnings);
      messenger.showSnackBar(SnackBar(
        content: Text('${report.added} machine(s) mise(s) à jour, ${report.unchanged} inchangée(s)'
            '${warnings.isEmpty ? '' : '\n${warnings.join('\n')}'}'),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lecture impossible : $e')));
    }
  }

  Future<void> _editInterval(MachineEntry e) async {
    final c = TextEditingController(text: e.settings.intervalDays.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Périodicité de recalibration'),
        content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jours', helperText: 'Ex. 30 pour une vérification mensuelle')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    final v = int.tryParse(c.text.trim());
    if (ok == true && v != null && v > 0) await ref.read(machineHistoryProvider.notifier).setInterval(e.machine, v);
  }

  Future<void> _editTolerance(MachineEntry e, SheetResult sh) async {
    final cur = sh.standards.first.tolerance;
    final c = TextEditingController(text: cur.value.toString());
    var relative = cur.relative;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Tolérance — ${sh.sheet}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: c, decoration: const InputDecoration(labelText: 'Valeur ±'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('% relatif')), ButtonSegment(value: false, label: Text('Absolue'))],
              selected: {relative},
              onSelectionChanged: (v) => setS(() => relative = v.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    if (ok == true && v != null && v >= 0) {
      await ref.read(machineHistoryProvider.notifier).setTolerance(e.machine, sh.sheet, relative ? CalTolerance.relative(v) : CalTolerance.absolute(v));
    }
  }

  Future<void> _delete(MachineEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la machine ?'),
        content: Text('« ${e.machine} » et tout son historique (${e.history.length} import(s)) seront supprimés de cet appareil.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) await ref.read(machineHistoryProvider.notifier).deleteMachine(e.machine);
  }

  Color _levelColor(AlertLevel l) => switch (l) {
        AlertLevel.critical => machineStatusColor(MachineStatus.fault),
        AlertLevel.warning => machineStatusColor(MachineStatus.warning),
        AlertLevel.info => Colors.blueGrey,
      };

  Color _dueColor(DueState s) => switch (s) {
        DueState.overdue => machineStatusColor(MachineStatus.fault),
        DueState.soon => machineStatusColor(MachineStatus.warning),
        DueState.ok => machineStatusColor(MachineStatus.ok),
        DueState.unknown => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(machineHistoryProvider);
    final entries = async.valueOrNull ?? const <MachineEntry>[];
    final alerts = buildMachineAlerts(entries);
    int count(MachineStatus s) => entries.where((e) => e.result.status == s).length;
    final results = [for (final e in entries) e.result];

    return Scaffold(
      appBar: AppBar(title: const Text('Laboratory Instrument Calibration'), actions: [
        if (entries.isNotEmpty)
          IconButton(
            tooltip: 'Télécharger le rapport de toutes les machines',
            icon: const Icon(Icons.download),
            onPressed: () => runExport(
              context: context,
              locale: ref.read(localeProvider),
              baseName: 'test_machines',
              tables: [
                allMachinesTable(results),
                for (final m in results)
                  ExportTable(
                    name: m.machine.length > 25 ? m.machine.substring(0, 25) : m.machine,
                    headers: machineExportTables(m)[1].headers,
                    rows: machineExportTables(m)[1].rows,
                  ),
              ],
            ),
          ),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _pick, icon: const Icon(Icons.upload_file), label: const Text('Importer Excel')),
      body: async.isLoading && entries.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (entries.isEmpty)
                  const Text(
                    'Importez un ou plusieurs classeurs de calibration (.xlsx). Chaque feuille doit avoir une '
                    'colonne valeur de référence / certifiée et une colonne valeur mesurée.\n\n'
                    'Chaque machine est testée séparément, standard par standard. Chaque import est conservé : '
                    "l'historique montre la dérive dans le temps et l'application calcule la prochaine "
                    'recalibration (30 jours par défaut, modifiable par machine).',
                  ),
                if (alerts.isNotEmpty) ...[
                  Text('Alertes (${alerts.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  for (final a in alerts.take(8))
                    Card(
                      color: _levelColor(a.level).withValues(alpha: 0.1),
                      child: ListTile(
                        dense: true,
                        leading: Icon(a.level == AlertLevel.info ? Icons.info_outline : Icons.notification_important, color: _levelColor(a.level)),
                        title: Text('${a.title} — ${a.machine}'),
                        subtitle: Text(a.body),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                if (entries.isNotEmpty) ...[
                  Wrap(spacing: 8, children: [
                    for (final s in MachineStatus.values)
                      Chip(avatar: CircleAvatar(backgroundColor: machineStatusColor(s), radius: 6), label: Text('${s.label} : ${count(s)}')),
                  ]),
                  const SizedBox(height: 8),
                ],
                for (final e in entries)
                  Card(
                    child: ExpansionTile(
                      leading: Icon(Icons.precision_manufacturing, color: machineStatusColor(e.result.status)),
                      title: Text(e.machine),
                      subtitle: Text('${e.result.status.label} · ${e.result.measured}/${e.result.total} mesurées · ${e.due.label}'),
                      trailing: Icon(Icons.event, color: _dueColor(e.due.state)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MachineDetailScreen(machineName: e.machine))),
                                icon: const Icon(Icons.open_in_full),
                                label: const Text('Grand affichage'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(onPressed: () => exportMachine(context, ref, e), icon: const Icon(Icons.download), label: const Text('Télécharger')),
                          ]),
                        ),
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.event, color: _dueColor(e.due.state)),
                          title: Text(e.due.label),
                          subtitle: Text('Périodicité ${e.settings.intervalDays} j · ${e.history.length} import(s) conservé(s)'),
                          trailing: const Icon(Icons.edit_outlined, size: 18),
                          onTap: () => _editInterval(e),
                        ),
                        for (final sh in e.result.sheets)
                          ListTile(
                            dense: true,
                            title: Text(sh.sheet, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${sh.status.label} · tolérance ${sh.standards.first.tolerance.text}'),
                            trailing: const Icon(Icons.edit_outlined, size: 18),
                            onTap: () => _editTolerance(e, sh),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(onPressed: () => _delete(e), icon: const Icon(Icons.delete_outline), label: const Text('Supprimer la machine')),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
