import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/admin_widgets.dart';

/// Circuits de l'usine CPF : regroupent les points de prélèvement (couleur,
/// icône, modèle de paramètres par défaut). Les 4 circuits intégrés
/// (condensat, eau, gaz, amine) peuvent être renommés ; un administrateur
/// peut en ajouter d'autres (Administration).
class CircuitsScreen extends ConsumerWidget {
  const CircuitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final plant = ref.watch(plantControllerProvider);
    String s(String key) => tr(locale, key);

    int pointCount(PlantCircuit c) => plant.points.where((p) => p.circuit.id == c.id).length;

    return Scaffold(
      appBar: AppBar(title: Text(s('adminCircuits'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: Text(s('circuitsAdd')),
      ),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 130),
        children: [
          Text(s('circuitsIntro'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
          const SizedBox(height: 12),
          AdminTable<PlantCircuit>(
            items: plant.circuits,
            onTap: (c) => _openEditor(context, existing: c),
            columns: [
              AdminColumn(
                s('circuitsName'),
                (c) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(c.icon, size: 18, color: c.color),
                    const SizedBox(width: 8),
                    Text(s(c.labelKey)),
                  ],
                ),
              ),
              AdminColumn(s('pointsProfile'), (c) => Text(s(plantProfileLabelKeys[c.defaultProfile] ?? c.defaultProfile))),
              AdminColumn(s('circuitsPointCountCol'), (c) => Text('${pointCount(c)}')),
            ],
            card: (context, c) => AdminCard(
              leading: IconBadge(c.icon, color: c.color),
              title: s(c.labelKey),
              subtitle: fill(s('circuitsPointCountLabel'), {'n': '${pointCount(c)}'}),
              onTap: () => _openEditor(context, existing: c),
            ),
          ),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, {PlantCircuit? existing}) {
    showAdminSheet<void>(context, builder: (_) => _CircuitForm(existing: existing));
  }
}

class _CircuitForm extends ConsumerStatefulWidget {
  final PlantCircuit? existing;
  const _CircuitForm({this.existing});

  @override
  ConsumerState<_CircuitForm> createState() => _CircuitFormState();
}

class _CircuitFormState extends ConsumerState<_CircuitForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _profile;
  late int _colorValue;
  late String _iconKey;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    final locale = ref.read(localeProvider);
    final circuits = ref.read(plantControllerProvider).circuits;
    _name = TextEditingController(text: c == null ? '' : tr(locale, c.labelKey));
    _profile = c?.defaultProfile ?? 'condensate';
    _colorValue = c?.colorValue ?? circuitColorOptions[circuits.length % circuitColorOptions.length].toARGB32();
    _iconKey = c?.iconKey ?? circuitIconOptions.keys.elementAt(circuits.length % circuitIconOptions.length);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final locale = ref.read(localeProvider);
    final existing = widget.existing;
    final typed = _name.text.trim();
    // Si le texte n'a pas changé par rapport à la traduction affichée, on
    // garde la clé de traduction d'origine (sinon un simple "Enregistrer"
    // sans modification figerait la langue courante).
    final labelKey = existing != null && typed == tr(locale, existing.labelKey) ? existing.labelKey : typed;
    final controller = ref.read(plantControllerProvider.notifier);
    await controller.saveCircuit(
      PlantCircuit(
        id: existing?.id ?? '',
        labelKey: labelKey,
        colorValue: _colorValue,
        iconKey: _iconKey,
        defaultProfile: _profile,
        sortOrder: existing?.sortOrder ?? controller.nextCircuitSortOrder,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(locale, 'circuitsSaved'))));
  }

  Future<void> _delete() async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final existing = widget.existing!;
    final inUse = ref.read(plantControllerProvider).points.any((p) => p.circuit.id == existing.id);
    if (inUse) {
      setState(() => _error = s('circuitsInUse'));
      return;
    }
    final ok = await confirmDanger(
      context,
      title: s('circuitsDeleteTitle'),
      body: s('circuitsDeleteBody'),
      confirm: s('recordDelete'),
      cancel: s('cancel'),
    );
    if (!ok) return;
    await ref.read(plantControllerProvider.notifier).deleteCircuit(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);

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
                  s(_isNew ? 'circuitsNew' : 'circuitsEdit'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (!_isNew)
                IconButton(
                  tooltip: s('recordDelete'),
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: s('circuitsName'), hintText: s('circuitsNameHint')),
            validator: (v) => (v ?? '').trim().isEmpty ? s('wellsManageInvalidName') : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _profile,
            decoration: InputDecoration(labelText: s('pointsProfile'), helperText: s('pointsProfileHint')),
            items: [
              for (final e in plantProfileLabelKeys.entries) DropdownMenuItem(value: e.key, child: Text(s(e.value))),
            ],
            onChanged: (v) => setState(() => _profile = v ?? _profile),
          ),
          const SizedBox(height: 16),
          Text(s('circuitsColor'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in circuitColorOptions)
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _colorValue = color.toARGB32()),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _colorValue == color.toARGB32() ? scheme.onSurface : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(s('circuitsIcon'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in circuitIconOptions.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _iconKey = entry.key),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _iconKey == entry.key
                          ? Color(_colorValue).withValues(alpha: 0.18)
                          : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _iconKey == entry.key ? Color(_colorValue) : scheme.outlineVariant.withValues(alpha: 0.4),
                        width: _iconKey == entry.key ? 2 : 1,
                      ),
                    ),
                    child: Icon(entry.value, color: _iconKey == entry.key ? Color(_colorValue) : scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              onPressed: _save,
              child: Text(s('wellsManageSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
