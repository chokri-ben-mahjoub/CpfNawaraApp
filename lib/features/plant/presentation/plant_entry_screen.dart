import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/analysis/series.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';

/// Saisie (ou correction) de l'analyse d'un point pour un jour : un champ
/// par paramètre, valeur hors seuil signalée en direct.
class PlantEntryScreen extends ConsumerStatefulWidget {
  final String pointId;
  final DateTime? initialDate;

  const PlantEntryScreen({super.key, required this.pointId, this.initialDate});

  @override
  ConsumerState<PlantEntryScreen> createState() => _PlantEntryScreenState();
}

class _PlantEntryScreenState extends ConsumerState<PlantEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _choices = <String, String?>{};
  final _comment = TextEditingController();
  late DateTime _date;
  String _source = plantSources.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final d = widget.initialDate ?? now;
    _date = DateTime(d.year, d.month, d.day);
    final point = ref.read(plantControllerProvider.notifier).point(widget.pointId);
    for (final param in point?.params ?? const <PlantParam>[]) {
      if (param.isNumeric) {
        _fields[param.key] = TextEditingController()..addListener(() => setState(() {}));
      } else {
        _choices[param.key] = null;
      }
    }
    _loadExisting();
  }

  /// Pré-remplit avec l'analyse déjà saisie pour ce jour (correction).
  void _loadExisting() {
    final controller = ref.read(plantControllerProvider.notifier);
    final existing = controller.analysisOn(widget.pointId, _date);
    for (final entry in _fields.entries) {
      final v = existing?.number(entry.key);
      entry.value.text = v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
    }
    for (final key in _choices.keys.toList()) {
      _choices[key] = existing?.values[key] as String?;
    }
    _comment.text = existing?.comment ?? '';
    if (existing != null) _source = existing.source;
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _comment.dispose();
    super.dispose();
  }

  double? _parse(String text) => double.tryParse(text.trim().replaceAll(',', '.').replaceAll(' ', ''));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final values = <String, Object?>{
      for (final e in _fields.entries)
        if (_parse(e.value.text) != null) e.key: _parse(e.value.text),
      for (final e in _choices.entries)
        if (e.value != null) e.key: e.value,
    };
    if (values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('plantEntryEmpty'))));
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(plantControllerProvider.notifier)
        .saveAnalysis(
          pointId: widget.pointId,
          day: _date,
          values: values,
          source: _source,
          operatorName: ref.read(profileProvider)?.fullName ?? '',
          comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(s('plantEntrySaved'))));
  }

  Future<void> _delete(PlantAnalysis existing) async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s('plantDeleteConfirmTitle')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s('recordDelete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(plantControllerProvider.notifier).deleteAnalysis(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final point = controller.point(widget.pointId);
    if (point == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(s('plantPointNotFound'))),
      );
    }
    final existing = controller.analysisOn(point.id, _date);
    final now = DateTime.now();

    Widget numberField(PlantParam param) {
      final value = _parse(_fields[param.key]!.text);
      final out = controller.isOut(point.id, param, value);
      final t = controller.threshold(point.id, param.key);
      return TextFormField(
        controller: _fields[param.key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(
          labelText: s(param.labelKey),
          suffixText: param.unit,
          helperText: t == null ? null : '${s('trendThreshold')} : ${t.label(formatNumber)}',
          errorText: out == true ? s('plantValueOut') : null,
          errorStyle: TextStyle(color: scheme.error, fontWeight: FontWeight.w700),
        ),
        validator: (v) => (v ?? '').trim().isEmpty || _parse(v!) != null ? null : s('entryInvalidValue'),
      );
    }

    final numeric = point.params.where((p) => p.isNumeric).toList();
    final composition = numeric.where((p) => gasCompositionKeys.contains(p.key)).toList();
    final others = numeric.where((p) => !gasCompositionKeys.contains(p.key)).toList();
    final compositionSum = composition.fold<double>(0, (sum, p) => sum + (_parse(_fields[p.key]!.text) ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: Text('${s('plantEnter')} · ${point.code}'),
        actions: [
          if (existing != null)
            IconButton(
              tooltip: s('recordDelete'),
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: () => _delete(existing),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: pagePadding(context, top: 8, bottom: 40, maxWidth: 700),
          children: [
            Text(point.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              '${s(point.circuit.labelKey)} · ${point.equipment}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(now.year, now.month, now.day),
                );
                if (picked == null) return;
                setState(() {
                  _date = picked;
                  _loadExisting();
                });
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: s('plantSampleDate'),
                  prefixIcon: const Icon(Icons.event_outlined),
                ),
                child: Text(DateFormat('EEEE d MMMM yyyy', locale.languageCode).format(_date)),
              ),
            ),
            if (existing != null) ...[
              const SizedBox(height: 6),
              Text(
                s('plantEntryExisting'),
                style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 14),
            if (composition.isNotEmpty) ...[
              Text(s('plantComposition'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ResponsiveWrapGrid(
                minItemWidth: 150,
                spacing: 10,
                children: [for (final p in composition) numberField(p)],
              ),
              const SizedBox(height: 6),
              Text(
                '${s('plantCompositionSum')} : ${formatNumber(compositionSum)} mol %',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: compositionSum > 0 && (compositionSum < 98 || compositionSum > 102)
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
            ResponsiveWrapGrid(minItemWidth: 260, spacing: 10, children: [for (final p in others) numberField(p)]),
            for (final param in point.params.where((p) => !p.isNumeric)) ...[
              const SizedBox(height: 16),
              Text(s(param.labelKey), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in param.choices)
                    ChoiceChip(
                      label: Text(s(choice)),
                      selected: _choices[param.key] == choice,
                      selectedColor: (param.okChoices.contains(choice) ? Colors.green : scheme.error).withValues(
                        alpha: 0.18,
                      ),
                      onSelected: (selected) => setState(() => _choices[param.key] = selected ? choice : null),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _source,
              decoration: InputDecoration(labelText: s('plantColSource')),
              items: [for (final key in plantSources) DropdownMenuItem(value: key, child: Text(s(key)))],
              onChanged: (v) => setState(() => _source = v ?? _source),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _comment,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: s('entryCommentLabel')),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(s('wellsManageSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
