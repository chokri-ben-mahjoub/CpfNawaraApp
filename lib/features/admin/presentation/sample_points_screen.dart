import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import 'params_screen.dart';
import 'widgets/admin_widgets.dart';

/// Points de prélèvement du circuit CPF : code, circuit, équipement et
/// paramètres analysés (Administration).
class SamplePointsScreen extends ConsumerWidget {
  const SamplePointsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final plant = ref.watch(plantControllerProvider);
    final points = plant.points;
    String s(String key) => tr(locale, key);

    return Scaffold(
      appBar: AppBar(title: Text(s('adminPoints'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: Text(s('pointsAdd')),
      ),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 130),
        children: [
          Text(s('pointsIntro'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
          for (final circuit in plant.circuits) ...[
            AdminSectionTitle(s(circuit.labelKey)),
            AdminTable<SamplePoint>(
              items: points.where((p) => p.circuit == circuit).toList(),
              onTap: (p) => _openEditor(context, existing: p),
              columns: [
                AdminColumn(
                  s('pointsCode'),
                  (p) => Text(
                    p.code,
                    style: TextStyle(fontWeight: FontWeight.w800, color: circuit.color),
                  ),
                ),
                AdminColumn(s('pointsName'), (p) => Text(p.name)),
                AdminColumn(s('pointsEquipment'), (p) => Text(p.equipment.isEmpty ? '—' : p.equipment)),
                AdminColumn(
                  s('pointsParams'),
                  (p) =>
                      Text(p.params.map((x) => s(x.labelKey)).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                AdminColumn(s('colStatus'), (p) => Text(s(p.active ? 'usersActive' : 'usersInactive'))),
              ],
              card: (context, p) => AdminCard(
                leading: IconBadge(circuit.icon, color: p.active ? circuit.color : scheme.outline),
                title: '${p.code} — ${p.name}',
                subtitle:
                    '${p.equipment.isEmpty ? '' : '${p.equipment} · '}'
                    '${fill(s('pointsParamCount'), {'n': '${p.params.length}'})}'
                    '${p.active ? '' : ' · ${s('usersInactive')}'}',
                onTap: () => _openEditor(context, existing: p),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, {SamplePoint? existing}) {
    showAdminSheet<void>(context, builder: (_) => _PointForm(existing: existing));
  }
}

class _PointForm extends ConsumerStatefulWidget {
  final SamplePoint? existing;
  const _PointForm({this.existing});

  @override
  ConsumerState<_PointForm> createState() => _PointFormState();
}

class _PointFormState extends ConsumerState<_PointForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _equipment;
  late PlantCircuit _circuit;
  late String _profile;
  late List<String> _params;
  late bool _active;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _code = TextEditingController(text: p?.code ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _equipment = TextEditingController(text: p?.equipment ?? '');
    _circuit = p?.circuit ?? ref.read(plantControllerProvider).circuits.first;
    _profile = p?.profile ?? _circuit.defaultProfile;
    _params = [for (final x in p?.storedParams ?? paramsForProfile(_profile)) x.key];
    _active = p?.active ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _equipment.dispose();
    super.dispose();
  }

  void _setProfile(String profile) {
    setState(() {
      _profile = profile;
      _params = [for (final x in paramsForProfile(profile)) x.key];
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final locale = ref.read(localeProvider);
    if (_params.isEmpty) {
      setState(() => _error = tr(locale, 'pointsNoParam'));
      return;
    }
    final controller = ref.read(plantControllerProvider.notifier);
    final code = _code.text.trim().toUpperCase();
    final duplicate = ref
        .read(plantControllerProvider)
        .points
        .any((p) => p.code.toUpperCase() == code && p.id != widget.existing?.id);
    if (duplicate) {
      setState(() => _error = tr(locale, 'pointsDuplicateCode'));
      return;
    }
    // Paramètres identiques à ceux du profil : rien à mémoriser (le point
    // suit le profil).
    final profileKeys = [for (final x in paramsForProfile(_profile)) x.key];
    final sameAsProfile = profileKeys.length == _params.length && profileKeys.every(_params.contains);
    final ordered = [
      for (final x in plantParamCatalog)
        if (_params.contains(x.key)) x.key,
    ];
    await controller.savePoint(
      SamplePoint(
        id: widget.existing?.id ?? '',
        code: code,
        circuit: _circuit,
        name: _name.text.trim(),
        equipment: _equipment.text.trim(),
        profile: _profile,
        sortOrder: widget.existing?.sortOrder ?? controller.nextSortOrder,
        active: _active,
        paramKeys: sameAsProfile
            ? null
            : [...profileKeys.where(_params.contains), ...ordered.where((k) => !profileKeys.contains(k))],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(locale, 'pointsSaved'))));
  }

  Future<void> _delete() async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final ok = await confirmDanger(
      context,
      title: s('pointsDeleteTitle'),
      body: s('pointsDeleteBody'),
      confirm: s('recordDelete'),
      cancel: s('cancel'),
    );
    if (!ok) return;
    await ref.read(plantControllerProvider.notifier).deletePoint(widget.existing!.id);
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
                  s(_isNew ? 'pointsNew' : 'pointsEdit'),
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
          ResponsiveWrapGrid(
            minItemWidth: 200,
            spacing: 12,
            children: [
              TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: s('pointsCode'), hintText: 'C1, W2, G3, LA...'),
                validator: (v) => (v ?? '').trim().isEmpty ? s('wellsManageInvalidCode') : null,
              ),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: s('pointsName'), hintText: 'Inlet Separator'),
                validator: (v) => (v ?? '').trim().isEmpty ? s('wellsManageInvalidName') : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _equipment,
            decoration: InputDecoration(labelText: s('pointsEquipment'), hintText: s('pointsEquipmentHint')),
          ),
          const SizedBox(height: 16),
          Text(s('pointsCircuit'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in ref.watch(plantControllerProvider).circuits)
                ChoiceChip(
                  avatar: Icon(c.icon, size: 18, color: c.color),
                  label: Text(s(c.labelKey)),
                  selected: _circuit == c,
                  onSelected: (_) {
                    setState(() => _circuit = c);
                    if (_isNew) _setProfile(c.defaultProfile);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _profile,
            decoration: InputDecoration(labelText: s('pointsProfile'), helperText: s('pointsProfileHint')),
            items: [
              for (final e in plantProfileLabelKeys.entries) DropdownMenuItem(value: e.key, child: Text(s(e.value))),
            ],
            onChanged: (v) => _setProfile(v ?? _profile),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text(s('pointsParams'), style: const TextStyle(fontWeight: FontWeight.w800))),
              TextButton.icon(
                onPressed: () async {
                  final key = await showPlantParamForm(context);
                  if (key != null && mounted) setState(() => _params.add(key));
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(s('paramsAdd')),
              ),
            ],
          ),
          Text(s('pointsParamsHint'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in plantParamCatalog)
                FilterChip(
                  label: Text('${s(p.labelKey)}${p.unit.isEmpty ? '' : ' (${p.displayed().unit})'}'),
                  selected: _params.contains(p.key),
                  selectedColor: accentColor.withValues(alpha: 0.18),
                  onSelected: (on) => setState(() {
                    _error = null;
                    on ? _params.add(p.key) : _params.remove(p.key);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s('pointsActive')),
            subtitle: Text(s('pointsActiveHint')),
            value: _active,
            activeTrackColor: accentColor,
            onChanged: (v) => setState(() => _active = v),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
            ),
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
