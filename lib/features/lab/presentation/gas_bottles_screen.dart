import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/lab/gas_bottle_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../admin/presentation/widgets/admin_widgets.dart';

String _fmtPressure(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Bouteilles de gaz pressurisées du laboratoire : relevé manuel (pression,
/// statut, emplacement) repris en fin de rapport usine (« Laboratory
/// Pressurized Gas Bottles Survey »), voir Réglages › Exports PDF.
class GasBottlesScreen extends ConsumerWidget {
  const GasBottlesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final bottles = ref.watch(gasBottleControllerProvider);
    String s(String key) => tr(locale, key);

    return Scaffold(
      appBar: AppBar(title: Text(s('gasBottlesTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAdminSheet<void>(context, builder: (_) => const _GasBottleFormSheet()),
        icon: const Icon(Icons.add),
        label: Text(s('gasBottlesAdd')),
      ),
      body: bottles.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.propane_tank_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(s('gasBottlesEmpty'), textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView(
              padding: pagePadding(context, top: 12, bottom: 100),
              children: [
                Text(s('gasBottlesHint'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                const SizedBox(height: 14),
                AdminTable<GasBottle>(
                  items: bottles,
                  onTap: (b) => showAdminSheet<void>(context, builder: (_) => _GasBottleFormSheet(existing: b)),
                  columns: [
                    AdminColumn(s('gasBottlesColCylinder'), (b) => Text(b.label, style: const TextStyle(fontWeight: FontWeight.w700))),
                    AdminColumn(s('gasBottlesColPressure'), (b) => Text('${_fmtPressure(b.pressure)} bars'), numeric: true),
                    AdminColumn(s('gasBottlesColLocation'), (b) => Text(b.location.isEmpty ? '—' : b.location)),
                  ],
                  card: (context, b) => AdminCard(
                    leading: const IconBadge(Icons.propane_tank_outlined, color: accentColor),
                    title: b.label,
                    subtitle: '${_fmtPressure(b.pressure)} bars · ${b.location.isEmpty ? '—' : b.location}',
                    onTap: () => showAdminSheet<void>(context, builder: (_) => _GasBottleFormSheet(existing: b)),
                  ),
                ),
              ],
            ),
    );
  }
}

class _GasBottleFormSheet extends ConsumerStatefulWidget {
  final GasBottle? existing;
  const _GasBottleFormSheet({this.existing});

  @override
  ConsumerState<_GasBottleFormSheet> createState() => _GasBottleFormSheetState();
}

class _GasBottleFormSheetState extends ConsumerState<_GasBottleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _pressure;
  late final TextEditingController _location;
  late String _status;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _pressure = TextEditingController(text: e == null ? '' : _fmtPressure(e.pressure));
    _location = TextEditingController(text: e?.location ?? '');
    _status = e?.status ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _pressure.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(gasBottleControllerProvider.notifier);
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final messenger = ScaffoldMessenger.of(context);
    final pressure = double.tryParse(_pressure.text.trim().replaceAll(',', '.')) ?? 0;

    if (_isNew) {
      await controller.add(
        name: _name.text.trim(),
        status: _status.trim(),
        pressure: pressure,
        location: _location.text.trim(),
      );
      messenger.showSnackBar(SnackBar(content: Text(s('gasBottlesAdded'))));
    } else {
      await controller.update(
        widget.existing!.copyWith(
          name: _name.text.trim(),
          status: _status.trim(),
          pressure: pressure,
          location: _location.text.trim(),
        ),
      );
      messenger.showSnackBar(SnackBar(content: Text(s('gasBottlesUpdated'))));
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final confirmed = await confirmDanger(
      context,
      title: s('gasBottlesDeleteConfirmTitle'),
      body: s('gasBottlesDeleteConfirmBody'),
      confirm: s('gasBottlesDelete'),
      cancel: s('cancel'),
    );
    if (!confirmed) return;
    await ref.read(gasBottleControllerProvider.notifier).delete(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isNew ? s('gasBottlesNew') : s('gasBottlesEdit'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: s('gasBottlesColCylinder'), hintText: s('gasBottlesNameHint')),
            validator: (v) => (v ?? '').trim().isEmpty ? s('gasBottlesInvalidName') : null,
          ),
          const SizedBox(height: 12),
          Text(s('gasBottlesStatus'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final status in gasBottleStatusSuggestions)
                ChoiceChip(
                  label: Text(status),
                  selected: _status == status,
                  onSelected: (v) => setState(() => _status = v ? status : ''),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ResponsiveWrapGrid(
            minItemWidth: 200,
            spacing: 12,
            children: [
              TextFormField(
                controller: _pressure,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: s('gasBottlesColPressure'), suffixText: 'bars'),
                validator: (v) {
                  final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  return value == null || value < 0 ? s('gasBottlesInvalidPressure') : null;
                },
              ),
              TextFormField(
                controller: _location,
                decoration: InputDecoration(labelText: s('gasBottlesColLocation')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final loc in gasBottleLocationSuggestions)
                ActionChip(label: Text(loc), onPressed: () => setState(() => _location.text = loc)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              child: Text(s('gasBottlesSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _delete,
                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                label: Text(s('gasBottlesDelete'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
