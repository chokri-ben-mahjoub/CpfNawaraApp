import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/models/well.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/startup_tasks.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';

/// Saisie groupée : une seule fiche pour tous les types d'analyse
/// "apparentés" (regroupés par l'Admin, ex: test de puits — choke, tête de
/// puits, injection chimique, séparateur de test), comme sur la fiche
/// papier — au lieu de refaire une saisie rapide par paramètre. Un seul
/// puits et un seul service pour toute la fiche ; les champs laissés vides
/// ne créent aucun enregistrement.
class BatchEntryScreen extends ConsumerStatefulWidget {
  final String? initialWellId;

  const BatchEntryScreen({super.key, this.initialWellId});

  @override
  ConsumerState<BatchEntryScreen> createState() => _BatchEntryScreenState();
}

class _BatchEntryScreenState extends ConsumerState<BatchEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};

  String? _wellId;
  String? _service;
  DateTime _date = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay? _endTime;
  bool _saving = false;
  bool _touched = false;

  static String? _formatTime(TimeOfDay? t) =>
      t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _wellId = widget.initialWellId;
    final preferred = ref.read(appSettingsProvider).defaultService;
    final candidate = preferred == defaultServiceFromProfile ? ref.read(profileProvider)?.serviceKey : preferred;
    if (candidate != null && serviceKeys.contains(candidate)) _service = candidate;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String typeId) => _controllers.putIfAbsent(typeId, TextEditingController.new);

  Future<void> _submit(List<AnalysisType> groupedTypes) async {
    setState(() => _touched = true);
    final valid = _formKey.currentState!.validate();
    if (!valid || _wellId == null || _service == null) return;

    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);

    final entries = <(AnalysisType, double)>[
      for (final type in groupedTypes)
        if ((_controllers[type.id]?.text ?? '').trim().isNotEmpty)
          (type, double.parse(_controllers[type.id]!.text.trim().replaceAll(',', '.'))),
    ];
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('entryBatchEmpty'))));
      return;
    }

    final outOfRange = [for (final (type, value) in entries) if (type.isOutOfRange(value)) type];
    if (outOfRange.isNotEmpty) {
      final proceed = await _confirm(
        title: s('entryOutOfRangeTitle'),
        body: '${s('entryOutOfRangeBody')}\n\n${outOfRange.map((t) => t.label).join(', ')}',
        confirmLabel: s('confirm'),
      );
      if (proceed != true) return;
      if (!mounted) return;
    }

    setState(() => _saving = true);
    final controller = ref.read(wellsControllerProvider.notifier);
    final profile = ref.read(profileProvider);
    final operatorName = (profile == null || profile.fullName.isEmpty) ? 'Opérateur' : profile.fullName;
    final recordedAt = DateTime(_date.year, _date.month, _date.day, _startTime.hour, _startTime.minute);
    for (final (type, value) in entries) {
      final existing = controller.recordOnDay(_wellId!, type.id, _date);
      await controller.addRecord(
        wellId: _wellId!,
        typeId: type.id,
        value: value,
        serviceKey: _service!,
        operatorName: operatorName,
        operatorId: profile?.id,
        replaceId: existing?.id,
        recordedAt: recordedAt,
        startTime: _formatTime(_startTime),
        endTime: _formatTime(_endTime),
      );
    }
    unawaited(refreshReminders(ref));
    if (!mounted) return;
    setState(() => _saving = false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.check_circle_outline, color: accentColor, size: 36),
        title: Text(s('entrySuccessTitle')),
        content: Text(fill(s('entryBatchSavedCount'), {'n': '${entries.length}'})),
        actions: [
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(s('close'))),
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
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr(locale, 'cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(confirmLabel)),
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

    final groupOrder = <String>[];
    final byGroup = <String, List<AnalysisType>>{};
    for (final t in data.analysisTypes) {
      if (t.group.isEmpty) continue;
      (byGroup[t.group] ??= []).add(t);
      if (!groupOrder.contains(t.group)) groupOrder.add(t.group);
    }
    final groupedTypes = [for (final g in groupOrder) ...byGroup[g]!];

    return Scaffold(
      appBar: AppBar(title: Text(s('entryBatchTitle'))),
      body: NarrowSafeArea(
        maxWidth: 640,
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
                      Text(s('entryBatchHint'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                      const SizedBox(height: 16),
                      _FieldLabel(s('entryWellLabel')),
                      DropdownButtonFormField<String>(
                        initialValue: _wellId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: s('entrySelectWell'),
                          prefixIcon: const Icon(Icons.water_drop_outlined),
                        ),
                        items: [
                          for (final Well w in wells)
                            DropdownMenuItem(
                              value: w.id,
                              child: Text('${w.name} (${w.code})', overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: widget.initialWellId != null ? null : (value) => setState(() => _wellId = value),
                      ),
                      if (_touched && _wellId == null) _FieldError(s('entryInvalidWell')),
                      const SizedBox(height: 16),
                      _FieldLabel(s('entryServiceLabel')),
                      DropdownButtonFormField<String>(
                        initialValue: _service,
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: s('signupServiceHint'),
                          prefixIcon: const Icon(Icons.groups_outlined),
                        ),
                        items: [
                          for (final key in serviceKeys)
                            DropdownMenuItem(value: key, child: Text(s(key), overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (value) => setState(() => _service = value),
                      ),
                      if (_touched && _service == null) _FieldError(s('entryInvalidService')),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _date,
                                  firstDate: DateTime(now.year - 2),
                                  lastDate: now,
                                );
                                if (picked != null) setState(() => _date = picked);
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: s('entryBatchDateLabel'),
                                  prefixIcon: const Icon(Icons.event_outlined),
                                ),
                                child: Text(DateFormat('d MMM yyyy', locale.languageCode).format(_date)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                final picked = await showTimePicker(context: context, initialTime: _startTime);
                                if (picked != null) setState(() => _startTime = picked);
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: s('entryBatchStartTimeLabel'),
                                  prefixIcon: const Icon(Icons.schedule_outlined),
                                ),
                                child: Text(_startTime.format(context)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          final picked = await showTimePicker(context: context, initialTime: _endTime ?? _startTime);
                          if (picked != null) setState(() => _endTime = picked);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: s('entryBatchEndTimeLabel'),
                            prefixIcon: const Icon(Icons.schedule_outlined),
                            suffixIcon: _endTime == null
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setState(() => _endTime = null),
                                  ),
                          ),
                          child: Text(_endTime == null ? '—' : _endTime!.format(context)),
                        ),
                      ),
                      for (final group in groupOrder) ...[
                        const SizedBox(height: 22),
                        Text(
                          group,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: accentColor, fontSize: 15),
                        ),
                        const Divider(height: 14),
                        for (final type in byGroup[group]!) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextFormField(
                              controller: _controllerFor(type.id),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              decoration: InputDecoration(
                                labelText: type.label,
                                suffixText: type.unit,
                                prefixIcon: const Icon(Icons.science_outlined),
                              ),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                if (text.isEmpty) return null;
                                return double.tryParse(text.replaceAll(',', '.')) == null
                                    ? s('entryInvalidValue')
                                    : null;
                              },
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => _submit(groupedTypes),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(s('entryBatchSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
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
