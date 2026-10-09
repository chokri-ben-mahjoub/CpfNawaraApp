import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';

class WellsManageScreen extends ConsumerWidget {
  const WellsManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final wells = [...ref.watch(wellsControllerProvider).wells]
      ..sort((a, b) {
        final byGroup = a.group.compareTo(b.group);
        return byGroup != 0 ? byGroup : a.name.compareTo(b.name);
      });
    String s(String key) => tr(locale, key);

    return Scaffold(
      appBar: AppBar(title: Text(s('wellsManageTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: Text(s('wellsManageAdd')),
      ),
      body: wells.isEmpty
          ? Center(child: Text(s('wellsManageEmpty'), style: TextStyle(color: scheme.onSurfaceVariant)))
          : ListView.separated(
              padding: pagePadding(context, top: 12, bottom: 130),
              itemCount: wells.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final well = wells[i];
                return Card(
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (well.active ? accentColor : scheme.outline).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.water_drop_outlined, color: well.active ? accentColor : scheme.outline),
                    ),
                    title: Text('${well.name} (${well.code})', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      well.group.trim().isEmpty ? s('statsUnassignedGroup') : well.group,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _openEditor(context, existing: well),
                  ),
                );
              },
            ),
    );
  }

  void _openEditor(BuildContext context, {Well? existing}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => _WellForm(existing: existing),
    );
  }
}

class _WellForm extends ConsumerStatefulWidget {
  final Well? existing;
  const _WellForm({this.existing});

  @override
  ConsumerState<_WellForm> createState() => _WellFormState();
}

class _WellFormState extends ConsumerState<_WellForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _groupController;
  late final TextEditingController _prController;
  late bool _active;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _codeController = TextEditingController(text: e?.code ?? '');
    _groupController = TextEditingController(text: e?.group ?? '');
    final pr = e?.reservoirPressure;
    _prController = TextEditingController(
      text: pr == null ? '' : (pr == pr.roundToDouble() ? pr.toInt().toString() : pr.toString()),
    );
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _groupController.dispose();
    _prController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(wellsControllerProvider.notifier);
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);

    final prText = _prController.text.trim().replaceAll(',', '.');
    final reservoirPressure = prText.isEmpty ? null : double.parse(prText);
    if (_isNew) {
      await controller.addWell(
        code: _codeController.text.trim(),
        name: _nameController.text.trim(),
        active: _active,
        group: _groupController.text.trim(),
        reservoirPressure: reservoirPressure,
      );
      _showSnack(s('wellsManageAdded'));
    } else {
      await controller.updateWell(Well(
        id: widget.existing!.id,
        code: _codeController.text.trim(),
        name: _nameController.text.trim(),
        active: _active,
        group: _groupController.text.trim(),
        reservoirPressure: reservoirPressure,
      ));
      _showSnack(s('wellsManageUpdated'));
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s('wellsManageDeleteConfirmTitle')),
        content: Text(s('wellsManageDeleteConfirmBody')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s('wellsManageDelete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(wellsControllerProvider.notifier).deleteWell(widget.existing!.id);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('wellsManageDeleted'))));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;
    final existingGroups = ref.watch(wellsControllerProvider.notifier).groups;
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
                    _isNew ? s('wellsManageNew') : s('wellsManageEdit'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!_isNew)
                  IconButton(
                    onPressed: _delete,
                    icon: Icon(Icons.delete_outline, color: scheme.error),
                    tooltip: s('wellsManageDelete'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: s('wellsManageNameLabel'), hintText: s('wellsManageNameHint')),
              validator: (v) => (v ?? '').trim().isEmpty ? s('wellsManageInvalidName') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codeController,
              decoration: InputDecoration(labelText: s('wellsManageCodeLabel'), hintText: s('wellsManageCodeHint')),
              validator: (v) => (v ?? '').trim().isEmpty ? s('wellsManageInvalidCode') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _groupController,
              decoration: InputDecoration(labelText: s('wellsManageGroupLabel'), hintText: s('wellsManageGroupHint')),
            ),
            if (existingGroups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final group in existingGroups)
                    ActionChip(
                      label: Text(group),
                      onPressed: () => setState(() => _groupController.text = group),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _prController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: s('reservoirPressureLabel'),
                helperText: s('reservoirPressureHelper'),
                suffixText: 'bar',
              ),
              validator: (v) {
                final text = (v ?? '').trim().replaceAll(',', '.');
                if (text.isEmpty) return null;
                final value = double.tryParse(text);
                return value == null || value <= 0 ? s('adminInvalidThreshold') : null;
              },
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s('wellsManageActiveLabel')),
              value: _active,
              activeTrackColor: accentColor,
              onChanged: (value) => setState(() => _active = value),
            ),
            const SizedBox(height: 16),
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
                child: Text(s('wellsManageSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
