import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/intervention.dart';
import '../../../core/settings/app_settings.dart';

/// Ouvre le formulaire d'ajout (ou de modification si [existing]) d'une
/// intervention sur un puits.
void showInterventionForm(BuildContext context, {required String wellId, Intervention? existing}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => _InterventionForm(wellId: wellId, existing: existing),
  );
}

class _InterventionForm extends ConsumerStatefulWidget {
  final String wellId;
  final Intervention? existing;

  const _InterventionForm({required this.wellId, this.existing});

  @override
  ConsumerState<_InterventionForm> createState() => _InterventionFormState();
}

class _InterventionFormState extends ConsumerState<_InterventionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _costController;
  late final TextEditingController _descriptionController;
  late DateTime _date;
  late String _typeKey;
  late String _resultKey;
  late String _currency;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now();
    _date = e?.date ?? DateTime(now.year, now.month, now.day);
    _typeKey = e?.typeKey ?? interventionTypeKeys.first;
    _resultKey = e?.resultKey ?? 'interventionResultPending';
    final preferredCurrency = ref.read(appSettingsProvider).defaultCurrency;
    _currency = e?.currency ??
        (interventionCurrencies.contains(preferredCurrency) ? preferredCurrency : interventionCurrencies.first);
    _costController = TextEditingController(text: e?.cost == null ? '' : _plain(e!.cost!));
    _descriptionController = TextEditingController(text: e?.description ?? '');
  }

  static String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _costController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final costText = _costController.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    final description = _descriptionController.text.trim();
    final operatorName = widget.existing?.operatorName ?? ref.read(profileProvider)?.fullName ?? '';
    await ref.read(wellsControllerProvider.notifier).saveIntervention(Intervention(
          id: widget.existing?.id ?? '',
          wellId: widget.wellId,
          date: _date,
          typeKey: _typeKey,
          cost: costText.isEmpty ? null : double.parse(costText),
          currency: _currency,
          resultKey: _resultKey,
          description: description.isEmpty ? null : description,
          operatorName: operatorName,
        ));
    if (!mounted) return;
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(s(_isNew ? 'interventionAdded' : 'interventionUpdated'))));
  }

  Future<void> _delete() async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s('interventionDeleteConfirmTitle')),
        content: Text(s('interventionDeleteConfirmBody')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s('interventionDelete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(wellsControllerProvider.notifier).deleteIntervention(widget.existing!.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(s('interventionDeleted'))));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final dateLabel = DateFormat('EEEE d MMMM yyyy', locale.languageCode).format(_date);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s(_isNew ? 'interventionNew' : 'interventionEdit'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (!_isNew)
                    IconButton(
                      onPressed: _delete,
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      tooltip: s('interventionDelete'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: s('interventionDateLabel'),
                    prefixIcon: const Icon(Icons.event_outlined),
                  ),
                  child: Text(dateLabel[0].toUpperCase() + dateLabel.substring(1)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _typeKey,
                isExpanded: true,
                decoration: InputDecoration(labelText: s('interventionTypeLabel')),
                items: [
                  for (final key in interventionTypeKeys) DropdownMenuItem(value: key, child: Text(s(key))),
                ],
                onChanged: (v) => setState(() => _typeKey = v ?? _typeKey),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: s('interventionCostLabel')),
                      validator: (v) {
                        final text = (v ?? '').trim().replaceAll(' ', '').replaceAll(',', '.');
                        if (text.isEmpty) return null;
                        final value = double.tryParse(text);
                        return value == null || value < 0 ? s('interventionInvalidCost') : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: InputDecoration(labelText: s('interventionCurrencyLabel')),
                      items: [
                        for (final c in interventionCurrencies) DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _currency = v ?? _currency),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(s('interventionResultLabel'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in interventionResultKeys)
                    ChoiceChip(
                      label: Text(s(key)),
                      selected: _resultKey == key,
                      onSelected: (_) => setState(() => _resultKey = key),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: s('interventionDescriptionLabel'),
                  hintText: s('interventionDescriptionHint'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(s('wellsManageSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
