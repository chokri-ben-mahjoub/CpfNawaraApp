import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/units/unit_system.dart';
import '../../../core/widgets/responsive.dart';
import '../../setup/presentation/widgets/firebase_project_picker.dart';
import 'widgets/admin_widgets.dart';

Color wellStatusColor(WellStatus status, ColorScheme scheme) => switch (status) {
  WellStatus.producing => Colors.green.shade600,
  WellStatus.testing => const Color(0xFF1E88E5),
  WellStatus.injecting => const Color(0xFF7E57C2),
  WellStatus.shutIn => scheme.outline,
  WellStatus.abandoned => scheme.error,
};

/// Puits : nom, champ, type, statut, coordonnées (Administration).
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
    String coords(Well w) =>
        w.hasLocation ? '${w.latitude!.toStringAsFixed(5)}, ${w.longitude!.toStringAsFixed(5)}' : '—';

    return Scaffold(
      appBar: AppBar(title: Text(s('wellsManageTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: Text(s('wellsManageAdd')),
      ),
      body: wells.isEmpty
          ? Center(
              child: Text(s('wellsManageEmpty'), style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          : ListView(
              padding: pagePadding(context, top: 12, bottom: 130),
              children: [
                AdminTable<Well>(
                  items: wells,
                  onTap: (w) => _openEditor(context, existing: w),
                  columns: [
                    AdminColumn(
                      s('wellsManageCodeLabel'),
                      (w) => Text(w.code, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    AdminColumn(s('wellsManageNameLabel'), (w) => Text(w.name)),
                    AdminColumn(s('wellsManageGroupLabel'), (w) => Text(w.group.isEmpty ? '—' : w.group)),
                    AdminColumn(s('wellTypeLabel'), (w) => Text(s(wellTypeLabelKey(w.type)))),
                    AdminColumn(s('wellStatusLabel'), (w) => _StatusPill(status: w.status)),
                    AdminColumn(s('wellCoordinates'), (w) => Text(coords(w), style: const TextStyle(fontSize: 12.5))),
                  ],
                  card: (context, w) => AdminCard(
                    leading: IconBadge(Icons.water_drop_outlined, color: wellStatusColor(w.status, scheme)),
                    title: '${w.name} (${w.code})',
                    subtitle: [
                      w.group.trim().isEmpty ? s('statsUnassignedGroup') : w.group,
                      if (w.type.isNotEmpty) s(wellTypeLabelKey(w.type)),
                    ].join(' · '),
                    trailing: _StatusPill(status: w.status),
                    onTap: () => _openEditor(context, existing: w),
                  ),
                ),
              ],
            ),
    );
  }

  void _openEditor(BuildContext context, {Well? existing}) {
    showAdminSheet<void>(context, builder: (sheetContext) => _WellForm(existing: existing));
  }
}

class _StatusPill extends ConsumerWidget {
  final WellStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = wellStatusColor(status, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
      child: Text(
        tr(ref.watch(localeProvider), status.labelKey),
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5),
      ),
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
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  late String _type;
  late WellStatus _status;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _codeController = TextEditingController(text: e?.code ?? '');
    _groupController = TextEditingController(text: e?.group ?? '');
    _prController = TextEditingController(text: decimalText(e?.reservoirPressure));
    _latController = TextEditingController(text: e?.latitude?.toString() ?? '');
    _lngController = TextEditingController(text: e?.longitude?.toString() ?? '');
    _type = e?.type ?? '';
    _status = e?.status ?? WellStatus.producing;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _groupController.dispose();
    _prController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(wellsControllerProvider.notifier);
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);

    final reservoirPressure = parseDecimal(_prController.text);
    final latitude = parseDecimal(_latController.text);
    final longitude = parseDecimal(_lngController.text);
    final messenger = ScaffoldMessenger.of(context);
    if (_isNew) {
      await controller.addWell(
        code: _codeController.text.trim(),
        name: _nameController.text.trim(),
        active: _status.isActive,
        group: _groupController.text.trim(),
        reservoirPressure: reservoirPressure,
        type: _type,
        status: _status,
        latitude: latitude,
        longitude: longitude,
      );
      messenger.showSnackBar(SnackBar(content: Text(s('wellsManageAdded'))));
    } else {
      await controller.updateWell(
        Well(
          id: widget.existing!.id,
          code: _codeController.text.trim(),
          name: _nameController.text.trim(),
          active: _status.isActive,
          group: _groupController.text.trim(),
          reservoirPressure: reservoirPressure,
          type: _type,
          status: _status,
          latitude: latitude,
          longitude: longitude,
        ),
      );
      messenger.showSnackBar(SnackBar(content: Text(s('wellsManageUpdated'))));
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final confirmed = await confirmDanger(
      context,
      title: s('wellsManageDeleteConfirmTitle'),
      body: s('wellsManageDeleteConfirmBody'),
      confirm: s('wellsManageDelete'),
      cancel: s('cancel'),
    );
    if (!confirmed) return;
    await ref.read(wellsControllerProvider.notifier).deleteWell(widget.existing!.id);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('wellsManageDeleted'))));
    }
  }

  String? _coordValidator(String? v, double limit, String Function(String) s) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return null;
    final value = parseDecimal(text);
    return value == null || value.abs() > limit ? s('wellInvalidCoordinate') : null;
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;
    final existingGroups = ref.watch(wellsControllerProvider.notifier).groups;
    String s(String key) => tr(locale, key);
    final lat = parseDecimal(_latController.text);
    final lng = parseDecimal(_lngController.text);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          ResponsiveWrapGrid(
            minItemWidth: 240,
            spacing: 12,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: s('wellsManageNameLabel'), hintText: s('wellsManageNameHint')),
                validator: (v) => (v ?? '').trim().isEmpty ? s('wellsManageInvalidName') : null,
              ),
              TextFormField(
                controller: _codeController,
                decoration: InputDecoration(labelText: s('wellsManageCodeLabel'), hintText: s('wellsManageCodeHint')),
                validator: (v) => (v ?? '').trim().isEmpty ? s('wellsManageInvalidCode') : null,
              ),
            ],
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
                  ActionChip(label: Text(group), onPressed: () => setState(() => _groupController.text = group)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          ResponsiveWrapGrid(
            minItemWidth: 240,
            spacing: 12,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: wellTypeKeys.contains(_type) ? _type : '',
                decoration: InputDecoration(labelText: s('wellTypeLabel')),
                items: [
                  DropdownMenuItem(value: '', child: Text(s('wellTypeNone'))),
                  for (final key in wellTypeKeys) DropdownMenuItem(value: key, child: Text(s(wellTypeLabelKey(key)))),
                ],
                onChanged: (v) => setState(() => _type = v ?? ''),
              ),
              DropdownButtonFormField<WellStatus>(
                isExpanded: true,
                initialValue: _status,
                decoration: InputDecoration(labelText: s('wellStatusLabel')),
                items: [for (final st in WellStatus.values) DropdownMenuItem(value: st, child: Text(s(st.labelKey)))],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s(_status.isActive ? 'wellStatusActiveHint' : 'wellStatusInactiveHint'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ResponsiveWrapGrid(
            minItemWidth: 200,
            spacing: 12,
            children: [
              TextFormField(
                controller: _latController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: s('wellLatitude'), hintText: '32.12345'),
                validator: (v) => _coordValidator(v, 90, s),
                onChanged: (_) => setState(() {}),
              ),
              TextFormField(
                controller: _lngController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: s('wellLongitude'), hintText: '9.12345'),
                validator: (v) => _coordValidator(v, 180, s),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          if (lat != null && lng != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => openExternalLink('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text(s('wellOpenMap')),
              ),
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _prController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: s('reservoirPressureLabel'),
              helperText: s('reservoirPressureHelper'),
              suffixText: Units.unit('bar'),
            ),
            validator: (v) {
              final text = (v ?? '').trim();
              if (text.isEmpty) return null;
              final value = parseDecimal(text);
              return value == null || value <= 0 ? s('adminInvalidThreshold') : null;
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              child: Text(s('wellsManageSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
