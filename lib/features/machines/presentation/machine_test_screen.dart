import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/machines/machine_test.dart';

class MachineTestScreen extends StatefulWidget {
  const MachineTestScreen({super.key});

  @override
  State<MachineTestScreen> createState() => _MachineTestScreenState();
}

class _MachineTestScreenState extends State<MachineTestScreen> {
  final List<CalPoint> _points = [];
  final List<String> _files = [];
  final List<String> _warnings = [];
  final Map<String, CalTolerance> _overrides = {};

  Future<void> _pick() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xlsm', 'csv'],
        allowMultiple: true,
        withData: true,
      );
      if (res == null) return;
      setState(() {
        _points.clear();
        _files.clear();
        _warnings.clear();
        _overrides.clear();
        for (final f in res.files) {
          if (f.bytes == null) continue;
          try {
            final d = parseCalibrationFile(f.name, f.bytes!);
            _points.addAll(d.points);
            _warnings.addAll(d.warnings);
            _files.add(f.name);
          } catch (e) {
            _warnings.add('« ${f.name} » illisible : $e');
          }
        }
      });
    } catch (e) {
      setState(() => _warnings.add('Lecture impossible : $e'));
    }
  }

  Color _color(MachineStatus s) => switch (s) {
        MachineStatus.ok => Colors.green,
        MachineStatus.warning => Colors.amber.shade700,
        MachineStatus.incomplete => Colors.orange,
        MachineStatus.fault => Colors.red,
        MachineStatus.notTested => Colors.grey,
      };

  Future<void> _editTolerance(String machine, SheetResult sh) async {
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
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('% relatif')),
                ButtonSegment(value: false, label: Text('Absolue')),
              ],
              selected: {relative},
              onSelectionChanged: (v) => setS(() => relative = v.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Appliquer')),
          ],
        ),
      ),
    );
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    if (ok == true && v != null && v >= 0) {
      setState(() => _overrides[toleranceKey(machine, sh.sheet)] = relative ? CalTolerance.relative(v) : CalTolerance.absolute(v));
    }
  }

  String _n(double? v) => v == null ? '—' : v.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    final results = evaluateCalibration(_points, overrides: _overrides);
    int count(MachineStatus s) => results.where((r) => r.status == s).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Test machines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pick,
        icon: const Icon(Icons.upload_file),
        label: const Text('Importer Excel'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_files.isEmpty && _warnings.isEmpty)
            const Text(
              'Importez un ou plusieurs classeurs de calibration (.xlsx). '
              'Chaque feuille doit avoir une colonne valeur de référence / certifiée '
              'et une colonne valeur mesurée.\n\n'
              'Chaque machine est testée séparément, standard par standard. '
              'Une mesure vide = « en attente » (pas un échec). Tolérances par défaut : '
              'pH ±0,05 · balance ±0,001 g · conductivité ±2 % · densimètre ±0,1 % · '
              'titrateur ±1 % · KF, chlorure, GC ±5 %. Touchez l\'icône crayon d\'une feuille pour la modifier.',
            ),
          for (final w in _warnings) Text(w, style: const TextStyle(color: Colors.orange)),
          if (results.isNotEmpty) ...[
            Text('${_files.length} fichier(s) · ${results.length} machine(s)', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final s in MachineStatus.values)
                Chip(avatar: CircleAvatar(backgroundColor: _color(s), radius: 6), label: Text('${s.label} : ${count(s)}')),
            ]),
            const SizedBox(height: 8),
            for (final r in results)
              Card(
                child: ExpansionTile(
                  leading: Icon(Icons.precision_manufacturing, color: _color(r.status)),
                  title: Text(r.machine),
                  subtitle: Text('${r.status.label} · ${r.measured}/${r.total} mesurées · ${r.failed} hors tolérance'),
                  children: [
                    for (final sh in r.sheets) ...[
                      ListTile(
                        dense: true,
                        title: Text(sh.sheet, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${sh.status.label} · tolérance ${sh.standards.first.tolerance.text}'),
                        trailing: const Icon(Icons.edit_outlined, size: 18),
                        onTap: () => _editTolerance(r.machine, sh),
                      ),
                      for (final s in sh.standards)
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 32, right: 16),
                          leading: Icon(Icons.circle, size: 14, color: _color(s.status)),
                          title: Text('${s.standard} (réf. ${s.reference})'),
                          subtitle: Text('${s.reason}\nÉcart moyen ${_n(s.meanError)} · pire ${_n(s.worstError)} · σ ${_n(s.stdDev)} · ${s.passCount} OK / ${s.failCount} KO / ${s.pendingCount} en attente'),
                          isThreeLine: true,
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
