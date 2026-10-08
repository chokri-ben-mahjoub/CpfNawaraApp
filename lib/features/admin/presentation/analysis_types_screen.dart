import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/theme/app_theme.dart';

const _uuid = Uuid();

class AnalysisTypesScreen extends ConsumerWidget {
  const AnalysisTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final types = ref.watch(wellsControllerProvider).analysisTypes;
    String s(String key) => tr(locale, key);

    return Scaffold(
      appBar: AppBar(title: Text(s('adminTypesTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: Text(s('adminAddType')),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final type = types[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.science_outlined, color: accentColor),
              title: Text('${type.label} (${type.unit})', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${type.min} – ${type.max} ${type.unit} · ${s(type.frequency.labelKey)}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _openEditor(context, ref, existing: type),
            ),
          );
        },
      ),
    );
  }

  void _openEditor(BuildContext context, WidgetRef ref, {AnalysisType? existing}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => _AnalysisTypeForm(existing: existing),
    );
  }
}

class _AnalysisTypeForm extends ConsumerStatefulWidget {
  final AnalysisType? existing;
  const _AnalysisTypeForm({this.existing});

  @override
  ConsumerState<_AnalysisTypeForm> createState() => _AnalysisTypeFormState();
}

class _AnalysisTypeFormState extends ConsumerState<_AnalysisTypeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _unitController;
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  late AnalysisFrequency _frequency;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController();
    _unitController = TextEditingController(text: e?.unit ?? '');
    _minController = TextEditingController(text: e == null ? '' : e.min.toString());
    _maxController = TextEditingController(text: e == null ? '' : e.max.toString());
    _frequency = e?.frequency ?? AnalysisFrequency.daily;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final min = double.parse(_minController.text.replaceAll(',', '.'));
    final max = double.parse(_maxController.text.replaceAll(',', '.'));
    final controller = ref.read(wellsControllerProvider.notifier);
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);

    if (_isNew) {
      controller.addAnalysisType(AnalysisType(
        id: _uuid.v4(),
        label: _nameController.text.trim(),
        unit: _unitController.text.trim(),
        min: min,
        max: max,
        frequency: _frequency,
      ));
      _showSnack(s('adminTypeAdded'));
    } else {
      controller.updateAnalysisType(AnalysisType(
        id: widget.existing!.id,
        label: widget.existing!.label,
        unit: _unitController.text.trim(),
        min: min,
        max: max,
        frequency: _frequency,
      ));
      _showSnack(s('adminTypeUpdated'));
    }
    Navigator.of(context).pop();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;
    String s(String key) => tr(locale, key);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isNew ? s('adminNewType') : s('adminEditType'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_isNew) ...[
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: s('adminNameLabel')),
                validator: (v) => (v ?? '').trim().isEmpty ? s('adminInvalidName') : null,
              ),
              const SizedBox(height: 12),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  widget.existing!.label,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
              ),
            TextFormField(
              controller: _unitController,
              decoration: InputDecoration(labelText: s('adminUnitLabel')),
              validator: (v) => (v ?? '').trim().isEmpty ? s('adminInvalidUnit') : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _minController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: InputDecoration(labelText: s('adminMinLabel')),
                    validator: _validateThreshold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _maxController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: InputDecoration(labelText: s('adminMaxLabel')),
                    validator: _validateThreshold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AnalysisFrequency>(
              value: _frequency,
              decoration: InputDecoration(labelText: s('adminFrequencyLabel')),
              items: [
                for (final f in AnalysisFrequency.values)
                  DropdownMenuItem(value: f, child: Text(s(f.labelKey))),
              ],
              onChanged: (value) => setState(() => _frequency = value ?? _frequency),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(s('adminSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateThreshold(String? value) {
    final locale = ref.read(localeProvider);
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (parsed == null) return tr(locale, 'adminInvalidThreshold');
    final min = double.tryParse(_minController.text.replaceAll(',', '.'));
    final max = double.tryParse(_maxController.text.replaceAll(',', '.'));
    if (min != null && max != null && min >= max) return tr(locale, 'adminMinMaxOrder');
    return null;
  }
}
