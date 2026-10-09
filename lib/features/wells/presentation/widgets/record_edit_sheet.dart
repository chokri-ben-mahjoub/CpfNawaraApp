import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/wells_repository.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/models/analysis_record.dart';
import '../../../../core/models/analysis_type.dart';

/// Ouvre la feuille de correction/suppression d'une analyse déjà enregistrée.
/// Partagé entre la fiche puits (aperçu) et l'historique complet.
void showRecordEditSheet(BuildContext context, {required AnalysisRecord record, required AnalysisType type}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => RecordEditSheet(record: record, type: type),
  );
}

/// Permet de corriger ou supprimer une analyse déjà enregistrée, y compris
/// d'un jour précédent — la saisie rapide ne permet de remplacer que celle
/// du jour même.
class RecordEditSheet extends ConsumerStatefulWidget {
  final AnalysisRecord record;
  final AnalysisType type;

  const RecordEditSheet({super.key, required this.record, required this.type});

  @override
  ConsumerState<RecordEditSheet> createState() => _RecordEditSheetState();
}

class _RecordEditSheetState extends ConsumerState<RecordEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _valueController;
  late final TextEditingController _commentController;
  late String _service;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: widget.record.value.toString());
    _commentController = TextEditingController(text: widget.record.comment ?? '');
    _service = widget.record.serviceKey;
  }

  @override
  void dispose() {
    _valueController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final value = double.parse(_valueController.text.replaceAll(',', '.'));
    await ref.read(wellsControllerProvider.notifier).updateRecord(
          recordId: widget.record.id,
          value: value,
          serviceKey: _service,
          comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s('recordDeleteConfirmTitle')),
        content: Text(s('recordDeleteConfirmBody')),
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
    await ref.read(wellsControllerProvider.notifier).deleteRecord(widget.record.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final dateFormat = DateFormat('d MMM yyyy, HH:mm', locale.languageCode);
    String s(String key) => tr(locale, key);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.type.label} — ${dateFormat.format(widget.record.dateTime)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  tooltip: s('recordDelete'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _valueController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: s('entryValueLabel'), suffixText: widget.type.unit),
              validator: (v) => double.tryParse((v ?? '').trim().replaceAll(',', '.')) == null ? s('entryInvalidValue') : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _service,
              decoration: InputDecoration(labelText: s('entryServiceLabel')),
              items: [
                for (final key in serviceKeys) DropdownMenuItem(value: key, child: Text(s(key))),
              ],
              onChanged: (value) => setState(() => _service = value ?? _service),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _commentController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: s('entryCommentLabel')),
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
    );
  }
}
