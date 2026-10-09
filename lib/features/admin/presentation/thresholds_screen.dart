import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/shared_config.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/admin_widgets.dart';

/// Seuils et alertes : pour chaque point et paramètre, min / max et alerte
/// activée ou non ; heure limite des analyses "non reçues".
class ThresholdsScreen extends ConsumerStatefulWidget {
  const ThresholdsScreen({super.key});

  @override
  ConsumerState<ThresholdsScreen> createState() => _ThresholdsScreenState();
}

class _ThresholdsScreenState extends ConsumerState<ThresholdsScreen> {
  String? _pointId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final shared = ref.watch(sharedConfigProvider);
    final points = ref.watch(plantControllerProvider).points;
    String s(String key) => tr(locale, key);
    final selected = points.where((p) => p.id == _pointId).firstOrNull ?? points.firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(s('adminThresholds'))),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 40, maxWidth: 980),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const IconBadge(Icons.schedule_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s('deadlineTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(s('deadlineHint'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonal(
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: shared.missingDeadline);
                      if (picked != null) await ref.read(sharedConfigProvider.notifier).setMissingDeadline(picked);
                    },
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
                    child: Text(
                      formatDeadline(shared.missingDeadline),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AdminSectionTitle(s('thresholdsByPoint')),
          Text(s('thresholdsIntro'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
          const SizedBox(height: 12),
          for (final circuit in PlantCircuit.values)
            if (points.any((p) => p.circuit == circuit)) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6, top: 4),
                child: Text(
                  s(circuit.labelKey),
                  style: TextStyle(fontWeight: FontWeight.w700, color: circuit.color),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in points.where((p) => p.circuit == circuit))
                    ChoiceChip(
                      label: Text(p.code),
                      selected: selected?.id == p.id,
                      selectedColor: circuit.color.withValues(alpha: 0.2),
                      onSelected: (_) => setState(() => _pointId = p.id),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          if (selected != null) ...[
            const SizedBox(height: 12),
            _PointThresholds(key: ValueKey(selected.id), point: selected),
          ],
        ],
      ),
    );
  }
}

class _Row {
  final PlantParam param;
  final TextEditingController min;
  final TextEditingController max;
  bool alert;
  String initialMin;
  String initialMax;
  bool initialAlert;

  _Row(this.param, PlantThreshold? t)
    : min = TextEditingController(text: decimalText(t?.min)),
      max = TextEditingController(text: decimalText(t?.max)),
      alert = t?.alertEnabled ?? true,
      initialMin = decimalText(t?.min),
      initialMax = decimalText(t?.max),
      initialAlert = t?.alertEnabled ?? true;

  bool get changed => min.text.trim() != initialMin || max.text.trim() != initialMax || alert != initialAlert;

  void markSaved() {
    initialMin = min.text.trim();
    initialMax = max.text.trim();
    initialAlert = alert;
  }
}

class _PointThresholds extends ConsumerStatefulWidget {
  final SamplePoint point;
  const _PointThresholds({super.key, required this.point});

  @override
  ConsumerState<_PointThresholds> createState() => _PointThresholdsState();
}

class _PointThresholdsState extends ConsumerState<_PointThresholds> {
  late final List<_Row> _rows;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(plantControllerProvider.notifier);
    _rows = [for (final p in widget.point.params) _Row(p, controller.threshold(widget.point.id, p.key))];
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.min.dispose();
      r.max.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final controller = ref.read(plantControllerProvider.notifier);
    for (final r in _rows.where((r) => r.changed)) {
      await controller.setThreshold(
        widget.point.id,
        r.param.key,
        parseDecimal(r.min.text),
        parseDecimal(r.max.text),
        alertEnabled: r.alert,
      );
      r.markSaved();
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr(ref.read(localeProvider), 'thresholdsSaved'))));
  }

  String? _validate(_Row r, String Function(String) s) {
    final min = parseDecimal(r.min.text);
    final max = parseDecimal(r.max.text);
    if (r.min.text.trim().isNotEmpty && min == null) return s('adminInvalidThreshold');
    if (r.max.text.trim().isNotEmpty && max == null) return s('adminInvalidThreshold');
    if (min != null && max != null && min > max) return s('adminMinAboveMax');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final point = widget.point;

    Widget numberField(TextEditingController c, String label, _Row r) => TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(labelText: label, suffixText: r.param.unit, isDense: true),
      validator: (_) => identical(c, r.min) ? _validate(r, s) : null,
      onChanged: (_) => setState(() {}),
    );

    return Form(
      key: _formKey,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(point.circuit.icon, color: point.circuit.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(point.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(
                          '${s(point.circuit.labelKey)}${point.equipment.isEmpty ? '' : ' · ${point.equipment}'}',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final r in _rows) ...[
                Divider(height: 20, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 620;
                    final title = Text(s(r.param.labelKey), style: const TextStyle(fontWeight: FontWeight.w700));
                    final alertSwitch = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(s('thresholdsAlert'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                        Switch(
                          value: r.alert,
                          activeTrackColor: accentColor,
                          onChanged: (v) => setState(() => r.alert = v),
                        ),
                      ],
                    );
                    if (!r.param.isNumeric) {
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                Text(
                                  '${s('thresholdsChoiceOk')} : ${r.param.okChoices.map(s).join(', ')}',
                                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          alertSwitch,
                        ],
                      );
                    }
                    if (wide) {
                      return Row(
                        children: [
                          Expanded(flex: 3, child: title),
                          const SizedBox(width: 12),
                          Expanded(flex: 3, child: numberField(r.min, s('thresholdsMin'), r)),
                          const SizedBox(width: 12),
                          Expanded(flex: 3, child: numberField(r.max, s('thresholdsMax'), r)),
                          const SizedBox(width: 12),
                          alertSwitch,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: title),
                            alertSwitch,
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: numberField(r.min, s('thresholdsMin'), r)),
                            const SizedBox(width: 10),
                            Expanded(child: numberField(r.max, s('thresholdsMax'), r)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                  onPressed: _saving || !_rows.any((r) => r.changed) ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(s('wellsManageSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
