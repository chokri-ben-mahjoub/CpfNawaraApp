import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';

const _serviceKeys = [
  'serviceLaboratoire',
  'serviceProduction',
  'serviceExploitation',
  'serviceReservoir',
  'serviceHse',
];

/// Saisie rapide : puits → type d'analyse → valeur → service → enregistrer.
/// Si [initialWellId] / [initialTypeId] sont fournis (venant d'une fiche
/// puits ou du tableau de bord), les champs correspondants sont pré-remplis
/// et verrouillés.
class QuickEntryScreen extends ConsumerStatefulWidget {
  final String? initialWellId;
  final String? initialTypeId;

  const QuickEntryScreen({super.key, this.initialWellId, this.initialTypeId});

  @override
  ConsumerState<QuickEntryScreen> createState() => _QuickEntryScreenState();
}

class _QuickEntryScreenState extends ConsumerState<QuickEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController();
  final _commentController = TextEditingController();

  String? _wellId;
  String? _typeId;
  String? _service;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _wellId = widget.initialWellId;
    _typeId = widget.initialTypeId;
  }

  @override
  void dispose() {
    _valueController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _touched = true);
    final valid = _formKey.currentState!.validate();
    if (!valid || _wellId == null || _typeId == null || _service == null) return;

    final value = double.parse(_valueController.text.replaceAll(',', '.'));
    final controller = ref.read(wellsControllerProvider.notifier);
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);

    final existing = controller.todayRecord(_wellId!, _typeId!);
    if (existing != null) {
      final replace = await _confirm(
        title: s('entryDuplicateTitle'),
        body:
            '${s('entryDuplicateBody')}\n\n${s(existing.serviceKey)} · ${existing.operatorName} · ${existing.value}',
        confirmLabel: s('entryDuplicateReplace'),
      );
      if (replace != true) return;
      if (!mounted) return;
    }

    final type = controller.typeById(_typeId!);
    if (type.isOutOfRange(value)) {
      final proceed = await _confirm(
        title: s('entryOutOfRangeTitle'),
        body: s('entryOutOfRangeBody'),
        confirmLabel: s('confirm'),
      );
      if (proceed != true) return;
      if (!mounted) return;
    }

    final operatorName = ref.read(pendingNameProvider) ?? 'Opérateur';
    controller.addRecord(
      wellId: _wellId!,
      typeId: _typeId!,
      value: value,
      serviceKey: _service!,
      operatorName: operatorName,
      comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      replaceId: existing?.id,
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.check_circle_outline, color: accentColor, size: 36),
        title: Text(s('entrySuccessTitle')),
        content: Text(s('entrySuccessBody')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s('close')),
          ),
        ],
      ),
    );
    if (mounted) context.pop();
  }

  Future<bool?> _confirm({required String title, required String body, required String confirmLabel}) {
    final locale = ref.read(localeProvider);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr(locale, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final data = ref.watch(wellsControllerProvider);
    final wells = data.wells;
    final types = data.analysisTypes;
    final selectedType = _typeId == null ? null : data.analysisTypes.firstWhere((t) => t.id == _typeId);

    return Scaffold(
      appBar: AppBar(title: Text(s('entryTitle'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      _FieldLabel(s('entryWellLabel')),
                      DropdownButtonFormField<String>(
                        value: _wellId,
                        decoration: InputDecoration(
                          hintText: s('entrySelectWell'),
                          prefixIcon: const Icon(Icons.water_drop_outlined),
                        ),
                        items: [
                          for (final Well w in wells)
                            DropdownMenuItem(value: w.id, child: Text('${w.name} (${w.code})')),
                        ],
                        onChanged: widget.initialWellId != null
                            ? null
                            : (value) => setState(() => _wellId = value),
                      ),
                      if (_touched && _wellId == null) _FieldError(s('entryInvalidWell')),
                      const SizedBox(height: 16),
                      _FieldLabel(s('entryTypeLabel')),
                      DropdownButtonFormField<String>(
                        value: _typeId,
                        decoration: InputDecoration(
                          hintText: s('entrySelectType'),
                          prefixIcon: const Icon(Icons.science_outlined),
                        ),
                        items: [
                          for (final AnalysisType t in types)
                            DropdownMenuItem(value: t.id, child: Text('${s(t.labelKey)} (${t.unit})')),
                        ],
                        onChanged: widget.initialTypeId != null
                            ? null
                            : (value) => setState(() => _typeId = value),
                      ),
                      if (_touched && _typeId == null) _FieldError(s('entryInvalidType')),
                      const SizedBox(height: 16),
                      _FieldLabel(s('entryValueLabel')),
                      TextFormField(
                        controller: _valueController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: InputDecoration(
                          hintText: s('entryValueHint'),
                          suffixText: selectedType?.unit,
                          prefixIcon: const Icon(Icons.numbers),
                        ),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
                          if (parsed == null) return s('entryInvalidValue');
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel(s('entryServiceLabel')),
                      DropdownButtonFormField<String>(
                        value: _service,
                        decoration: InputDecoration(
                          hintText: s('signupServiceHint'),
                          prefixIcon: const Icon(Icons.groups_outlined),
                        ),
                        items: [
                          for (final key in _serviceKeys)
                            DropdownMenuItem(value: key, child: Text(s(key))),
                        ],
                        onChanged: (value) => setState(() => _service = value),
                      ),
                      if (_touched && _service == null) _FieldError(s('entryInvalidService')),
                      const SizedBox(height: 16),
                      _FieldLabel(s('entryCommentLabel')),
                      TextFormField(
                        controller: _commentController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.notes_outlined)),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: Text(s('entrySave'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class _FieldError extends StatelessWidget {
  final String text;
  const _FieldError(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
    );
  }
}
