import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';

/// Saisie en série : plusieurs points d'un même circuit (ex. MEMBRANE N° 1 à
/// 6) à la suite, sur un seul écran, avec la couleur rouge/verte selon les
/// seuils au fur et à mesure de la saisie. Une analyse est créée par point
/// renseigné (paramètres numériques ; les choix se saisissent point par
/// point).
class PlantBatchEntryScreen extends ConsumerStatefulWidget {
  const PlantBatchEntryScreen({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  ConsumerState<PlantBatchEntryScreen> createState() =>
      _PlantBatchEntryScreenState();
}

class _PlantBatchEntryScreenState extends ConsumerState<PlantBatchEntryScreen> {
  late DateTime _date;
  TimeOfDay? _time;
  PlantCircuit? _circuit;
  final _filter = TextEditingController();
  final _source = TextEditingController();
  final _selected = <String>{};
  // pointId -> paramKey -> champ
  final _fields = <String, Map<String, TextEditingController>>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate ?? DateTime.now();
    _date = DateTime(d.year, d.month, d.day);
    _source.text = tr(ref.read(localeProvider), plantSources.first);
  }

  @override
  void dispose() {
    _filter.dispose();
    _source.dispose();
    for (final m in _fields.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.').replaceAll(' ', ''));

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  List<PlantParam> _numericParams(SamplePoint p) => [
    for (final x in p.params)
      if (x.isNumeric && !x.computed) x,
  ];

  TextEditingController _field(String pointId, String key) =>
      (_fields[pointId] ??= {}).putIfAbsent(key, () => TextEditingController());

  Future<void> _save() async {
    final locale = ref.read(localeProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    final points = ref.read(plantControllerProvider).points;
    var saved = 0;
    setState(() => _saving = true);
    try {
      for (final point in points.where((p) => _selected.contains(p.id))) {
        final values = <String, Object?>{};
        for (final param in _numericParams(point)) {
          final v = _parse(_field(point.id, param.key).text);
          if (v != null) values[param.key] = v;
        }
        if (values.isEmpty) continue;
        final computed = plantComputedValues({
          for (final e in values.entries) e.key: (e.value as num).toDouble(),
        });
        for (final param in point.params) {
          if (param.computed && computed[param.key] != null)
            values[param.key] = computed[param.key];
        }
        await controller.saveAnalysis(
          pointId: point.id,
          day: _date,
          values: values,
          source: _source.text.trim(),
          operatorName: ref.read(profileProvider)?.fullName ?? '',
          startTime: _time == null ? null : _formatTime(_time!),
        );
        saved++;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    if (saved == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr(locale, 'plantEntryEmpty'))));
      return;
    }
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(fill(tr(locale, 'plantBatchSaved'), {'n': '$saved'})),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final state = ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final circuit =
        _circuit ?? (state.circuits.isEmpty ? null : state.circuits.first);
    final query = _filter.text.trim().toLowerCase();
    final candidates = [
      for (final p in state.points)
        if (p.active &&
            p.circuit == circuit &&
            _numericParams(p).isNotEmpty &&
            (query.isEmpty || p.title.toLowerCase().contains(query)))
          p,
    ];
    final chosen = [
      for (final p in state.points)
        if (_selected.contains(p.id)) p,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(s('plantBatchTitle'))),
      bottomNavigationBar: chosen.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _saving ? null : _save,
                    child: Text(
                      fill(s('plantBatchSave'), {'n': '${chosen.length}'}),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 90),
        children: [
          Text(
            s('plantBatchIntro'),
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ResponsiveWrapGrid(
            minItemWidth: 200,
            spacing: 12,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: s('plantSampleDate'),
                    prefixIcon: const Icon(Icons.event_outlined),
                  ),
                  child: Text(DateFormat('dd/MM/yyyy').format(_date)),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _time ?? TimeOfDay.now(),
                  );
                  if (picked != null) setState(() => _time = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: s('plantSamplingTime'),
                    prefixIcon: const Icon(Icons.schedule),
                  ),
                  child: Text(_time == null ? '—' : _formatTime(_time!)),
                ),
              ),
              TextField(
                controller: _source,
                decoration: InputDecoration(labelText: s('plantColSource')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in state.circuits)
                ChoiceChip(
                  avatar: Icon(c.icon, size: 18, color: c.color),
                  label: Text(s(c.labelKey)),
                  selected: circuit == c,
                  onSelected: (_) => setState(() => _circuit = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: s('plantBatchFilter'),
              hintText: 'MEMBRANE',
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(
                  () => _selected.addAll(candidates.map((p) => p.id)),
                ),
                icon: const Icon(Icons.select_all, size: 18),
                label: Text(s('plantBatchSelectAll')),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _selected.removeAll(candidates.map((p) => p.id)),
                ),
                child: Text(s('plantBatchSelectNone')),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in candidates)
                FilterChip(
                  label: Text(p.code),
                  selected: _selected.contains(p.id),
                  onSelected: (on) => setState(
                    () => on ? _selected.add(p.id) : _selected.remove(p.id),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (final point in chosen)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      point.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (point.equipment.isNotEmpty)
                      Text(
                        point.equipment,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 10),
                    ResponsiveWrapGrid(
                      minItemWidth: 170,
                      spacing: 12,
                      children: [
                        for (final param in _numericParams(point))
                          _ValueField(
                            controller: _field(point.id, param.key),
                            label:
                                '${s(param.labelKey)}${param.unit.isEmpty ? '' : ' (${param.unit})'}',
                            limit: controller
                                .threshold(point.id, param.key)
                                ?.label((v) => '$v'),
                            isOut: (text) {
                              final v = _parse(text);
                              if (v == null) return null;
                              // Le seuil est enregistré en unités SI, la
                              // saisie est dans l'unité affichée.
                              return controller.isOut(
                                point.id,
                                param,
                                param.toSi(v),
                              );
                            },
                            parse: _parse,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Champ numérique dont la couleur suit le seuil : rouge hors seuil, vert
/// conforme, neutre sans seuil.
class _ValueField extends StatefulWidget {
  const _ValueField({
    required this.controller,
    required this.label,
    required this.isOut,
    required this.parse,
    this.limit,
  });

  final TextEditingController controller;
  final String label;
  final String? limit;
  final bool? Function(String text) isOut;
  final double? Function(String text) parse;

  @override
  State<_ValueField> createState() => _ValueFieldState();
}

class _ValueFieldState extends State<_ValueField> {
  @override
  Widget build(BuildContext context) {
    final out = widget.isOut(widget.controller.text);
    final color = out == null
        ? null
        : (out ? const Color(0xFFD32F2F) : const Color(0xFF2E9E5B));
    return TextField(
      controller: widget.controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      style: TextStyle(fontWeight: FontWeight.w800, color: color),
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.limit == null || widget.limit!.isEmpty
            ? null
            : widget.limit,
        enabledBorder: color == null
            ? null
            : OutlineInputBorder(
                borderSide: BorderSide(color: color, width: 1.6),
              ),
        focusedBorder: color == null
            ? null
            : OutlineInputBorder(
                borderSide: BorderSide(color: color, width: 2),
              ),
      ),
    );
  }
}
